import Foundation

struct InsightSignal:Codable,Equatable {
    let kind:String
    let provider:String
    let window:String
    let facts:[String]
    let priority:Int
    var urgency:Double=0
    enum CodingKeys:String,CodingKey {case kind,provider,window,facts,priority}
}

enum InsightAnalysis {
    static let waitingMessage="O histórico está sendo acompanhado. Ainda não há um sinal de ritmo ou risco que justifique uma análise."
    static func decimal(_ value:Double)->String {String(format:"%.1f",value).replacingOccurrences(of:".",with:",")}
    static func signals(_ projections:[UsageProjection],now:Date=Date())->[InsightSignal] {
        var result:[InsightSignal]=[]
        for p in projections {
            guard p.remaining.isFinite,(0...100).contains(p.remaining),p.observedAt<=now.timeIntervalSince1970+5,now.timeIntervalSince1970-p.observedAt<=3600 else{continue}
            let name=["codex":"Codex","claude":"Claude","kimi":"Kimi Code","zai":"Z.ai","grok":"Grok"][p.provider] ?? p.provider
            if let reset=p.resetAt,reset.isFinite,reset>now.timeIntervalSince1970,reset<=now.addingTimeInterval(366*86400).timeIntervalSince1970 {
                let age=max(0,now.timeIntervalSince1970-p.observedAt)/3600
                let hours=(reset-now.timeIntervalSince1970)/3600
                let rate:Double?
                let basis:String
                if hours<=6 {
                    rate=p.recentPercentPerHour;basis="ritmo recente observado"
                } else if let calendarRate=p.calendarPercentPerHour,p.calendarHours>=24,calendarRate.isFinite,calendarRate>=0 {
                    rate=calendarRate;basis="média por hora de relógio em dias completos do período, incluindo as pausas"
                } else if let historical=p.historicalCalendarPercentPerHour,p.historicalCalendarHours>=24,historical.isFinite,historical>=0 {
                    rate=historical;basis="média por hora de relógio de períodos anteriores registrados, incluindo as pausas"
                } else {rate=nil;basis=""}
                if let rate=rate,rate.isFinite,hours>0,rate>0 {
                    let estimatedNow=max(0,p.remaining-rate*age)
                    let sustainable=estimatedNow/hours
                    let projected=p.remaining-rate*(hours+age)
                    if projected < -0.5 {
                        let reduction=min(100,max(1,ceil((1-sustainable/rate)*100-0.000001)))
                        result.append(InsightSignal(kind:"depletion_risk",provider:p.provider,window:p.window,facts:["\(name), janela \(p.window): \(basis) de \(decimal(rate)) pontos percentuais por hora.","Mantido esse ritmo, o saldo duraria cerca de \(intervalLabel(max(0,p.remaining/rate-age)*3600)), enquanto faltam \(intervalLabel(ceil(hours*60)*60)) para renovar.","Para chegar à renovação, o ritmo precisaria cair aproximadamente \(Int(reduction))% em relação ao observado. A projeção depende da manutenção do padrão de uso."],priority:0,urgency:max(0,p.remaining/rate-age)))
                    } else {
                        let tight=projected<10
                        result.append(InsightSignal(kind:tight ? "tight_margin" : "projected_margin",provider:p.provider,window:p.window,facts:["\(name), janela \(p.window): o ritmo observado projeta cerca de \(Int(max(0,projected).rounded()))% de saldo na próxima renovação.","Essa margem é uma projeção condicional à \(basis) de \(decimal(rate)) pontos percentuais por hora, não garantia de disponibilidade."],priority:tight ? 1 : 3,urgency:projected))
                    }
                }
            }
            if let recent=p.recentPercentPerHour,let prior=p.baselinePercentPerHour,prior>0,recent.isFinite,prior.isFinite {
                let change=(recent/prior-1)*100
                if change.isFinite,abs(change)>=25,abs(change)<=1_000_000,abs(recent-prior)>=0.1 {
                    result.append(InsightSignal(kind:change>0 ? "accelerating" : "decelerating",provider:p.provider,window:p.window,facts:["\(name), janela \(p.window): o ritmo na janela recente de seis horas \(change>0 ? "aumentou" : "diminuiu") cerca de \(Int(abs(change).rounded()))% em relação à mesma faixa horária observada em pelo menos dois dias anteriores.","Ritmo recente: \(decimal(recent)); anterior: \(decimal(prior)) pontos percentuais por hora. São intervalos separados, com pelo menos uma hora observada em cada um."],priority:2,urgency:-abs(change)))
                }
            }
        }
        return result.sorted {a,b in
            if a.priority != b.priority {return a.priority<b.priority}
            if a.urgency != b.urgency {return a.urgency<b.urgency}
            return (a.provider+a.window+a.kind)<(b.provider+b.window+b.kind)
        }
    }
}

