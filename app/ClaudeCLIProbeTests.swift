import Foundation

func runClaudeCLIProbeTests() {
    var count=0
    func check(_ value:Bool,_ name:String){if !value {fatalError("FAIL Claude PTY: \(name)")};count += 1}
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("claude-pty-fixture-"+UUID().uuidString)
    try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    defer{try? FileManager.default.removeItem(at:root)}
    func fixture(_ name:String,_ body:String)->String {
        let path=root.appendingPathComponent(name)
        try! ("#!/bin/sh\n"+body).write(to:path,atomically:true,encoding:.utf8)
        try! FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:path.path)
        return path.path
    }
    let ready=fixture("ready","printf 'Current session\\r\\n7%% used\\r\\nCurrent week (all models)\\r\\n53%% used\\r\\n'\nsleep 10\n")
    let read=try! ClaudeCLIProbe(binary:ready,directory:root,timeout:3).read()
    check(read.status=="ok" && read.snapshot.windows.map(\.remaining)==[93,47],"real PTY transport reads synthetic screen")
    let trust=fixture("trust","printf 'Do you trust the files in this folder?\\r\\nYes, I trust this folder\\r\\n'\nsleep 10\n")
    check((try! ClaudeCLIProbe(binary:trust,directory:root,timeout:3).read()).status=="setup_required","trust never accepted by background query")
    let idle=fixture("idle","sleep 10\n")
    let start=Date()
    check((try! ClaudeCLIProbe(binary:idle,directory:root,timeout:0.2).read()).status=="unavailable","empty terminal is not full quota")
    check(Date().timeIntervalSince(start)<4,"timeout cleanup is bounded")
    let cancelled=ClaudeCLIProbe(binary:ready,directory:root);cancelled.cancel()
    check((try? cancelled.read())==nil,"cancel before launch")
    let screen="\(root.path)\n❯ Yes, I trust this folder\nNo, exit"
    check(ClaudeCLIProbe.trustKey(screen:screen,directory:root)=="\r","explicit trust requires matching folder and selection")
    check(ClaudeCLIProbe.trustKey(screen:screen,directory:root.appendingPathComponent("other"))==nil,"different displayed folder cannot be accepted")

    let transitioning=fixture("transitioning","printf 'Current session\\r\\n7%% used\\r\\nRefreshing…\\r\\n'\nsleep 1\nprintf '\\033[2J\\033[HCurrent session\\r\\n20%% used\\r\\nCurrent week (all models)\\r\\n40%% used\\r\\n'\nsleep 10\n")
    let transitionStart=Date(),fresh=try! ClaudeCLIProbe(binary:transitioning,directory:root,timeout:4).read()
    check(fresh.status=="ok" && fresh.snapshot.windows.map(\.remaining)==[80,60] && fresh.snapshot.queriedAt.timeIntervalSince(transitionStart)>=1,"refreshing cached frame is never returned as a fresh reading")
    let stale=fixture("stale","printf 'Current session\\r\\n7%% used\\r\\nShowing last-known usage as of yesterday (could not refresh)\\r\\n'\nsleep 10\n")
    let old=try! ClaudeCLIProbe(binary:stale,directory:root,timeout:3).read()
    check(old.status=="stale" && old.snapshot.windows.isEmpty,"last-known screen supplies no new measurements")
    print("PASS Claude PTY: \(count) checks; fixture executables only; no real Claude or credentials")
}
