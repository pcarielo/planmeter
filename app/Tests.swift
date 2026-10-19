import Foundation

func runTests() {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
        count += 1
    }
    func snapshot(_ primary: [String: Any], secondary: [String: Any]? = nil) -> QuotaSnapshot {
        var bucket: [String: Any] = ["primary": primary]
        if let secondary = secondary { bucket["secondary"] = secondary }
        return try! parseQuota(["rateLimitsByLimitId": ["codex": bucket]])
    }
    check(snapshot(["usedPercent": 21]).remaining == 79, "100-usedPercent")
    check(snapshot(["usedPercent": 0]).remaining == 100, "zero used")
    check(snapshot(["usedPercent": 100]).remaining == 0, "exhausted quota")
    for invalid: Any in [NSNull(), true, "25", -1, 101, Double.nan, Double.infinity] {
        check(snapshot(["usedPercent": invalid]).remaining == nil, "invalid percentage")
    }
    check(snapshot([:]).remaining == nil, "absent percentage")
    check(snapshot(["usedPercent": 21]).windows[0].durationMinutes == nil, "don't assume five hours")
    check(snapshot(["usedPercent": 21], secondary: ["usedPercent": 40]).remaining == 60, "most constrained window")
    check(durationLabel(nil) == "duração não informada", "unknown duration")
    check(durationLabel(10080) == "7 dias", "weekly duration")
    check(durationLabel(300) == "5 horas", "five-hour duration")
    let legacy = try! parseQuota(["rateLimits": ["primary": ["usedPercent": 10]]])
    check(legacy.remaining == 90, "legacy fallback")
    let mismatched = try! parseQuota(["rateLimitsByLimitId": ["codex": ["limitId": "changed", "primary": ["usedPercent": 10]]]])
    check(mismatched.bucketID == "changed", "explicit bucket mismatch cannot celebrate")
    do { _ = try parseQuota(["rateLimitsByLimitId": ["other": [:]], "rateLimits": ["primary": ["usedPercent": 0]]]); check(false, "wrong bucket") }
    catch { check(true, "wrong bucket rejected") }
    let null = try! parseQuota(["rateLimits": ["primary": NSNull(), "secondary": NSNull()]])
    check(null.windows.isEmpty && null.remaining == nil, "null window unknown")
    let encoded = try! JSONEncoder().encode(legacy)
    check((try! JSONDecoder().decode(QuotaSnapshot.self, from: encoded)).remaining == 90, "cache roundtrip")
    check(!String(data: encoded, encoding: .utf8)!.contains("email"), "cache excludes identity")
    var policy = RefreshPolicy()
    let now = Date(timeIntervalSince1970: 100)
    check(policy.begin(now: now), "first query")
    check(!policy.begin(now: now), "no overlap")
    policy.finish(success: false)
    check(policy.interval == 60, "first retry 60s")
    check(policy.delay(now: now.addingTimeInterval(10)) == 50, "60 seconds between starts")
    for expected in [120.0, 240.0, 480.0, 900.0, 900.0] {
        policy.finish(success: false); check(policy.interval == expected, "bounded backoff")
    }
    policy.finish(success: true)
    check(policy.interval == 60, "success restores cadence")
    policy.sleeping = true
    check(!policy.begin(), "no query while asleep")
    policy.sleeping = false
    check(policy.begin(), "wake allows one query")
    check(!policy.begin(), "wake cannot overlap")
    policy.sleeping = true
    policy.finish(success: false)
    check(policy.failures == 0, "sleep cancellation doesn't count failure")
    check(percentLabel(nil) == "—", "unknown isn't zero")
    let environment = Runtime.cliEnvironment(binary:"/opt/homebrew/bin/codex",inherited:["PATH":"/usr/bin:/bin","OPENAI_API_KEY":"synthetic","CODEX_API_KEY":"synthetic"])
    check(environment["PATH"]!.hasPrefix("/opt/homebrew/bin:"),"GUI launch resolves CLI interpreter")
    check(environment["OPENAI_API_KEY"] == nil && environment["CODEX_API_KEY"] == nil,"managed login excludes API key overrides")
    print("PASS: \(count) checks")
}


