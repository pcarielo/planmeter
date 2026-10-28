import Foundation

struct InsightModelCatalog {
    static func safeModel(_ value:String)->Bool {
        value.count<=120 && value.range(of:"^[A-Za-z0-9][A-Za-z0-9._:/-]*$",options:.regularExpression) != nil
    }
    static func environmentModels(provider:String,environment:[String:String])->[String] {
        let names:[String]
        switch provider {case "codex":names=["CODEX_MODEL","OPENAI_MODEL"];case "claude":names=["ANTHROPIC_MODEL"];case "kimi":names=["KIMI_MODEL"];default:names=[]}
        return names.compactMap{environment[$0]}.filter{safeModel($0)}
    }
    static func piModels(_ data:Data,provider:String)->[String] {
        guard let text=String(data:data,encoding:.utf8) else{return []}
        var seen=Set<String>()
        return text.components(separatedBy:.newlines).compactMap {line in
            let parts=line.split(whereSeparator:{$0.isWhitespace}).map(String.init)
            guard parts.count>=2,parts[0]==provider,safeModel(parts[1]),seen.insert(parts[1]).inserted else{return nil}
            return parts[1]
        }
    }
    static func request(harness:InsightHarness,executable:String)->InsightRequest? {
        switch harness {
        case .pi:return InsightRequest(executable:executable,arguments:["--no-extensions","--no-mcp","--no-skills","--no-context-files","--offline","--list-models"],environment:InsightRunner.environment(ProcessInfo.processInfo.environment,binary:executable),input:Data())
        case .kimi:return InsightRequest(executable:executable,arguments:["provider","list"],environment:InsightRunner.environment(ProcessInfo.processInfo.environment,binary:executable),input:Data())
        case .primeAgent:
            var prefs=InsightPreferences();prefs.harness = .primeAgent
            return InsightAdapter(preferences:prefs,executable:executable,inheritedEnvironment:ProcessInfo.processInfo.environment).metadataRequest(arguments:["--offline","model","list"])
        case .opencode:
            var prefs=InsightPreferences();prefs.harness = .opencode
            return InsightAdapter(preferences:prefs,executable:executable,inheritedEnvironment:ProcessInfo.processInfo.environment).metadataRequest(arguments:["--pure","models"])
        default:return nil
        }
    }
    static func openCodeModels(_ data:Data,provider:String)->[String] {
        guard let text=String(data:data,encoding:.utf8) else{return []}
        return text.components(separatedBy:.newlines).filter{$0.hasPrefix(provider+"/") && safeModel($0)}
    }
    static func kimiModels(_ data:Data)->[String] {
        guard let text=String(data:data,encoding:.utf8) else{return []}
        return text.components(separatedBy:.newlines).filter{$0.hasPrefix("Default model: kimi-code/")}.compactMap {line in
            let value=String(line.dropFirst("Default model: ".count));return safeModel(value) ? value : nil
        }
    }
}
func runInsightModelTests() {
    var n=0
    func check(_ value:Bool,_ label:String){if !value{fatalError("FAIL model discovery: \(label)")};n += 1}
    let table="provider model context\nkimi-coding k3 1M\nmoonshotai kimi-k3 1M\nkimi-coding k3 1M\nkimi-coding --bad 1M"
    check(InsightModelCatalog.piModels(Data(table.utf8),provider:"kimi-coding")==["k3"],"only selected coding-plan route, unique valid models")
    check(InsightModelCatalog.environmentModels(provider:"claude",environment:["ANTHROPIC_MODEL":"sonnet","API_KEY":"hidden"])==["sonnet"],"only named model variables")
    check(InsightModelCatalog.environmentModels(provider:"codex",environment:["CODEX_MODEL":"../../secret key"]).isEmpty,"invalid env model ignored")
    let now=Date(timeIntervalSince1970:1800000000)
    let projection=UsageProjection(provider:"codex",window:"weekly",remaining:50,observedAt:now.timeIntervalSince1970,resetAt:now.timeIntervalSince1970+1800,observedHours:24,sampleCount:48,percentPerHour:1,estimatedExhaustionAt:nil,riskBeforeReset:false)
    check(!InsightBasis.isStale(generatedAt:now,basis:[projection],current:[projection],now:now),"new insight matches its data")
    check(InsightBasis.isStale(generatedAt:now,basis:[projection],current:[projection],now:now.addingTimeInterval(1801)),"reset invalidates an old insight")
    check(InsightBasis.isStale(generatedAt:now,basis:[projection],current:[],now:now),"missing provider invalidates old insight")
    check(InsightBasis.isStale(generatedAt:now,basis:[],current:[],now:now.addingTimeInterval(3601)),"one-hour age bound")
    print("PASS Insight model discovery: \(n) checks")
}
