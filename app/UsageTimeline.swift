import Foundation

struct UsageSample:Codable,Equatable {
    let provider:String
    let account:String?
    let window:String
    let durationMinutes:Int?
    let observed:Double
    let reset:Double?
    let remaining:Double
}
struct UsageProjection:Codable {
    let provider:String
    let window:String
    let remaining:Double
    let observedAt:Double
    let resetAt:Double?
    let observedHours:Double
    let sampleCount:Int
    let percentPerHour:Double?
    let estimatedExhaustionAt:Double?
    let riskBeforeReset:Bool?
    var identityEvidence:String="provider"
    var reason:String?=nil
    var historyPeriodCount:Int=0
    var confirmedRenewalCount:Int=0
    var periodFirstObservedRemainingPercent:Double?=nil
    var periodObservedHours:Double?=nil
    var recentPercentPerHour:Double?=nil
    var baselinePercentPerHour:Double?=nil
    var historicalCalendarPercentPerHour:Double?=nil
    var historicalCalendarHours:Double=0
    var calendarPercentPerHour:Double?=nil
    var calendarHours:Double=0
}
struct UsageTimeline:Codable {
    private(set) var samples:[UsageSample]=[]
    static let retention:TimeInterval=7*86400
    @discardableResult mutating func ingest(_ snapshot:QuotaSnapshot,now:Date=Date(),connectionID:String?=nil)->Bool {
        let time=snapshot.queriedAt.timeIntervalSince1970
        let cutoff=now.timeIntervalSince1970-Self.retention
        guard time.isFinite,time>0,time<=now.timeIntervalSince1970+5,time>=cutoff else{return false}
        var changed=false
        for window in snapshot.windows {
            guard let remaining=window.remaining,remaining.isFinite,(0...100).contains(remaining) else{continue}
            if let reset=window.reset,(!reset.isFinite || reset<=time) {continue}
            let sample=UsageSample(provider:snapshot.effectiveProvider,account:snapshot.identityFingerprint ?? connectionID,window:window.name,durationMinutes:window.durationMinutes,observed:time,reset:window.reset,remaining:remaining)
            if let last=samples.last(where:{$0.provider==sample.provider && $0.account==sample.account && $0.window==sample.window && $0.durationMinutes==sample.durationMinutes}) {
                guard time>last.observed+0.001 else{continue}
                // Preserve changing measures; unchanged observations need only a 30-minute heartbeat.
                if last.remaining==sample.remaining,last.reset==sample.reset,time-last.observed<1800 {continue}
            }
            samples.append(sample);changed=true
        }
        let before=samples.count;samples.removeAll{$0.observed<cutoff}
        return changed || before != samples.count
    }
    @discardableResult mutating func restoreRecordedObservations(_ states:[String:ResetState],now:Date=Date())->Bool {
        var restored=UsageTimeline()
        var snapshots:[QuotaSnapshot]=[]
        for (provider,state) in states {
            var recorded=state.transitions.flatMap {[$0.previous,$0.current]}
            if let baseline=state.baseline {recorded.append(baseline)}
            for event in state.history {
                var value=QuotaSnapshot(queriedAt:event.detectedAt,windows:[QuotaWindow(name:event.window,remaining:100-event.usedPercent,durationMinutes:event.durationMinutes,reset:event.serviceResetAt)])
                value.provider=event.provider ?? provider;value.identityFingerprint=event.identityFingerprint;value.bucketID=event.bucketID
                recorded.append(value)
            }
            for var value in recorded {if value.provider==nil {value.provider=provider};snapshots.append(value)}
        }
        for value in snapshots.sorted(by:{$0.queriedAt<$1.queriedAt}) {_=restored.ingest(value,now:now,connectionID:value.credentialScope)}
        let original=samples
        for value in restored.samples {
            let duplicate=samples.contains {$0.provider==value.provider && $0.account==value.account && $0.window==value.window && $0.durationMinutes==value.durationMinutes && abs($0.observed-value.observed)<0.001}
            if !duplicate {samples.append(value)}
        }
        samples.sort {$0.observed<$1.observed}
        return original != samples
    }
    private static func completeDays(_ rows:[UsageSample],end:UsageSample,maximumGap:TimeInterval)->(Double,Double)? {
        guard let first=rows.first,end.observed>first.observed else{return nil}
        let days=min(7,Int((end.observed-first.observed)/86400))
        guard days>=1 else{return nil}
        for count in stride(from:days,through:1,by:-1) {
            let target=end.observed-Double(count)*86400
            guard let anchor=rows.last(where:{$0.observed<=target && target-$0.observed<=min(3600,maximumGap)}),
                  (0...100).contains(anchor.remaining),(0...100).contains(end.remaining),anchor.remaining>=end.remaining else{continue}
            return (end.observed-anchor.observed,anchor.remaining-end.remaining)
        }
        return nil
    }
    func projections(for snapshot:QuotaSnapshot,now:Date=Date(),maximumGap:TimeInterval=3600,connectionID:String?=nil,renewals:[RenewalEntry]=[],calendar:Calendar = .current)->[UsageProjection] {
        let end=now.timeIntervalSince1970,cutoff=end-Self.retention
        guard snapshot.queriedAt.timeIntervalSince1970.isFinite,snapshot.queriedAt.timeIntervalSince1970<=end+5 else{return []}
        return snapshot.windows.compactMap { window in
            guard let remaining=window.remaining,remaining.isFinite,(0...100).contains(remaining) else{return nil}
            let rows=samples.filter{$0.provider==snapshot.effectiveProvider && $0.account==(snapshot.identityFingerprint ?? connectionID) && $0.window==window.name && $0.durationMinutes==window.durationMinutes && $0.observed>=cutoff && $0.observed<=min(end+5,snapshot.queriedAt.timeIntervalSince1970+0.001)}.sorted{$0.observed<$1.observed}
            var seconds=0.0,consumed=0.0,pairs=0
            var recentSeconds=0.0,recentConsumed=0.0,recentPairs=0
            var priorSeconds=0.0,priorConsumed=0.0,priorPairs=0
            let recentStart=snapshot.queriedAt.timeIntervalSince1970-6*3600
            let historyBands=(1...6).compactMap {day -> (Int,Double,Double)? in
                guard let start=calendar.date(byAdding:.day,value:-day,to:Date(timeIntervalSince1970:recentStart)),let end=calendar.date(byAdding:.day,value:-day,to:snapshot.queriedAt) else{return nil}
                return (day,start.timeIntervalSince1970,end.timeIntervalSince1970)
            }
            var matchedDays=Set<Int>()
            for (a,b) in zip(rows,rows.dropFirst()) {
                let gap=b.observed-a.observed
                guard gap>0,gap<=maximumGap,a.reset != nil,b.reset != nil,
                      abs(a.reset!-b.reset!)<60,b.remaining<=a.remaining else{continue}
                seconds += gap;consumed += a.remaining-b.remaining;pairs += 1
                if a.observed>=recentStart {recentSeconds += gap;recentConsumed += a.remaining-b.remaining;recentPairs += 1}
                else if let band=historyBands.first(where:{a.observed >= $0.1 && b.observed <= $0.2}) {
                    priorSeconds += gap;priorConsumed += a.remaining-b.remaining;priorPairs += 1;matchedDays.insert(band.0)
                }
            }
            // At least one hour and three comparable observations are required for a pace.
            let rate=(snapshot.identityFingerprint != nil || connectionID != nil) && seconds>=3600 && pairs>=2 ? consumed/(seconds/3600) : nil
            let identified=snapshot.identityFingerprint != nil || connectionID != nil
            let recentRate=identified && recentSeconds>=3600 && recentPairs>=2 ? recentConsumed/(recentSeconds/3600) : nil
            let priorRate=identified && priorSeconds>=3600 && priorPairs>=2 && matchedDays.count>=2 ? priorConsumed/(priorSeconds/3600) : nil
            var historyClockSeconds=0.0,historyClockConsumed=0.0
            if identified {
                let currentPeriodFirst=rows.first {row in
                    guard let reset=row.reset,let currentReset=window.reset else{return false}
                    return abs(reset-currentReset)<60
                }?.observed ?? snapshot.queriedAt.timeIntervalSince1970
                let periods=Dictionary(grouping:rows.filter {row in
                    guard let reset=row.reset,reset.isFinite,let currentReset=window.reset else{return false}
                    return abs(reset-currentReset)>=60
                },by:{$0.reset!})
                for period in periods.values {
                    let ordered=period.sorted{$0.observed<$1.observed}
                    guard let last=ordered.last,last.observed<currentPeriodFirst,
                          let interval=Self.completeDays(ordered,end:last,maximumGap:maximumGap) else{continue}
                    historyClockSeconds += interval.0
                    historyClockConsumed += interval.1
                }
            }
            let historyClockRate=historyClockSeconds>=86400 ? historyClockConsumed/(historyClockSeconds/3600) : nil
            let currentRows=rows.filter {row in
                guard let recordedReset=row.reset,let currentReset=window.reset else{return false}
                return abs(recordedReset-currentReset)<60
            }
            let endpoint=UsageSample(provider:snapshot.effectiveProvider,account:snapshot.identityFingerprint ?? connectionID,window:window.name,durationMinutes:window.durationMinutes,observed:snapshot.queriedAt.timeIntervalSince1970,reset:window.reset,remaining:remaining)
            let currentClock=identified ? Self.completeDays(currentRows,end:endpoint,maximumGap:maximumGap) : nil
            let currentClockRate=currentClock.map{$0.1/($0.0/3600)}
            let exhaustion=rate.flatMap {rate->Double? in
                guard rate>0 else{return nil}
                let date=snapshot.queriedAt.timeIntervalSince1970+remaining/rate*3600
                return date.isFinite ? date : nil
            }
            let reset=window.reset.flatMap{$0.isFinite && $0>end ? $0 : nil}
            let risk:Bool?
            if let reset=reset {risk=remaining==0 ? true : exhaustion.map{$0<reset} ?? (rate==0 ? false : nil)} else {risk=nil}
            let reason:String? = snapshot.identityFingerprint==nil && connectionID==nil ? "account_unidentified" : reset==nil ? "reset_unavailable" : rate==nil ? "insufficient_coverage" : nil
            let periods=renewals.filter {entry in
                entry.provider==snapshot.effectiveProvider && entry.minutes==window.durationMinutes && entry.window==quotaWindowLabel(window) && entry.startedAt>=cutoff && entry.startedAt<=end && entry.identity==snapshot.identityFingerprint
            }
            let firstInPeriod:UsageSample?
            if snapshot.identityFingerprint != nil || connectionID != nil {
                firstInPeriod=rows.first {row in
                guard let recordedReset=row.reset,let currentReset=window.reset else{return false}
                return abs(recordedReset-currentReset)<60 && row.observed<snapshot.queriedAt.timeIntervalSince1970-60
                }
            } else {firstInPeriod=nil}
            return UsageProjection(provider:snapshot.effectiveProvider,window:quotaWindowLabel(window),remaining:remaining,observedAt:snapshot.queriedAt.timeIntervalSince1970,resetAt:window.reset,observedHours:seconds/3600,sampleCount:rows.count,percentPerHour:rate,estimatedExhaustionAt:exhaustion,riskBeforeReset:risk,identityEvidence:snapshot.identityFingerprint != nil ? "provider" : connectionID != nil ? "local_credential_configuration" : "unknown",reason:reason,historyPeriodCount:periods.count,confirmedRenewalCount:periods.filter(\.detectedBetweenReadings).count,periodFirstObservedRemainingPercent:firstInPeriod?.remaining,periodObservedHours:firstInPeriod.map{(snapshot.queriedAt.timeIntervalSince1970-$0.observed)/3600},recentPercentPerHour:recentRate,baselinePercentPerHour:priorRate,historicalCalendarPercentPerHour:historyClockRate,historicalCalendarHours:historyClockSeconds/3600,calendarPercentPerHour:currentClockRate,calendarHours:(currentClock?.0 ?? 0)/3600)
        }
    }
}