import AppKit
func runUITests(binary: String) {
    _ = NSApplication.shared
    let app = MenuApp();
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("planmeter-tests-" + UUID().uuidString)
    app.cacheDirectory = directory
    app.binary = binary
    app.status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    app.menu = NSMenu()
    app.celebrationDisplay = false
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fputs("FAIL UI: \(label)\n", stderr); exit(1) }
        count += 1
    }
    func wait() {
        let deadline = Date().addingTimeInterval(5)
        while app.policy.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        check(!app.policy.busy, "async query finished")
        app.timer?.invalidate(); app.claudeTimer?.invalidate()
    }
    app.refresh(); wait()
    check(app.snapshot?.remaining == 63, "fixture shown")
    check(app.detector.state.lastDetectedAt == nil, "first read no celebration")
    check(app.confetti.presentationCount == 0, "no unexpected confetti")
    check(app.status.button?.toolTip?.contains("Codex 63%") == true, "status title")
    check(!app.menu.items.contains(where: { $0.title.contains("2 horas") }), "metrics removed from menu")
    check(app.dashboard.cards.contains{$0.key=="codex" && !$0.windows.isEmpty}, "quota available in dashboard")
    check(app.menu.items.contains(where: { $0.title.contains("DEMO de confete") }), "explicit demo action")
    check(countdownLabel(reset:Date().addingTimeInterval(-60).timeIntervalSince1970).contains("aguardando leitura"), "countdown does not claim reset")
    check(FileManager.default.fileExists(atPath: app.cacheFile.path), "cache saved")
    let metrics = try? JSONSerialization.jsonObject(with: Data(contentsOf: app.metricsFile)) as? [String: Any]
    check(metrics?["statusItemVisible"] as? Bool == app.status.isVisible, "metrics report actual AppKit visibility")
    app.binary = "/nonexistent/planmeter-test"
    app.refresh(); wait()
    check(app.snapshot?.remaining == 63, "failure preserves cache")
    check(app.status.button!.title.contains("·"), "failure marks stale")
    check(app.policy.failures == 1, "failure backoff")
    let beforeSleep = app.attempts
    app.sleep(); app.refresh()
    check(app.attempts == beforeSleep && app.policy.sleeping, "sleep blocks requests")
    app.wake(); wait()
    check(app.attempts == beforeSleep + 1, "wake performs one attempt")
    app.timer?.invalidate(); app.claudeTimer?.invalidate()
    NSStatusBar.system.removeStatusItem(app.status)
    try? FileManager.default.removeItem(at: directory)
    print("PASS UI: \(count) checks (synthetic data; no real sleep or service calls)")
}

