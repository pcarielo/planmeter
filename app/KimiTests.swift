import AppKit

func runKimiTests() {
    var count=0
    func check(_ value:Bool,_ label:String){guard value else{fputs("FAIL Kimi: \(label)\n",stderr);exit(1)};count += 1}
    func data(_ value:[String:Any])->Data{try! JSONSerialization.data(withJSONObject:value)}
    let fixture:[String:Any] = ["usage":["limit":"1000","used":"200"],"limits":[["window":["duration":300,"timeUnit":"TIME_UNIT_MINUTE"],"detail":["limit":100,"remaining":70]]],"private":"must-not-copy"]
    let reading=try! parseKimi(data(fixture))
    check(reading.snapshot.windows.count==2,"two windows")
    check(reading.snapshot.windows.first{$0.durationMinutes==10080}?.remaining==80,"weekly ratio")
    check(reading.snapshot.windows.first{$0.durationMinutes==300}?.remaining==70,"5h ratio")
    check(!String(data:try! JSONEncoder().encode(reading),encoding:.utf8)!.contains("must-not-copy"),"no raw fields")
    check(kimiCount(true)==nil && kimiCount("NaN")==nil && kimiCount(-1)==nil,"invalid counters")
    check(kimiMinutes(["duration":5,"timeUnit":"HOUR"])==300,"explicit hour duration")
    let itemDuration=try! parseKimi(data(["usage":["limit":100,"used":20],"limits":[["window":[:],"duration":300,"timeUnit":"TIME_UNIT_MINUTE","detail":["limit":100,"used":30]]]]))
    check(itemDuration.snapshot.windows.contains{$0.durationMinutes==300 && $0.remaining==70},"item duration survives empty window")
    check(kimiMinutes(["duration":5,"timeUnit":"unknown"])==nil,"no invented duration")
    for invalid:[String:Any] in [[:],["usage":["limit":0,"used":0]],["usage":["limit":100]],["usage":["limit":100,"used":true]]] {
        do {_=try parseKimi(data(invalid));check(false,"unknown isn't zero")}catch{check(true,"reject invalid")}
    }
    let nullUsed=try! parseKimi(data(["usage":["limit":100,"used":NSNull(),"remaining":25]]))
    check(nullUsed.snapshot.remaining==25,"null used falls back to remaining")
    let exhausted=try! parseKimi(data(["usage":["limit":100,"used":110]]))
    check(exhausted.snapshot.remaining==0,"over quota exhausted")
    do {_=try parseKimi(data(["usage":["limit":100,"used":1],"limits":[["window":["duration":7,"timeUnit":"DAY"],"detail":["limit":100,"used":1]]]]));check(false,"duplicates")}catch{check(true,"duplicates rejected")}
    let noKey=try! KimiClient(keyProvider:{nil},transport:{_ in fatalError("network not allowed")}).read()
    check(noKey.status=="auth_unavailable","missing key no network")
    for (code,status) in [(401,"unauthorized"),(403,"unauthorized"),(429,"rate_limited"),(500,"unavailable")] {
        let client=KimiClient(keyProvider:{"synthetic-key"},transport:{_ in (Data(),code,"3600")})
        let result=try! client.read();check(result.status==status,"status category")
        if code==429 {check(result.nextAttemptAt.timeIntervalSinceNow>3500,"Retry-After")}
    }
    let client=KimiClient(keyProvider:{"synthetic-key"},transport:{key in check(key=="synthetic-key","injected credential");return(data(fixture),200,nil)})
    check((try! client.read()).snapshot.remaining==70,"fixture transport")
    check(KimiKeychain.read()==nil,"test processes never access real keychain")
    print("PASS Kimi parser/client: \(count) checks")
}

