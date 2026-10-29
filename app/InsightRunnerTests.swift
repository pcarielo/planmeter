import Foundation
func runInsightRunnerTests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value{fatalError("FAIL insight runner: \(label)")};count += 1}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:directory)}
    let script=directory.appendingPathComponent("fake harness")
    func write(_ body:String){try! ("#!/bin/sh\n"+body).write(to:script,atomically:true,encoding:.utf8);try! FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)}
    func request(_ data:String="fixture")->InsightRequest {InsightRequest(executable:script.path,arguments:[],environment:["PATH":"/usr/bin:/bin"],input:Data(data.utf8))}
    write("cat\n")
    check(String(data:try! InsightRunner().run(request()),encoding:.utf8)=="fixture","stdin is transported literally")
    write("printf 'short insight'\n")
    check(String(data:try! InsightRunner().run(request("")),encoding:.utf8)=="short insight","empty stdin")
    write("exec /bin/sleep 5\n")
    do {_=try InsightRunner(timeout:0.1).run(request(""));check(false,"timeout")}
    catch InsightFailure.timeout {check(true,"timeout terminates child")}catch{check(false,"wrong timeout error")}
    let cancelled=InsightRunner();cancelled.cancel()
    do {_=try cancelled.run(request());check(false,"cancel")}
    catch InsightFailure.cancelled {check(true,"cancel before start")}catch{check(false,"wrong cancel error")}
    write("printf '12345678901234567890'\n")
    do {_=try InsightRunner(outputLimit:10).run(request(""));check(false,"output limit")}
    catch InsightFailure.excessiveOutput{check(true,"bounded output")}catch{check(false,"wrong limit error")}
    write("printf 'private error' >&2\nexit 1\n")
    do {_=try InsightRunner().run(request(""));check(false,"failure")}
    catch InsightFailure.failed{check(true,"sanitized failure")}catch{check(false,"wrong failure error")}
    let env=InsightRunner.environment(["HOME":"/fixture","USER":"fixture","LOGNAME":"fixture","SECRET":"hidden","OPENAI_API_KEY":"hidden","BASH_ENV":"untrusted"],binary:"/fixture/cli")
    check(env["USER"]=="fixture" && env["LOGNAME"]=="fixture","native CLI login keeps user identity")
    check(env["SECRET"]==nil && env["OPENAI_API_KEY"]==nil && env["BASH_ENV"]==nil,"environment allowlist")
    check((try? InsightText.validate("Uso estável.\nAcompanhe a janela semanal.")) != nil,"two short lines")
    check((try? InsightText.validate(String(repeating:"x",count:221)))==nil,"long response rejected, not silently truncated")
    check((try? InsightText.validate("one\ntwo\nthree"))==nil,"three lines rejected")
    write("exit 0\n")
    do {_=try InsightRunner().run(request(String(repeating:"x",count:32000)));check(true,"early exit does not terminate host through SIGPIPE")}
    catch {check(true,"broken stdin returns an error instead of signal")}
    write("/bin/sleep 30 &\nwait\n")
    let start=Date()
    do {_=try InsightRunner(timeout:0.1).run(request(""));check(false,"descendant timeout")}
    catch {check(Date().timeIntervalSince(start)<3,"process group cleanup remains bounded")}
    let marker=directory.appendingPathComponent("must-not-exist")
    let restricted=InsightRequest(executable:"/bin/zsh",arguments:["-f","-c","if /usr/bin/touch \"$1\"; then echo unsafe; else echo blocked; fi","fixture",marker.path],environment:["PATH":"/usr/bin:/bin","ZDOTDIR":directory.path],input:Data(),blockChildExecution:true,writableDirectories:[directory.path])
    let reply=try! InsightRunner().run(restricted)
    check(String(data:reply,encoding:.utf8)?.contains("blocked")==true && !FileManager.default.fileExists(atPath:marker.path),"containment blocks child execution even in writable directory")
    if let probe=ProcessInfo.processInfo.environment["PLANMETER_TEST_NET_PROBE"] {
        let gateway=InsightRequest(executable:probe,arguments:["0","p"],environment:[:],input:Data(),blockChildExecution:true,proxyHosts:["api.kimi.com"])
        check(String(data:try! InsightRunner().run(gateway),encoding:.utf8)=="connected\n","contained process can reach its own restricted gateway")
        for (key,family) in [("PLANMETER_TEST_PROBE_PORT","4"),("PLANMETER_TEST_PROBE_IPV6_PORT","6")] {
            guard let raw=ProcessInfo.processInfo.environment[key],UInt16(raw) != nil else{fatalError("Missing live network fixture")}
            let control=InsightRequest(executable:probe,arguments:[raw,family],environment:[:],input:Data())
            check(String(data:try! InsightRunner().run(control),encoding:.utf8)=="connected\n","loopback fixture is live outside containment")
            let request=InsightRequest(executable:probe,arguments:[raw,family],environment:[:],input:Data(),blockChildExecution:true,proxyHosts:["api.kimi.com"])
            check(String(data:try! InsightRunner().run(request),encoding:.utf8)=="unreachable\n","live loopback service is unreachable inside containment")
            check(String(data:try! InsightRunner().run(control),encoding:.utf8)=="connected\n","loopback fixture remains live after blocked attempt")
        }
    }
    check((try? InsightText.validate("riskBeforeReset é true"))==nil,"internal field names never reach the user")
    let clock=Date(timeIntervalSince1970:1800000000)
    var projected=UsageProjection(provider:"codex",window:"Semanal",remaining:10,observedAt:clock.timeIntervalSince1970,resetAt:clock.timeIntervalSince1970+7200,observedHours:24,sampleCount:49,percentPerHour:10,estimatedExhaustionAt:clock.timeIntervalSince1970+3600,riskBeforeReset:true,identityEvidence:"unknown",reason:"account_unidentified")
    projected.recentPercentPerHour=10
    let payload=try! JSONSerialization.jsonObject(with:InsightText.prompt([projected],now:clock,timeZone:TimeZone(identifier:"America/Fortaleza")!)) as! [String:Any]
    let signals=payload["signals"] as! [[String:Any]]
    check(signals.first?["kind"] as? String=="depletion_risk","model receives a computed interpretation instead of card facts")
    check(payload["projections"]==nil,"ordinary balances and dates are not sent for paraphrasing")
    let signalText=String(data:try! JSONSerialization.data(withJSONObject:payload),encoding:.utf8)!
    check(!signalText.contains("account_unidentified") && !signalText.contains("1800000000"),"internal diagnostics and epochs do not leak into analytical prompt")
    write("printf '{\"error\":\"node_version\"}\\n'\n")
    let nodes=InsightProxy.nodeCandidates(environment:ProcessInfo.processInfo.environment,home:FileManager.default.homeDirectoryForCurrentUser.path)
    guard let node=nodes.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else{fatalError("Node fixture required")}
    let relay=try! InsightProxy.start(hosts:["api.kimi.com"],directory:directory,candidates:[script.path,node]);relay.stop()
    check(true,"unsupported first Node candidate falls back to available runtime")
    do {_=try InsightProxy.start(hosts:["invalid.example"],directory:directory,candidates:[node]);check(false,"invalid relay host")}
    catch InsightFailure.proxyUnavailable {check(true,"relay failure is not mislabeled as Node version")}
    catch {check(false,"wrong relay failure")}
    print("PASS Insight runner: \(count) checks; fixture processes only")
}