func runResetTests() {
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else { fputs("FAIL reset: \(name)\n", stderr); exit(1) }; count += 1
    }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func snap(_ seconds: Double, used: Double?, reset: Double?, identity: String? = "synthetic-account", bucket: String? = "codex", duration: Int? = 60) -> QuotaSnapshot {
        var value = QuotaSnapshot(queriedAt: start.addingTimeInterval(seconds), windows: [QuotaWindow(name: "primary", remaining: used.map { 100 - $0 }, durationMinutes: duration, reset: reset.map { start.timeIntervalSince1970 + $0 })])
        value.identityFingerprint = identity; value.bucketID = bucket
        return value
    }
    let before = snap(0, used: 50, reset: 1800)
    let after = snap(60, used: 0, reset: 3660)
    var detector = ResetDetector()
    check(detector.accept(before).isEmpty, "first live read no event")
    check(detector.accept(after).count == 1, "early reset detected")
    check(detector.accept(snap(120, used: 1, reset: 3660)).isEmpty, "event not repeated")
    let saved = try! JSONEncoder().encode(detector.state)
    var restored = ResetDetector(); restored.state = try! JSONDecoder().decode(ResetState.self, from: saved)
    check(restored.accept(before).isEmpty, "restart is baseline only")
    check(restored.accept(after).isEmpty, "persistent dedup")
    check(restored.state.recentEventIDs.count == 1, "one retained event")
    var drift = ResetDetector()
    _ = drift.accept(snap(0, used: 50, reset: 3620))
    check(drift.accept(after).isEmpty, "small timestamp correction rejected")
    func rejected(_ next: QuotaSnapshot, label: String) {
        var d = ResetDetector(); _ = d.accept(before)
        check(d.accept(next).isEmpty, label)
    }
    rejected(snap(60, used: 0, reset: 3660, identity: "different-account"), label: "account change")
    rejected(snap(60, used: 0, reset: 3660, identity: nil), label: "unknown identity")
    rejected(snap(60, used: 0, reset: 3660, bucket: "other"), label: "other bucket")
    rejected(snap(60, used: 0, reset: 3660, duration: 120), label: "duration change")
    rejected(snap(60, used: 0, reset: 3660, duration: nil), label: "unknown duration")
    rejected(snap(60, used: nil, reset: 3660), label: "null usage")
    rejected(snap(60, used: 0, reset: nil), label: "null reset")
    rejected(snap(60, used: 0, reset: 1800), label: "usage correction without reset change")
    rejected(snap(60, used: 50, reset: 3660), label: "reset shift without usage decrease")
    rejected(snap(60, used: 80, reset: 3660), label: "usage increase")
    rejected(snap(60, used: 0, reset: 100_000), label: "implausible future reset")
    rejected(snap(60, used: 0, reset: 30), label: "expired reset")
    rejected(snap(60, used: 0, reset: 1e100), label: "extreme timestamp")
    var nullPrior = ResetDetector(); _ = nullPrior.accept(snap(0, used: nil, reset: 1800))
    check(nullPrior.accept(after).isEmpty, "null baseline doesn't celebrate")
    var ancient = ResetDetector(); _ = ancient.accept(snap(0, used: 50, reset: -1000))
    check(ancient.accept(after).isEmpty, "ancient reset timestamp rejected")
    rejected(snap(400, used: 0, reset: 4000), label: "stale gap")
    rejected(snap(-60, used: 0, reset: 3540), label: "clock reversal")
    var recovery = ResetDetector(); _ = recovery.accept(before); recovery.interrupt()
    check(recovery.accept(after).isEmpty, "error recovery doesn't celebrate")
    var natural = ResetDetector(); _ = natural.accept(snap(0, used: 99, reset: 30))
    check(natural.accept(after).count == 1, "scheduled window reset")
    check(countdownLabel(reset: start.timeIntervalSince1970 + 3660, now: start) == "Previsto em 1h 1min", "countdown")
    check(countdownLabel(reset: nil, now: start) == "Prazo não informado", "no invented deadline")
    check(countdownLabel(reset: start.timeIntervalSince1970, now: start).contains("aguardando leitura"), "deadline not proof of reset")
    check(!movementAllowed(reduceMotion: true, demo: false, allowDemoMotion: false), "automatic respects accessibility")
    check(!movementAllowed(reduceMotion: true, demo: false, allowDemoMotion: true), "override cannot affect real reset")
    check(!movementAllowed(reduceMotion: true, demo: true, allowDemoMotion: false), "ordinary demo respects accessibility")
    check(movementAllowed(reduceMotion: true, demo: true, allowDemoMotion: true), "explicit opt-in demo only")
    check(movementAllowed(reduceMotion: false, demo: false, allowDemoMotion: false), "normal animation allowed")
    print("PASS reset: \(count) checks")
}

func runConfettiTests() {
    _ = NSApplication.shared
    let presenter = ConfettiPresenter()
    presenter.show(message: "Teste fora da tela; sem consulta ou baseline.", demo: true, display: false, allowDemoMotion: true)
    guard let panel = presenter.panel, !panel.isVisible,
          panel.ignoresMouseEvents, presenter.activeParticles == 16,
          presenter.presentationCount == 1 else { exit(1) }
    let deadline = Date().addingTimeInterval(3)
    while presenter.panel != nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard presenter.panel == nil && presenter.activeParticles == 0 else { exit(1) }
    print("PASS confetti: passive panel, max 16 particles, offscreen, cleanup <=3s; no visible DEMO fired")
}

