import AppKit

final class ConfettiCanvas: NSView {
    let started = ProcessInfo.processInfo.systemUptime
    private(set) var frames = 0
    var motion = false
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        frames += 1
        guard motion else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple]
        for i in 0..<16 {
            let phase = (elapsed / 3 + Double(i) / 16).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(12 + (i * 43) % 320) + CGFloat(sin(phase * .pi * 2 + Double(i)) * 12)
            let y = bounds.height + 8 - CGFloat(phase) * (bounds.height + 16)
            colors[i % colors.count].setFill()
            NSRect(x: x, y: y, width: 4, height: 7).fill()
        }
    }
}
final class ResetNoticeView: NSView {
    var onClick: () -> Void = {}
    override func hitTest(_ point: NSPoint) -> NSView? {bounds.contains(point) ? self : nil}
    override func mouseDown(with event: NSEvent) {onClick()}
}
final class ConfettiPresenter {
    var onAcknowledge: () -> Void = {}
    private(set) var panel: NSPanel?
    private(set) var canvas: ConfettiCanvas?
    private var animationTimer: Timer?
    private var cleanup: DispatchWorkItem?
    private(set) var presentationCount = 0
    private(set) var activeParticles = 0
    var frameCount: Int { canvas?.frames ?? 0 }
    var isAnimating: Bool { animationTimer != nil }
    func show(message: String, demo: Bool, display: Bool = true, allowDemoMotion: Bool = false) {
        let motion = movementAllowed(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, demo: demo, allowDemoMotion: allowDemoMotion)
        showLoop(message: message, demo: demo, motion: motion, display: display)
        let cleanup = DispatchWorkItem { [weak self] in self?.close() }
        self.cleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: cleanup)
    }
    func showLoop(message: String, demo: Bool, motion: Bool, display: Bool = true, renderOffscreen: Bool = false) {
        close()
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 350, height: 175)
        let frame = NSRect(x: screen.visibleFrame.maxX - size.width - 16,
                           y: screen.visibleFrame.maxY - size.height - 12, width: size.width, height: size.height)
        let view = ResetNoticeView(frame: NSRect(origin: .zero, size: size)); view.wantsLayer = true
        view.onClick = { [weak self] in self?.onAcknowledge() }
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.cornerRadius = 14
        let canvas = ConfettiCanvas(frame: view.bounds); canvas.motion = motion
        view.addSubview(canvas)
        let title = NSTextField(labelWithString: demo ? "DEMO · PlanMeter" : "PlanMeter · Reset detectado")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 18, y: 128, width: 315, height: 24); view.addSubview(title)
        let detail = NSTextField(wrappingLabelWithString: message)
        detail.font = .systemFont(ofSize: 12)
        detail.frame = NSRect(x: 18, y: 65, width: 315, height: 55); view.addSubview(detail)
        let instruction = NSTextField(labelWithString: "Clique neste aviso ou no indicador para dispensar")
        instruction.font = .systemFont(ofSize: 11, weight: .medium)
        instruction.frame = NSRect(x: 18, y: 22, width: 325, height: 32); view.addSubview(instruction)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        self.panel = panel; self.canvas = canvas; presentationCount += 1
        if display { panel.orderFrontRegardless() }
        if motion {
            activeParticles = 16
            let bitmap: NSBitmapImageRep? = renderOffscreen ? NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 350, pixelsHigh: 175, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) : nil
            let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak canvas] _ in
                guard let canvas = canvas else { return }
                if let bitmap = bitmap, let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                    context.cgContext.clear(canvas.bounds); canvas.draw(canvas.bounds)
                    NSGraphicsContext.restoreGraphicsState()
                } else { canvas.needsDisplay = true }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common); animationTimer = timer
        }
    }
    func close() {
        cleanup?.cancel(); cleanup = nil
        animationTimer?.invalidate(); animationTimer = nil
        panel?.close(); panel = nil; canvas = nil; activeParticles = 0
    }
}
func movementAllowed(reduceMotion: Bool, demo: Bool, allowDemoMotion: Bool) -> Bool {
    !reduceMotion || (demo && allowDemoMotion)
}

func runResetNoticeTests() {
    let app=MenuApp();app.celebrationDisplay=false
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("reset-notice-"+UUID().uuidString)
    app.cacheDirectory=dir;app.status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);app.menu=NSMenu()
    defer {app.confetti.close();NSStatusBar.system.removeStatusItem(app.status);try? FileManager.default.removeItem(at:dir)}
    var snapshot=QuotaSnapshot(queriedAt:Date().addingTimeInterval(-3600),windows:[])
    snapshot.identityFingerprint="synthetic-only";snapshot.bucketID="codex";app.snapshot=snapshot
    app.errorText="synthetic unavailable"
    app.detector.state.history=[ResetRecord(id:"fixture",identityFingerprint:"synthetic-only",bucketID:"codex",window:"primary",durationMinutes:300,detectedAt:Date(),previousServiceResetAt:1,serviceResetAt:2,previousUsedPercent:50,usedPercent:0,acknowledgedAt:nil)]
    app.reconcileCelebration()
    guard app.confetti.panel != nil,app.realPending.count==1 else {fatalError("confirmed reset must survive stale quota")}
    let presenterCount=app.confetti.presentationCount
    app.reconcileCelebration()
    guard app.confetti.presentationCount==presenterCount else {fatalError("notice must not restart on refresh")}
    guard let notice=app.confetti.panel?.contentView as? ResetNoticeView else {fatalError("clickable notice required")}
    notice.onClick()
    guard app.realPending.isEmpty,app.confetti.panel==nil,app.detector.state.history.first?.acknowledgedAt != nil else {fatalError("click must acknowledge and close")}
    let observed=Date().addingTimeInterval(-1000),now=Date()
    var baseline=QuotaSnapshot(queriedAt:observed,windows:[QuotaWindow(name:"five_hour",remaining:30,durationMinutes:300,reset:now.addingTimeInterval(-500).timeIntervalSince1970)])
    baseline.identityFingerprint="synthetic-claude";baseline.provider="claude";baseline.bucketID="claude_usage"
    app.claudeDetector.state.baseline=baseline
    let identity=String(repeating:"a",count:64);app.claudeDetector.state.baseline?.identityFingerprint=identity
    func validCache(_ at:Date,_ reset:Date,_ used:Double) {
        let data:[String:Any]=["source":"claude-code-statusline","providerObservedAt":at.timeIntervalSince1970,"identityFingerprint":identity,"rateLimits":["five_hour":["used_percentage":used,"resets_at":reset.timeIntervalSince1970]]]
        try! JSONSerialization.data(withJSONObject:data).write(to:dir.appendingPathComponent("claude-statusline.json"))
    }
    validCache(observed.addingTimeInterval(0.000001),now.addingTimeInterval(-500),70);app.readClaudeCache()
    guard app.claudeDetector.state.baseline?.windows.count==1 else {fatalError("unchanged expired cache must preserve persisted baseline")}
    validCache(now,now.addingTimeInterval(18000),1);app.readClaudeCache()
    guard app.claudeDetector.state.history.count==1 else {fatalError("Claude renewal must survive restart with expired cache")}
    print("PASS reset notice: stale quota persistence, stable refresh, click acknowledgment; synthetic only")
}
