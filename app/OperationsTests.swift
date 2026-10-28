import Foundation

func runOperationsTests() {
    var checks=0
    func check(_ ok:Bool,_ label:String) {if !ok {fatalError("FAIL operations: \(label)")};checks += 1}
    let empty=try! JSONDecoder().decode(OperationsSettings.self,from:Data("{}".utf8))
    check(empty.refreshSeconds==0 && empty.retentionDays==90,"migration keeps safe defaults")
    check(empty.interval(for:"codex")==60 && empty.interval(for:"kimi")==900,"automatic defaults preserve provider cadence")
    var settings=empty;settings.refreshSeconds=1;settings.retentionDays=2;settings.rotationMB=0
    settings=settings.normalized()
    check(settings.refreshSeconds==60 && settings.retentionDays==90 && settings.rotationMB==1,"bounds")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let log=AuditLog(directory:root)
    let now=Date(timeIntervalSince1970:1_800_000_000)
    var opts=OperationsSettings();opts.rotationDays=1
    check(log.record(.queries,provider:.claude,action:.readCache,outcome:.success,settings:opts,now:now),"write")
    check(log.record(.queries,provider:.claude,action:.readCache,outcome:.success,settings:opts,now:now.addingTimeInterval(86401)),"period rotate")
    let files=try! FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
    check(files.count==2,"rotation retains recent file")
    let text=try! String(contentsOf:log.url(.queries),encoding:.utf8)
    check(text.contains("readCache") && !text.contains("token"),"closed event schema")
    let attrs=try! FileManager.default.attributesOfItem(atPath:log.url(.queries).path)
    check((attrs[.posixPermissions] as? NSNumber)?.intValue==384,"private file")
    opts.queries=false
    let before=try! Data(contentsOf:log.url(.queries))
    check(log.record(.queries,provider:.codex,action:.query,outcome:.failure,settings:opts,now:now),"disabled category")
    check(before == (try! Data(contentsOf:log.url(.queries))),"disabled does not append")
    let target=root.appendingPathComponent("target");try! Data("preserve".utf8).write(to:target)
    try! FileManager.default.createSymbolicLink(atPath:log.url(.access).path,withDestinationPath:target.path)
    check(!log.record(.access,provider:.kimi,action:.authorize,outcome:.failure,settings:opts,now:now),"symlink rejected")
    check((try! String(contentsOf:target,encoding:.utf8))=="preserve","symlink destination untouched")
    check(log.lastError != nil,"storage failure visible")
    opts.queries=true
    let oldName="queries-\(Int64(now.addingTimeInterval(-95*86400).timeIntervalSince1970))-\(UUID().uuidString).jsonl"
    let old=root.appendingPathComponent(oldName);try! Data("old".utf8).write(to:old)
    let recent=root.appendingPathComponent("queries-\(Int64(now.addingTimeInterval(-89*86400).timeIntervalSince1970))-\(UUID().uuidString).jsonl")
    try! Data("recent".utf8).write(to:recent)
    check(log.record(.queries,provider:.app,action:.query,outcome:.success,settings:opts,now:now),"prune")
    check(!FileManager.default.fileExists(atPath:old.path) && FileManager.default.fileExists(atPath:recent.path),"retention boundary preserves 89 days, prunes 95")
    let external=root.appendingPathComponent("redirect")
    try! FileManager.default.createSymbolicLink(atPath:external.path,withDestinationPath:root.path)
    check(!AuditLog(directory:external).record(.queries,provider:.app,action:.query,outcome:.success,settings:opts,now:now),"redirected directory rejected")
    opts.rotationMB=1;opts.rotationDays=0
    let large=Data(repeating:32,count:1_048_576)
    try! large.write(to:log.url(.configuration))
    check(log.record(.configuration,provider:.app,action:.settingsChanged,outcome:.success,settings:opts,now:now),"size rotation")
    check((try! Data(contentsOf:log.url(.configuration))).count<1024,"new segment after size threshold")
    opts.rotateBySize=false
    try! large.write(to:log.url(.configuration))
    check(log.record(.configuration,provider:.app,action:.settingsChanged,outcome:.success,settings:opts,now:now),"no rotation triggers")
    check((try! Data(contentsOf:log.url(.configuration))).count>1_048_576,"size rotation can be disabled")
    log.availableBytes={_ in 50_000_000}
    check(log.record(.queries,provider:.app,action:.query,outcome:.success,settings:opts,now:now) && log.warning != nil,"low disk warning without deleting retained logs")
    log.simulateWriteFailure=true
    check(!log.record(.queries,provider:.app,action:.query,outcome:.success,settings:opts,now:now) && log.lastError != nil,"write failure is surfaced")
    print("PASS Operations: \(checks) checks")
}