func runHistoryTests() {
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) { guard value() else { fputs("FAIL history: \(label)\n", stderr); exit(1) }; count += 1 }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func snap(_ time: Double, _ used: Double, _ reset: Double, provider: String = "codex") -> QuotaSnapshot {
        var s = QuotaSnapshot(queriedAt: start.addingTimeInterval(time), windows: [QuotaWindow(name: "primary", remaining: 100-used, durationMinutes: 60, reset: start.timeIntervalSince1970+reset)])
        s.identityFingerprint = "synthetic-hash"; s.bucketID = provider == "codex" ? "codex" : "claude_usage"; s.provider = provider; return s
    }
    var detector = ResetDetector(); _ = detector.accept(snap(0,50,1800))
    let first = detector.accept(snap(60,0,3660))[0]
    check(detector.state.history.count == 1, "one factual history row")
    check(first.previousUsedPercent == 50 && first.usedPercent == 0 && first.previousServiceResetAt == start.timeIntervalSince1970+1800, "old/new observed values")
    check(detector.state.activePending(snapshot: snap(60,0,3660)).count == 1, "pending until ack")
    check(detectionIntervals(detector.state.history).isEmpty, "no statistic with only one event")
    let ack = start.addingTimeInterval(75)
    detector.state.acknowledge(ids: [first.id], at: ack)
    check(detector.state.activePending(snapshot: snap(60,0,3660)).isEmpty, "ack clears pending")
    check(detector.state.history[0].acknowledgedAt == ack, "ack timestamp")
    detector.state.acknowledge(ids: [first.id], at: start.addingTimeInterval(90))
    check(detector.state.history[0].acknowledgedAt == ack, "ack idempotent")
    let encoded = try! JSONEncoder().encode(detector.state)
    var restored = ResetDetector(); restored.state = try! JSONDecoder().decode(ResetState.self, from: encoded)
    check(restored.state.history[0].acknowledgedAt == ack, "ack persists")
    _ = restored.accept(snap(0,50,1800))
    check(restored.accept(snap(60,0,3660)).isEmpty, "acknowledged event never replayed")
    _ = restored.accept(snap(120,50,3660))
    check(restored.accept(snap(180,0,3780)).count == 1, "next reset creates next event")
    check(restored.state.history.count == 2 && restored.state.activePending(snapshot: snap(180,0,3780)).count == 1, "only new event pending")
    check(detectionIntervals(restored.state.history) == [120], "actual detection interval")
    check(restored.state.activePending(snapshot: snap(180,0,3780,provider:"claude")).isEmpty, "provider isolation")
    var claude = ResetDetector(); _ = claude.accept(snap(0,50,1800,provider:"claude"))
    check(claude.accept(snap(60,0,3660,provider:"claude")).count == 1, "Claude has own detector")
    check(claude.state.history[0].groupKey != detector.state.history[0].groupKey, "statistics separate by provider")
    let legacy = Data("{\"recentEventIDs\":[],\"lastDetectedAt\":null}".utf8)
    check((try! JSONDecoder().decode(ResetState.self, from: legacy)).history.isEmpty, "don't fabricate legacy history")
    var activity = CelebrationActivity(); activity.sleeping = true
    check(activity.suspended, "sleep pauses")
    activity.screenLocked = true; activity.sleeping = false
    check(activity.suspended, "wake while locked remains paused")
    activity.screenLocked = false; activity.displaySleeping = true
    check(activity.suspended, "display sleep pauses")
    activity.displaySleeping = false; check(!activity.suspended, "resume only when all active")
    print("PASS history/ack/providers: \(count) checks")
}
func runLoopTests() {
    _ = NSApplication.shared
    let app = MenuApp();
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-loop-tests-"+UUID().uuidString)
    app.cacheDirectory = directory; app.binary = "/nonexistent/codex-loop-test"
    app.status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    app.celebrationDisplay = false; app.celebrationRenderOffscreen = true
    func cpu() -> Double { var u = rusage(); getrusage(RUSAGE_SELF,&u); return Double(u.ru_utime.tv_sec+u.ru_stime.tv_sec)+Double(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1e6 }
    func run(_ seconds: Double) { let end=Date().addingTimeInterval(seconds); while Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) } }
    let idleCPU = cpu(); run(3); let idleDelta = cpu()-idleCPU
    app.startDemo(motion:true)
    let baselineCPU = cpu(), start = Date(); run(30)
    let frames = app.confetti.frameCount, loopCPU = cpu()-baselineCPU, elapsed = Date().timeIntervalSince(start)
    guard app.demoPending, app.confetti.isAnimating, app.confetti.activeParticles == 16, frames >= 300,
          app.detector.state.history.isEmpty, app.claudeDetector.state.history.isEmpty, app.quotaRequests == 0 else { exit(1) }
    app.setScreenLocked(true); run(1)
    guard app.demoPending, app.confetti.panel == nil, !app.confetti.isAnimating else { exit(1) }
    let pausedCPU = cpu(); run(3); let pauseDelta = cpu()-pausedCPU
    app.setScreenLocked(false); run(0.3)
    guard app.demoPending, app.confetti.isAnimating else { exit(1) }
    app.acknowledge()
    guard !app.demoPending, app.confetti.panel == nil, !app.confetti.isAnimating, app.detector.state.history.isEmpty else { exit(1) }
    app.timer?.invalidate(); app.claudeTimer?.invalidate(); app.confetti.close(); NSStatusBar.system.removeStatusItem(app.status)
    try? FileManager.default.removeItem(at:directory)
    print("PASS loop/ack/screen-lock: offscreen raster, no visible DEMO or quota query")
    print(String(format:"loopSeconds=%.2f frames=%d observedFPS=%.2f loopCPUSeconds=%.3f idle3sCPU=%.3f paused3sCPU=%.3f",elapsed,frames,Double(frames)/elapsed,loopCPU,idleDelta,pauseDelta))
}

