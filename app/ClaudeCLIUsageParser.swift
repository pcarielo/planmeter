import Foundation

struct ClaudeCLIUsageParser {
    static func normalized(_ text:String)->String {text.lowercased().filter{!$0.isWhitespace}}
    static func requiresTrust(_ text:String)->Bool {
        let value=normalized(text)
        return value.contains("yes,itrustthisfolder") || value.contains("doyoutrustthefilesinthisfolder") || value.contains("quicksafetycheck")
    }
    static func screenStatus(_ text:String)->String? {
        let lower=text.lowercased()
        if ["rate limited until","requests temporarily limited","temporarily limiting requests to the usage page"].contains(where:lower.contains) {return "rate_limited"}
        if ["showing last-known usage","could not refresh","partial usage data","per-model breakdown unavailable"].contains(where:lower.contains) {return "stale"}
        if ["refreshing","loading usage","fetching usage"].contains(where:lower.contains) {return "refreshing"}
        if lower.contains("failed to load usage") {return "unavailable"}
        return nil
    }
    static func retryDate(_ text:String,now:Date)->Date {
        let resetText=capture(#"rate limited until\s+([^\n)]+)"#,text)
        let reported=resetText.flatMap{reset($0,minutes:1440,now:now)}.map{Date(timeIntervalSince1970:$0)}
        return max(now.addingTimeInterval(900),reported ?? now.addingTimeInterval(900))
    }
    static func capture(_ pattern:String,_ text:String)->String? {
        guard let regex=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]),let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),match.numberOfRanges>1,let range=Range(match.range(at:1),in:text) else{return nil}
        return String(text[range])
    }
    static func reset(_ text:String,minutes:Int,now:Date)->Double? {
        let zoneName=capture(#"\(([^)]+)\)"#,text)
        guard let zone=zoneName.flatMap(TimeZone.init(identifier:)) ?? (zoneName==nil ? TimeZone.current : nil) else{return nil}
        let value=text.components(separatedBy:"(")[0].trimmingCharacters(in:.whitespaces).replacingOccurrences(of:#"\s+(am|pm)\b"#,with:"$1",options:.regularExpression)
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=zone;formatter.isLenient=false
        let formats=["h:mma","ha","H:mm"]
        for format in formats {
            formatter.dateFormat=format
            if let time=formatter.date(from:value) {
                let parts=calendar.dateComponents([.hour,.minute],from:time)
                if let today=calendar.date(bySettingHour:parts.hour ?? 0,minute:parts.minute ?? 0,second:0,of:now) {
                    let candidates=[today,calendar.date(byAdding:.day,value:1,to:today)!]
                    if let valid=candidates.first(where:{$0>=now.addingTimeInterval(-60) && $0<=now.addingTimeInterval(Double(minutes)*60+60)}) {return valid.timeIntervalSince1970}
                }
            }
        }
        // Explicit years must not receive a second, inferred year at the end.
        for format in ["MMM d, yyyy 'at' h:mma","MMM d, yyyy 'at' ha","MMM d, yyyy, h:mma","MMM d, yyyy, ha","MMM d, yyyy, H:mm"] {
            formatter.dateFormat=format
            if let date=formatter.date(from:value),date>=now.addingTimeInterval(-60),date<=now.addingTimeInterval(Double(minutes)*60+3600) {return date.timeIntervalSince1970}
        }
        let year=calendar.component(.year,from:now)
        for y in (year-1)...(year+1) {
            for format in ["MMM d 'at' h:mma yyyy","MMM d 'at' ha yyyy","MMM d 'at' H:mm yyyy","MMM d, h:mma yyyy","MMM d, ha yyyy","MMM d, H:mm yyyy"] {
                formatter.dateFormat=format
                if let date=formatter.date(from:value+" "+String(y)),date>=now.addingTimeInterval(-60),date<=now.addingTimeInterval(Double(minutes)*60+3600) {return date.timeIntervalSince1970}
            }
        }
        return nil
    }
    static func parse(_ text:String,now:Date=Date())throws->ClaudeQuotaReading {
        guard !requiresTrust(text),screenStatus(text)==nil else{throw QuotaError.message("Consulta Claude ainda não concluída")}
        let lines=text.components(separatedBy:.newlines)
        var windows:[QuotaWindow]=[]
        for (name,minutes,header) in [("five_hour",300,"current session"),("seven_day",10080,"current week")] {
            guard let start=lines.firstIndex(where:{line in
                let v=line.lowercased().trimmingCharacters(in:.whitespaces)
                if name=="five_hour" {return v==header}
                return v==header || v=="current week (all models)"
            }) else{continue}
            let end=lines.indices.dropFirst(start+1).first(where:{lines[$0].lowercased().contains("current week") || lines[$0].lowercased().contains("usage credits")}) ?? min(lines.count,start+12)
            let block=lines[start..<end].joined(separator:"\n")
            guard let raw=capture(#"([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*used"#,block),let used=Double(raw),(0...100).contains(used) else{throw QuotaError.message("Painel Claude incompleto")}
            let resetText=capture(#"Resets\s+([^\n]+)"#,block)
            windows.append(QuotaWindow(name:name,remaining:100-used,durationMinutes:minutes,reset:resetText.flatMap{reset($0,minutes:minutes,now:now)}))
        }
        guard !windows.isEmpty else{throw QuotaError.message("Painel de quota Claude não reconhecido")}
        var snapshot=QuotaSnapshot(queriedAt:now,windows:windows);snapshot.provider="claude";snapshot.bucketID="claude:subscription";snapshot.sourceHost="claude-code-cli"
        return ClaudeQuotaReading(snapshot:snapshot,status:"ok",nextAttemptAt:now.addingTimeInterval(60))
    }
}
func runClaudeCLIParserTests() {
    var n=0
    func check(_ value:Bool,_ name:String){if !value {fatalError("FAIL Claude CLI parser: \(name)")};n += 1}
    let now=ISO8601DateFormatter().date(from:"2026-10-28T17:00:00Z")!
    let screen="Current session\n████ 7% used\nResets 4pm (America/Fortaleza)\n\nCurrent week (all models)\n53% used\nResets Oct 29 at 8am (America/Fortaleza)\n\nCurrent week (Fable)\n0% used"
    let value=try! ClaudeCLIUsageParser.parse(screen,now:now)
    check(value.snapshot.windows.map(\.remaining)==[93,47],"session and all-model weekly, no scoped duplicate")
    check(value.snapshot.windows[0].reset==ISO8601DateFormatter().date(from:"2026-10-28T19:00:00Z")!.timeIntervalSince1970,"time-only reset with explicit timezone")
    check(value.snapshot.windows[1].reset==ISO8601DateFormatter().date(from:"2026-10-29T11:00:00Z")!.timeIntervalSince1970,"weekly reset with timezone")
    check((try? ClaudeCLIUsageParser.parse("Current session\nLoading usage",now:now))==nil,"loading is not zero")
    check((try? ClaudeCLIUsageParser.parse("Current week (Fable)\n0% used",now:now))==nil,"model-specific week cannot substitute overall week")
    check(ClaudeCLIUsageParser.requiresTrust("Yes, I trust this folder"),"trust state classified without accepting")
    var terminal=ClaudeTerminalScreen(rows:10,columns:80)
    terminal.render(Data("old\r\n\u{1b}[2J\u{1b}[HCurrent session\r\n\u{1b}[32m9% used\u{1b}[0m\r\u{1b}[K7% used".utf8))
    check(terminal.text.contains("7% used") && !terminal.text.contains("9% used") && !terminal.text.contains("old"),"terminal clears and overwrites old frames")
    for marker in ["Refreshing…","Showing last-known usage as of yesterday","Could not refresh","Partial usage data","Per-model breakdown unavailable","rate limited until 4pm","requests temporarily limited","Claude is temporarily limiting requests to the usage page"] {
        check((try? ClaudeCLIUsageParser.parse(screen+"\n"+marker,now:now))==nil,"cached or partial screen rejected: "+marker)
    }
    check(ClaudeCLIUsageParser.retryDate("rate limited until 4pm",now:now)>=now.addingTimeInterval(900),"rate limit enforces backoff")
    for dateText in ["Oct 29, 8am (America/Fortaleza)","Oct 29, 8:00am (America/Fortaleza)"] {
        check(ClaudeCLIUsageParser.reset(dateText,minutes:10080,now:now)==ISO8601DateFormatter().date(from:"2026-10-29T11:00:00Z")!.timeIntervalSince1970,"comma date: "+dateText)
    }
    let december=ISO8601DateFormatter().date(from:"2026-12-30T12:00:00Z")!
    for dateText in ["Jan 2, 2027, 8am (America/Fortaleza)","Jan 2, 2027 at 8am (America/Fortaleza)","Jan 2, 2027, 8:00am (America/Fortaleza)"] {
        check(ClaudeCLIUsageParser.reset(dateText,minutes:10080,now:december)==ISO8601DateFormatter().date(from:"2027-01-02T11:00:00Z")!.timeIntervalSince1970,"explicit year: "+dateText)
    }
    print("PASS Claude official CLI parser: \(n) checks; no token, terminal launch or network")
}