func runKimiMonitorTests() {
    _ = NSApplication.shared
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("kimi-fixture-"+UUID().uuidString)
    let monitor=KimiMonitor();monitor.cacheDirectory=dir;monitor.enabled=true
    defer {monitor.stop();try? FileManager.default.removeItem(at:dir)}
    var count=0,calls=0;var fail=false,slow=false
    func check(_ value:Bool,_ label:String){guard value else{fputs("FAIL Kimi monitor: \(label)\n",stderr);exit(1)};count += 1}
    monitor.clientFactory={KimiClient(keyProvider:{"synthetic-key"},transport:{_ in
        calls += 1;if slow {Thread.sleep(forTimeInterval:0.15)}
        if fail {throw QuotaError.message("synthetic")}
        return(Data(#"{"usage":{"limit":100,"used":20},"limits":[{"window":{"duration":5,"timeUnit":"HOUR"},"detail":{"limit":100,"used":30}}]}"#.utf8),200,nil)
    })}
    func wait(){let end=Date().addingTimeInterval(3);while monitor.busy && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.02))};check(!monitor.busy,"request terminal")}
    monitor.setPaused(true);monitor.start();monitor.refreshNow()
    check(calls==0 && !monitor.busy,"launch paused never queries")
    monitor.setPaused(false);wait();check(monitor.snapshot?.remaining==70,"live state updated")
    monitor.refreshNow();check(calls==1 && monitor.message!.contains("aguarde"),"throttle")
    let restored=KimiMonitor();restored.cacheDirectory=dir;restored.load()
    check(restored.snapshot==nil && restored.schedule.manual>Date(),"cache cannot prove authentication in this process")
    monitor.schedule.manual = .distantPast;monitor.start();check(calls==1,"wake preserves automatic interval")
    monitor.schedule=KimiSchedule(manual:.distantPast,automatic:.distantPast);fail=true;monitor.refreshNow();wait()
    check(monitor.snapshot?.remaining==70 && monitor.stale,"failure preserves marked stale quota")
    monitor.schedule=KimiSchedule(manual:.distantPast,automatic:.distantPast);fail=false;slow=true;monitor.refreshNow();monitor.setPaused(true)
    RunLoop.current.run(until:Date().addingTimeInterval(0.25))
    check(!monitor.busy && monitor.message!.contains("pausa"),"cancelled result discarded")
    monitor.clear();slow=true;monitor.setPaused(false);monitor.clear()
    RunLoop.current.run(until:Date().addingTimeInterval(0.25))
    check(!monitor.busy && monitor.snapshot==nil,"credential change cancels and discards in-flight result")
    slow=false;monitor.refreshNow();wait()
    check(monitor.snapshot?.remaining==70,"refresh works after credential change")
    let presentation=StatusPresentation.make(codex:nil,claude:nil,zai:nil,codexStale:false,claudeStale:false,zaiStale:false,badge:"",kimi:monitor.snapshot,kimiStale:false,showKimi:true)
    check(presentation.accessibilityText.contains("Kimi Code 5h 70% · sem 80%"),"distinct accessible windows")
    var icons=0;presentation.title.enumerateAttribute(.attachment,in:NSRange(location:0,length:presentation.title.length)){value,_,_ in if value is NSTextAttachment {icons += 1}}
    check(icons==1,"only provider with metrics has an icon")
    var aged=QuotaSnapshot(queriedAt:Date().addingTimeInterval(-300),windows:monitor.snapshot!.windows);aged.provider="kimi"
    check(!MenuApp().stale(aged),"Kimi menu uses 15-minute freshness")
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    let field=KimiCredentialField(frame:NSRect(x:10,y:10,width:300,height:24))
    field.pasteText={"synthetic-paste"};window.contentView?.addSubview(field)
    window.makeFirstResponder(field)
    let paste=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"v",charactersIgnoringModifiers:"v",isARepeat:false,keyCode:9)!
    check(field.performKeyEquivalent(with:paste),"secure field handles command paste without edit menu")
    window.makeFirstResponder(nil)
    check(field.stringValue=="synthetic-paste","secure editor accepts synthetic paste without real clipboard")
    field.stringValue="";window.orderOut(nil)
    monitor.schedule=KimiSchedule(manual:.distantPast,automatic:.distantPast);monitor.clientFactory={KimiClient(keyProvider:{nil},transport:{_ in fatalError("no credentials must not reach provider")})}
    monitor.refreshNow();wait();check(monitor.snapshot==nil,"lost credential hides old quota");monitor.prepareAfterAuthorization()
    let authorizedSchedule=try! JSONDecoder().decode(KimiSchedule.self,from:Data(contentsOf:dir.appendingPathComponent("kimi-schedule.json")))
    check(monitor.schedule.manual<Date() && authorizedSchedule.manual<Date(),"authorization clears credential-only cooldown and persists it")
    monitor.clientFactory={KimiClient(keyProvider:{"synthetic-only"},transport:{_ in (Data(),429,"900")})}
    monitor.refreshNow();wait();let limited=monitor.schedule.manual;monitor.prepareAfterAuthorization()
    check(monitor.schedule.manual==limited && limited>Date(),"authorization preserves provider cooldown")
    print("PASS Kimi monitor/UI: \(count) checks; no real keychain or network")
}