func runZaiUITests() {
    _ = NSApplication.shared
    let app=MenuApp();app.status=NSStatusBar.system.statusItem(withLength:0);app.status.isVisible=false;app.celebrationDisplay=false
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("planmeter-ui-"+UUID().uuidString)
    app.cacheDirectory=directory
    defer { NSStatusBar.system.removeStatusItem(app.status);try? FileManager.default.removeItem(at:directory) }
    var count=0
    func check(_ ok:Bool) { guard ok else {fputs("FAIL Z.ai UI\n",stderr);exit(1)};count += 1 }
    app.updateUI();check(app.status.button!.title.contains("5h — · sem —"))
    check(app.menu.items.contains{$0.title=="Z.ai: configurar chave…"})
    check(app.menu.items.contains{$0.title=="Z.ai: remover chave…"})
    let split=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"5h",remaining:42,durationMinutes:300,reset:nil),QuotaWindow(name:"week",remaining:65,durationMinutes:10080,reset:nil),QuotaWindow(name:"MCP",remaining:0,durationMinutes:nil,reset:nil)])
    app.zaiSnapshot=split;app.zaiError=nil;app.updateUI()
    check(app.status.button!.title.contains("5h 42% · sem 65%"))
    check(app.status.button!.toolTip!.contains("Z.ai 5h 42% · sem 65%"))
    var icons=0;app.status.button!.attributedTitle.enumerateAttribute(.attachment,in:NSRange(location:0,length:app.status.button!.attributedTitle.length)){ value,_,_ in if value is NSTextAttachment {icons += 1} }
    check(icons==4)
    app.zaiEnabled=true;app.zaiBusy=true;app.startZaiTimer();check(app.zaiTimer?.timeInterval==30)
    app.activity.screenLocked=true;app.startZaiTimer();check(app.zaiTimer==nil)
    check(KeychainStore.read()==nil) // Test processes cannot access real Keychain.
    print("PASS Z.ai UI: \(count) checks")
}