func runInsightAnalysisTests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL insight analysis: \(label)")};count += 1}
    let now=Date(timeIntervalSince1970:1800000000)
    func sample(_ rate:Double?,remaining:Double=20)->UsageProjection {
        var value=UsageProjection(provider:"codex",window:"Semanal",remaining:remaining,observedAt:now.timeIntervalSince1970,resetAt:now.addingTimeInterval(4*3600).timeIntervalSince1970,observedHours:2,sampleCount:5,percentPerHour:rate,estimatedExhaustionAt:nil,riskBeforeReset:nil)
        value.recentPercentPerHour=rate;return value
    }
    check(InsightAnalysis.signals([sample(nil)],now:now).isEmpty,"balance and renewal alone are not an insight")
    check(InsightAnalysis.signals([sample(10)],now:now).first?.kind=="depletion_risk","measured pace detects depletion before renewal")
    check(InsightAnalysis.signals([sample(1,remaining:80)],now:now).first?.kind=="projected_margin","margin derives from pace and time, not balance alone")
    var accelerating=sample(nil);accelerating.recentPercentPerHour=4;accelerating.baselinePercentPerHour=2
    check(InsightAnalysis.signals([accelerating],now:now).contains{$0.kind=="accelerating"},"recent and prior pace compared")
    var flat=sample(0);flat.recentPercentPerHour=0;flat.baselinePercentPerHour=0
    check(InsightAnalysis.signals([flat],now:now).isEmpty,"zero baseline never divides by zero or promises headroom")
    check(InsightAnalysis.signals([sample(5)],now:now.addingTimeInterval(3601)).isEmpty,"stale observation cannot drive forecast")
    var urgent=sample(10,remaining:10)
    urgent=UsageProjection(provider:"zai",window:"5 horas",remaining:10,observedAt:now.timeIntervalSince1970,resetAt:now.addingTimeInterval(5*3600).timeIntervalSince1970,observedHours:2,sampleCount:5,percentPerHour:10,estimatedExhaustionAt:nil,riskBeforeReset:nil)
    urgent.recentPercentPerHour=10
    check(InsightAnalysis.signals([sample(10),urgent],now:now).first?.provider=="zai","first limiting window wins over alphabetical order")
    check(InsightAnalysis.signals([sample(5)],now:now).first?.kind=="tight_margin","zero projected reserve is an actionable tight margin")
    let distant=UsageProjection(provider:"codex",window:"Semanal",remaining:20,observedAt:now.timeIntervalSince1970,resetAt:1e100,observedHours:2,sampleCount:5,percentPerHour:5,estimatedExhaustionAt:nil,riskBeforeReset:nil)
    check(InsightAnalysis.signals([distant],now:now).isEmpty,"implausible horizon cannot overflow interval formatting")
    var daily=UsageProjection(provider:"codex",window:"Semanal",remaining:70,observedAt:now.timeIntervalSince1970,resetAt:now.addingTimeInterval(72*3600).timeIntervalSince1970,observedHours:30,sampleCount:50,percentPerHour:1.2,estimatedExhaustionAt:nil,riskBeforeReset:nil)
    daily.recentPercentPerHour=1.2;daily.periodFirstObservedRemainingPercent=100;daily.periodObservedHours=75;daily.calendarPercentPerHour=0.4;daily.calendarHours=48
    let dailySignals=InsightAnalysis.signals([daily],now:now)
    check(!dailySignals.contains{$0.kind=="depletion_risk"} && dailySignals.contains{$0.kind=="projected_margin"},"weekly forecast includes night pauses instead of extending the work-hour burst")
    daily.periodObservedHours=6;daily.calendarPercentPerHour=nil;daily.calendarHours=0
    check(InsightAnalysis.signals([daily],now:now).isEmpty,"short coverage cannot forecast multiple days")
    let midnight=Date(timeIntervalSince1970:floor(now.timeIntervalSince1970/86400)*86400)
    let cycles:[(Double,Double,Double,Double)]=[(0,8,20,1.2),(0,9,18,1.2),(9,9,18,1.2),(0,8,20,1.8),(0,9,18,1.8),(9,9,18,1.8)]
    for (startHour,awakeStart,awakeEnd,dailyRate) in cycles {
        var timeline=UsageTimeline(),falseRisks=0
        let anchor=midnight.addingTimeInterval(startHour*3600)
        for quarter in 0...672 {
            let elapsed=Double(quarter)/4,absolute=startHour+elapsed,phase=absolute.truncatingRemainder(dividingBy:24)
            guard phase>=awakeStart && phase<=awakeEnd else{continue}
            var worked=0.0
            for day in 0...7 {worked += max(0,min(absolute,Double(day)*24+18)-max(startHour,Double(day)*24+9))}
            let stamp=anchor.addingTimeInterval(elapsed*3600)
            var snapshot=QuotaSnapshot(queriedAt:stamp,windows:[QuotaWindow(name:"week",remaining:max(0,100-worked*dailyRate),durationMinutes:10080,reset:anchor.addingTimeInterval(168*3600).timeIntervalSince1970)])
            snapshot.provider="codex";snapshot.identityFingerprint="daily-cycle"
            _=timeline.ingest(snapshot,now:stamp)
            if snapshot.windows[0].remaining!>0 && InsightAnalysis.signals(timeline.projections(for:snapshot,now:stamp),now:stamp).contains(where:{$0.kind=="depletion_risk"}) {falseRisks += 1}
        }
        check(dailyRate==1.2 ? falseRisks==0 : falseRisks>0,"full week distinguishes sustainable work cycles from real depletion before the reset")
    }
    var priorPeriod=daily;priorPeriod.historicalCalendarPercentPerHour=0.4;priorPeriod.historicalCalendarHours=48
    check(InsightAnalysis.signals([priorPeriod],now:now).contains{$0.kind=="projected_margin"},"valid prior-period history supports a new period without extrapolating a fresh burst")
    let controller=InsightController();controller.generate([sample(nil)],permitted:true)
    check(!controller.busy && controller.message==InsightAnalysis.waitingMessage,"no model call when only card facts are available")
    print("PASS analytical insight: \(count) checks")
}
