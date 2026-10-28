import Foundation

enum InsightHarness:String,CaseIterable,Codable {
    case codex,claude,kimi,opencode,pi,primeAgent="prime-agent"
    var title:String {switch self {case .codex:return "Codex";case .claude:return "Claude Code";case .kimi:return "Kimi Code";case .opencode:return "OpenCode";case .pi:return "pi";case .primeAgent:return "Prime Agent"}}
    var pathVariable:String {"PLANMETER_"+rawValue.replacingOccurrences(of:"-",with:"_").uppercased()+"_PATH"}
    static let modelProviders=["codex","claude","kimi","zai"]
    static func providerTitle(_ key:String)->String {
        ["codex":"Codex","claude":"Claude Code","kimi":"Kimi Code","zai":"Z.ai"][key] ?? key
    }
    var compatibleProviderNames:String {Self.modelProviders.filter{Self.compatible(with:$0).contains(self)}.map{Self.providerTitle($0)}.joined(separator:" / ")}
    static func compatible(with provider:String)->[Self] {
        switch provider {case "codex":return [.codex,.opencode,.pi];case "claude":return [.claude];case "kimi":return [.kimi,.opencode,.pi,.primeAgent];case "zai":return [.opencode,.pi,.primeAgent];default:return []}
    }
    static func preferred(for provider:String)->Self? {
        switch provider {case "codex":return .codex;case "claude":return .claude;case "kimi":return .kimi;case "zai":return .opencode;default:return nil}
    }
}
struct InsightPreferences:Codable,Equatable {
    var provider="codex"
    var model=""
    var harness=InsightHarness.codex
    var executablePath=""
    func sameCatalog(as other:Self)->Bool {provider==other.provider && harness==other.harness && executablePath==other.executablePath}
}
struct HarnessDiscovery {
    let home:String
    let environment:[String:String]
    var executable:(String)->Bool={FileManager.default.isExecutableFile(atPath:$0) && !FileManager.default.isDirectory(atPath:$0)}
    func candidates(_ harness:InsightHarness)->[String] {
        var paths:[String]=[]
        if let configured=environment[harness.pathVariable],configured.hasPrefix("/") {paths.append(configured)}
        if harness == .primeAgent {paths.append(home+"/.local/share/prime-agent/prime-agent")}
        let directories=(environment["PATH"] ?? "").split(separator:":").map(String.init)+[
            home+"/.local/bin",home+"/.kimi-code/bin",home+"/.bun/bin",home+"/.cargo/bin",home+"/.npm-global/bin",home+"/.prime-agent/bin","/opt/homebrew/bin","/usr/local/bin","/usr/bin"]
        paths += directories.filter{$0.hasPrefix("/")}.map{$0+"/"+harness.rawValue}
        var seen=Set<String>()
        return paths.filter{!$0.contains("\n") && !$0.contains("\0") && seen.insert($0).inserted && executable($0)}
    }
    func resolve(_ harness:InsightHarness,override:String="")->String? {
        if !override.isEmpty {
            let path=override.hasPrefix("~/") ? home+String(override.dropFirst()) : override
            guard path.hasPrefix("/"),!path.contains("\n"),!path.contains("\0"),executable(path) else{return nil}
            return path
        }
        return candidates(harness).first
    }
}
private extension FileManager {
    func isDirectory(atPath path:String)->Bool {var isDirectory:ObjCBool=false;return fileExists(atPath:path,isDirectory:&isDirectory) && isDirectory.boolValue}
}
func runHarnessDiscoveryTests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL harness discovery: \(label)")};count += 1}
    let paths:Set<String>=["/fixture/.local/bin/codex","/custom path/claude","/fixture/.kimi-code/bin/kimi"]
    let discovery=HarnessDiscovery(home:"/fixture",environment:["PATH":"relative:/fixture/.local/bin:/fixture/.local/bin","PLANMETER_CLAUDE_PATH":"/custom path/claude","SECRET":"must never be consumed"],executable:{paths.contains($0)})
    check(discovery.resolve(.codex)=="/fixture/.local/bin/codex","common location")
    check(discovery.resolve(.claude)=="/custom path/claude","explicit path from whitelisted variable")
    check(discovery.resolve(.kimi)=="/fixture/.kimi-code/bin/kimi","native Kimi path")
    check(discovery.candidates(.codex).count==1,"deduplicated")
    check(discovery.resolve(.codex,override:"relative")==nil,"relative override rejected")
    check(discovery.resolve(.codex,override:"/missing")==nil,"invalid override never silently falls back")
    check(discovery.resolve(.codex,override:"~/.local/bin/codex")=="/fixture/.local/bin/codex","home shortcut without shell")
    check(discovery.resolve(.primeAgent)==nil,"missing is explicit")
    check(InsightHarness.preferred(for:"kimi") == .kimi && InsightHarness.preferred(for:"claude") == .claude,"native harness defaults")
    check(InsightProxy.nodeCandidates(environment:["PLANMETER_NODE_PATH":"/custom/node"],home:"/fixture")==["/custom/node"],"explicit Node path has no silent fallback")
    check(InsightProxy.nodeCandidates(environment:["PLANMETER_NODE_PATH":"relative"],home:"/fixture").isEmpty,"relative Node path rejected")
    check(InsightProxy.nodeCandidates(environment:[:],home:"/fixture").contains("/fixture/.volta/bin/node"),"Node common version-manager path")
    print("PASS Harness discovery: \(count) checks; no executable launched")
}