func runZaiRefreshTests() {
    _ = NSApplication.shared
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("planmeter-refresh-"+UUID().uuidString)
    let app=MenuApp();app.cacheDirectory=directory;app.zaiEnabled=true;app.binary="/nonexistent/test-codex"
    app.status=NSStatusBar.system.statusItem(withLength:0);app.status.isVisible=false;app.celebrationDisplay=false
    defer {app.timer?.invalidate();app.zaiTimer?.invalidate();NSStatusBar.system.removeStatusItem(app.status);try? FileManager.default.removeItem(at:directory)}
    var count=0,calls=0;var fail=false
    func check(_ ok:Bool,_ label:String){guard ok else{fputs("FAIL refresh: \(label)\n",stderr);exit(1)};count += 1}
    app.zaiClientFactory = { ZaiClient(keyProvider:{"synthetic-test-key"},transport:{_ in
        calls += 1
        if fail {throw QuotaError.message("synthetic failure")}
        return (Data(#"{"data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"percentage":29}]}}"#.utf8),200,nil)
    }) }
    func wait(){let deadline=Date().addingTimeInterval(5);while (app.zaiBusy || app.policy.busy) && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))};app.timer?.invalidate();check(!app.zaiBusy,"completed")}
    app.zaiCooldown=Date().addingTimeInterval(30);app.refreshZaiNow();wait()
    check(calls==1 && app.zaiSnapshot?.remaining==71,"manual bypasses local read throttle")
    check(app.zaiRefreshMessage?.contains("coleta concluída")==true,"completion visible")
    app.refreshZaiNow();check(calls==1,"rate limit prevents repeat")
    check(app.zaiRefreshMessage?.contains("aguarde")==true,"rate limit explained")
    app.zaiManualCooldown = .distantPast;fail=true;app.refreshZaiNow();wait()
    check(app.zaiSnapshot?.remaining==71,"failure preserves quota")
    check(app.zaiRefreshMessage?.contains("falhou")==true,"failure visible")
    let before=calls;app.refreshZaiNow();check(calls==before,"failed attempts also throttled")
    app.zaiManualCooldown = .distantPast;app.zaiCooldown = .distantPast
    app.startZaiTimer();check(calls==before,"resume does not bypass automatic interval")
    check(Runtime.codexPath()=="/nonexistent/planmeter-test-codex","tests skip personal config")
    print("PASS local Z.ai refresh: \(count) checks; fixture transport only")
}

func runLocalClientTests() {
    var count=0
    func check(_ ok:Bool){guard ok else{fputs("FAIL local client\n",stderr);exit(1)};count += 1}
    let absent=try! ZaiClient(keyProvider:{nil},transport:{_ in fatalError("must not call transport")}).read()
    check(absent.status=="auth_unavailable")
    for code in [401,403,429,500] {
        let result=try! ZaiClient(keyProvider:{"fake-key"},transport:{_ in (Data(),code,"3600")}).read()
        check(result.status == (code==429 ? "rate_limited" : code==500 ? "unavailable" : "unauthorized"))
        if code==429 {check(result.retryAfter==3600)}
    }
    for payload in [#"{"data":{"limits":[]}}"#,#"{"success":false}"#,#"{"code":true,"limits":[]}"#,"not-json"] {
        do {_=try ZaiClient(keyProvider:{"fake-key"},transport:{_ in (Data(payload.utf8),200,nil)}).read();check(false)}catch{check(true)}
    }
    let result=try! ZaiClient(keyProvider:{"fake-key"},transport:{_ in
        (Data(#"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":20,"secret":"must-not-copy"},{"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":40}]},"private":"must-not-copy"}"#.utf8),200,nil)
    }).read()
    check(result.snapshot.windows.count==2 && result.snapshot.remaining==60)
    check(!String(data:try! JSONEncoder().encode(result),encoding:.utf8)!.contains("must-not-copy"))
    print("PASS local Z.ai client: \(count) checks")
}
