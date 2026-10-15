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
final class ConfettiPresenter {
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
        let view = NSView(frame: NSRect(origin: .zero, size: size)); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.cornerRadius = 14
        let canvas = ConfettiCanvas(frame: view.bounds); canvas.motion = motion
        view.addSubview(canvas)
        let title = NSTextField(labelWithString: demo ? "DEMO · Confete Codex" : "Codex · Reset detectado")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 18, y: 128, width: 315, height: 24); view.addSubview(title)
        let detail = NSTextField(wrappingLabelWithString: message)
        detail.font = .systemFont(ofSize: 12)
        detail.frame = NSRect(x: 18, y: 65, width: 315, height: 55); view.addSubview(detail)
        let instruction = NSTextField(labelWithString: "Clique uma vez em Codex na barra para dispensar")
        instruction.font = .systemFont(ofSize: 11, weight: .medium)
        instruction.frame = NSRect(x: 18, y: 22, width: 325, height: 32); view.addSubview(instruction)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
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
