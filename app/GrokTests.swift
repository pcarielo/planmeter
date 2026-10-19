import Foundation
func runGrokTests() {
    var count=0
    func check(_ value:Bool,_ label:String) {guard value else {fputs("FAIL Grok: \(label)\n",stderr);exit(1)};count += 1}
    func result(_ used:Any)->[String:Any] {["config":["creditUsagePercent":used,"isUnifiedBillingUser":true,"currentPeriod":["type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-26T23:02:12.373+00:00"],"prepaidBalance":["val":9999]],"subscription_tier":"private-do-not-copy"]}
    let reading=try! parseGrok(result(1))
    check(reading.snapshot.remaining==99,"remaining percentage")
    check(reading.snapshot.bucketID=="grok:unified","shared pool explicit")
    check(reading.snapshot.windows.first?.durationMinutes==10080,"weekly metadata")
    check(reading.snapshot.windows.first?.reset != nil,"fractional reset timestamp")
    let encoded=String(data:try! JSONEncoder().encode(reading),encoding:.utf8)!
    check(!encoded.contains("prepaid") && !encoded.contains("private-do-not-copy"),"only quota retained")
    for bad:Any in [true,"1",-1,101,NSNull()] {do {_=try parseGrok(result(bad));check(false,"invalid quota accepted")}catch{check(true,"invalid quota rejected")}}
    check((try! parseGrok(result(100))).snapshot.remaining==0,"zero balance valid")
    check((try! GrokClient(binary:"/nonexistent/synthetic-grok").read()).status=="cli_unavailable","missing CLI no network")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("grok-fixture-"+UUID().uuidString)
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:directory)}
    let fake=directory.appendingPathComponent("grok")
    let script="""
    #!/usr/bin/env python3
    import sys,json
    assert sys.argv[1:]==['--no-auto-update','agent','stdio']
    request=json.loads(input());assert request['method']=='initialize' and request['params']['protocolVersion']==1
    print(json.dumps({'jsonrpc':'2.0','id':88,'method':'fs/read_text_file','params':{}}),flush=True)
    denied=json.loads(input());assert denied['id']==88 and denied['error']['code']==-32601
    print(json.dumps({'jsonrpc':'2.0','id':request['id'],'result':{'protocolVersion':1}}),flush=True)
    request=json.loads(input());assert request['method']=='_x.ai/billing'
    print(json.dumps({'jsonrpc':'2.0','id':request['id'],'result':{'config':{'creditUsagePercent':12,'isUnifiedBillingUser':True,'currentPeriod':{'type':'USAGE_PERIOD_TYPE_WEEKLY'}}}}),flush=True)
    assert sys.stdin.read()==''
    """
    try! script.write(to:fake,atomically:true,encoding:.utf8);try! FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:fake.path)
    let client=GrokClient(binary:fake.path,timeout:5)
    check((try! client.read()).snapshot.remaining==88,"ACP only initializes and reads billing; server tool denied")
    check(client.lastExitStatus==0 && client.quotaRequests==1,"fixture confirms no traffic after billing")
    for value:Any in [true,0,1,100] {
        let json=try! JSONSerialization.data(withJSONObject:result(value))
        let decoded=try! JSONSerialization.jsonObject(with:json) as! [String:Any]
        if value is Bool {do {_=try parseGrok(decoded);check(false,"JSON boolean accepted")}catch{check(true,"JSON boolean rejected")}}
        else {check((try! parseGrok(decoded)).status=="ok","JSON numeric boundary accepted")}
    }
    let cancelled=GrokClient(binary:fake.path);cancelled.cancel()
    do {_=try cancelled.read();check(false,"cancelled process launched")}catch{check(!cancelled.didLaunch,"pre-launch cancellation prevents process creation")}
    print("PASS Grok: \(count) checks; fixture CLI, no real credentials or model")
}