func runUsageTimelineTests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL timeline: \(label)")};count += 1}
    let now=Date(timeIntervalSince1970:1_800_000_000)
    func snap(_ offset:Double,_ remaining:Double,_ reset:Double=10000,_ account:String="one")->QuotaSnapshot {
        var s=QuotaSnapshot(queriedAt:now.addingTimeInterval(offset),windows:[QuotaWindow(name:"5h",remaining:remaining,durationMinutes:300,reset:now.timeIntervalSince1970+reset)])
        s.provider="claude";s.identityFingerprint=account;return s
    }
    var timeline=UsageTimeline()
    check(timeline.ingest(snap(-3600,80),now:now),"first observation")
    check(!timeline.ingest(snap(-3600,80),now:now),"reread deduplicated")
    check(timeline.projections(for:snap(-3600,80),now:now)[0].percentPerHour==nil,"no invented past week")
    _=timeline.ingest(snap(-1800,60),now:now);_=timeline.ingest(snap(0,40),now:now)
    let p=timeline.projections(for:snap(0,40),now:now)[0]
    check(p.percentPerHour==40 && p.observedHours==1 && p.riskBeforeReset==true,"measured pace and depletion before reset")
    check(timeline.projections(for:snap(0,40,10000,"two"),now:now)[0].percentPerHour==nil,"accounts never mixed")
    check(!timeline.ingest(snap(20,20),now:now),"future sample rejected")
    check(!timeline.ingest(snap(-8*86400,80),now:now),"outside seven days rejected")
    check(!timeline.ingest(snap(0,Double.nan),now:now),"nonfinite rejected")
    var resets=UsageTimeline()
    _=resets.ingest(snap(-3600,10,5000),now:now);_=resets.ingest(snap(-1800,100,15000),now:now);_=resets.ingest(snap(0,90,15000),now:now)
    check(resets.projections(for:snap(0,90,15000),now:now)[0].percentPerHour==nil,"reset is not negative consumption or full interval evidence")
    check(timeline.projections(for:snap(0,40),now:now,maximumGap:300)[0].percentPerHour==nil,"unobserved long gaps excluded")
    let decoded=try! JSONDecoder().decode(UsageTimeline.self,from:JSONEncoder().encode(timeline))
    check(decoded.samples==timeline.samples,"private store roundtrip")
    var local=UsageTimeline()
    var first=snap(-3600,80);first.identityFingerprint=nil
    var second=snap(-1800,60);second.identityFingerprint=nil
    var third=snap(0,40);third.identityFingerprint=nil
    _=local.ingest(first,now:now,connectionID:"local:fixture1");_=local.ingest(second,now:now,connectionID:"local:fixture1");_=local.ingest(third,now:now,connectionID:"local:fixture1")
    check(local.projections(for:third,now:now,connectionID:"local:fixture1")[0].percentPerHour==40,"same locally managed credential can be measured")
    check(local.projections(for:third,now:now,connectionID:"local:fixture2")[0].percentPerHour==nil,"replacing key separates history")
    check(local.projections(for:third,now:now)[0].percentPerHour==nil,"unknown account without managed scope remains insufficient")
    check(local.projections(for:third,now:now,connectionID:"local:fixture1")[0].identityEvidence=="local_credential_configuration","local scope is not claimed as provider account identity")
    var sparse=UsageTimeline()
    for minute in 0...10080 {_=sparse.ingest(snap(Double(minute-10080)*60,80),now:now)}
    check(sparse.samples.count<=337,"seven days of unchanged minute reads are sampled every half hour")
    check(sparse.projections(for:snap(0,0),now:now)[0].riskBeforeReset==true,"zero remaining is exhausted even with zero measured pace")
    check(local.projections(for:third,now:now)[0].reason=="account_unidentified","missing identity is not misreported as missing samples")
    var noReset=third;noReset=QuotaSnapshot(queriedAt:now,windows:[QuotaWindow(name:"5h",remaining:40,durationMinutes:300,reset:nil)],identityFingerprint:"one")
    check(timeline.projections(for:noReset,now:now)[0].reason=="reset_unavailable","missing reset explained")
    check(timeline.projections(for:snap(30,20),now:now).isEmpty,"future projection rejected")
    var week=UsageTimeline()
    for hour in 0...168 {
        let offset=Double(hour-168)*3600
        let remaining=hour<3 ? 10-Double(hour) : 100-Double(hour-3)*99/165
        let reset=hour<3 ? -165*3600.0 : 3*3600.0
        _=week.ingest(snap(offset,remaining,reset),now:now)
    }
    let forecast=week.projections(for:snap(0,1,10800),now:now)[0]
    check(forecast.observedHours>=166 && forecast.riskBeforeReset==true && forecast.percentPerHour!>0.5,"seven-day history across a reset predicts depletion before next reset")
    let keyA=quotaCredentialScope(provider:"kimi",key:"fixture-key-a"),keyB=quotaCredentialScope(provider:"kimi",key:"fixture-key-b")
    check(keyA != keyB && keyA==quotaCredentialScope(provider:"kimi",key:"fixture-key-a") && !keyA.contains("fixture-key-a"),"continuity follows the queried key without storing its value")
    check(keyA != quotaCredentialScope(provider:"zai",key:"fixture-key-a"),"credential scopes are provider-specific")
    var codex=QuotaSnapshot(queriedAt:now,windows:[QuotaWindow(name:"primary",remaining:80,durationMinutes:10080,reset:now.timeIntervalSince1970+3600),QuotaWindow(name:"secondary",remaining:90,durationMinutes:300,reset:now.timeIntervalSince1970+3600)])
    codex.provider="codex"
    let labels=timeline.projections(for:codex,now:now).map(\.window)
    check(labels==["Semanal","5 horas"],"insight describes actual durations instead of provider-internal primary and secondary names")
    let encoded=String(data:try! JSONEncoder().encode(timeline.projections(for:codex,now:now)),encoding:.utf8)!
    check(!encoded.contains("primary") && !encoded.contains("secondary"),"model payload does not require guessing window semantics")
    var restored=UsageTimeline()
    _=restored.ingest(snap(0,40),now:now)
    var state=ResetState();state.transitions=[ResetTransition(previous:snap(-3600,80),current:snap(-1800,60),confirmed:false)]
    check(restored.restoreRecordedObservations(["claude":state],now:now),"older recorded observations are recovered even after a newer sample")
    check(restored.samples.count==3 && restored.projections(for:snap(0,40),now:now)[0].percentPerHour==40,"restored observations contribute to measured pace")
    check(!restored.restoreRecordedObservations(["claude":state],now:now),"history recovery is idempotent")
    let period=RenewalEntry(provider:"claude",bucket:"fixture",identity:"one",window:"5 horas",minutes:300,startedAt:now.timeIntervalSince1970-7200,endsAt:now.timeIntervalSince1970+10000,recordedAt:now,detectedBetweenReadings:true)
    let context=UsageTimeline().projections(for:snap(0,40),now:now,renewals:[period])[0]
    check(context.historyPeriodCount==1 && context.confirmedRenewalCount==1 && context.sampleCount==0 && context.percentPerHour==nil,"renewal history is visible without inventing usage measurements")
    var unidentified=UsageTimeline()
    _=unidentified.ingest(first,now:now);_=unidentified.ingest(second,now:now);_=unidentified.ingest(third,now:now)
    check(unidentified.samples.count==3 && unidentified.projections(for:third,now:now)[0].periodFirstObservedRemainingPercent==nil,"unidentified rows cannot provide a cross-account balance comparison")
    state.baseline=snap(-1200,55,-1000)
    state.history=[ResetRecord(id:"fixture",provider:"claude",identityFingerprint:"one",bucketID:"fixture",window:"5h",durationMinutes:300,detectedAt:now.addingTimeInterval(-900),previousServiceResetAt:now.timeIntervalSince1970-1000,serviceResetAt:now.timeIntervalSince1970+10000,previousUsedPercent:99,usedPercent:11)]
    _=restored.restoreRecordedObservations(["claude":state],now:now)
    check(restored.samples.contains{$0.observed==now.timeIntervalSince1970-1200 && $0.remaining==55},"baseline restored with original observation time")
    check(restored.samples.contains{$0.observed==now.timeIntervalSince1970-900 && $0.remaining==89},"event restores current usedPercent, never previousUsedPercent")
    check(!restored.samples.contains{$0.remaining==1},"untimed previous utilization is never reconstructed")
    check(!restored.restoreRecordedObservations(["claude":state],now:now),"baseline and event backfill also remain idempotent")
    var unknownPeriod=period;unknownPeriod.id="unknown";unknownPeriod.identity=nil
    var otherPeriod=period;otherPeriod.id="other";otherPeriod.identity="other"
    check(UsageTimeline().projections(for:snap(0,40),now:now,renewals:[period,unknownPeriod,otherPeriod])[0].historyPeriodCount==1,"known account does not inherit unknown or other-account periods")
    check(UsageTimeline().projections(for:third,now:now,renewals:[period,unknownPeriod,otherPeriod])[0].historyPeriodCount==1,"unidentified snapshot does not inherit identified account periods")
    var countOnly=context;countOnly.historyPeriodCount += 1;countOnly.confirmedRenewalCount += 1
    var encodedCounts=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(countOnly)) as! [String:Any]
    encodedCounts["sampleCount"]=30
    countOnly=try! JSONDecoder().decode(UsageProjection.self,from:JSONSerialization.data(withJSONObject:encodedCounts))
    check(InsightBasis.signature([context])==InsightBasis.signature([countOnly]),"counts alone do not invalidate a still-current insight")
    var changedReference=context;changedReference.periodFirstObservedRemainingPercent=80
    check(InsightBasis.signature([context]) != InsightBasis.signature([changedReference]),"changed historical reference invalidates the previous insight")
    var changing=UsageTimeline()
    // Three separate half-hour observations in each non-overlapping period.
    func trendSnapshot(_ offset:Double,_ balance:Double)->QuotaSnapshot {
        var value=QuotaSnapshot(queriedAt:now.addingTimeInterval(offset),windows:[QuotaWindow(name:"week",remaining:balance,durationMinutes:10080,reset:now.timeIntervalSince1970+86400)])
        value.provider="codex";value.identityFingerprint="one";return value
    }
    let boundaryReadings:[(Double,Double)]=[(-176400,100),(-174600,99),(-172800,98),(-108900,98),(-107100,90),(-90000,90),(-88200,89),(-86400,88),(-22500,88),(-20700,87),(-3600,80),(-1800,76),(0,72)]
    for (offset,balance) in boundaryReadings {
        _=changing.ingest(trendSnapshot(offset,balance),now:now)
    }
    var utc=Calendar(identifier:.gregorian);utc.timeZone=TimeZone(secondsFromGMT:0)!
    let compared=changing.projections(for:trendSnapshot(0,72),now:now,calendar:utc)[0]
    check(compared.recentPercentPerHour==8 && compared.baselinePercentPerHour==2,"matched previous days and current period exclude the pair crossing the six-hour boundary")
    var historicalClock=UsageTimeline()
    func calendarSnapshot(_ offset:Double,_ balance:Double,_ reset:Double)->QuotaSnapshot {
        var value=QuotaSnapshot(queriedAt:now.addingTimeInterval(offset),windows:[QuotaWindow(name:"week",remaining:balance,durationMinutes:10080,reset:now.timeIntervalSince1970+reset)])
        value.provider="codex";value.identityFingerprint="one";return value
    }
    _=historicalClock.ingest(calendarSnapshot(-50*3600,100,-3600),now:now)
    _=historicalClock.ingest(calendarSnapshot(-2*3600,80,-3600),now:now)
    let clockProjection=historicalClock.projections(for:calendarSnapshot(0,99,7*86400),now:now)[0]
    check(clockProjection.historicalCalendarHours==48 && abs(clockProjection.historicalCalendarPercentPerHour!-20.0/48)<0.0001,"previous periods retain wall-clock pauses and do not cross resets")
    print("PASS Usage timeline: \(count) checks")
}
