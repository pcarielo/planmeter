import AppKit

struct QuotaCard {
    let key: String, name: String
    let snapshot: QuotaSnapshot
    let stale: Bool
    var note: String? = nil
    var windows: [QuotaWindow] { snapshot.windows.filter { $0.remaining.map { $0.isFinite && $0 >= 0 && $0 <= 100 } ?? false } }
    static func available(_ values: [QuotaCard]) -> [QuotaCard] { values.filter { !$0.windows.isEmpty } }
}

final class QuotaDashboardView: NSView {
    let cards: [QuotaCard]
    let columns: Int
    var dismiss: () -> Void = {}
    var pinned=false
    override var isFlipped: Bool { true }
    static func rowHeight(_ cards: [QuotaCard]) -> CGFloat { CGFloat(78 + (cards.map { $0.windows.count }.max() ?? 0) * 90) }
    init(cards: [QuotaCard], width: CGFloat) {
        self.cards=cards;columns=width < 500 ? 1 : 2
        var height:CGFloat=76
        for index in stride(from:0,to:cards.count,by:columns) { height += Self.rowHeight(Array(cards[index..<min(index+columns,cards.count)])) + 12 }
        super.init(frame:NSRect(x:0,y:0,width:width,height:max(150,height+30)))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        let summaries: [String] = cards.map { card in
            let windows: [String] = card.windows.map { window in
                durationLabel(window.durationMinutes) + " " + percentLabel(window.remaining)
            }
            let freshness = card.stale ? ", dados desatualizados" : ""
            return card.name + freshness + ": " + windows.joined(separator:", ")
        }
        setAccessibilityLabel("Quotas disponíveis. " + summaries.joined(separator:". "))
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) not supported") }
    override func mouseDown(with event:NSEvent) { dismiss() }
    private func text(_ value:String,_ rect:NSRect,_ size:CGFloat,_ color:NSColor = .labelColor,_ weight:NSFont.Weight = .regular) {
        let style=NSMutableParagraphStyle();style.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:style])
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.windowBackgroundColor.setFill();bounds.fill()
        text("Disponibilidade",NSRect(x:20,y:18,width:bounds.width-40,height:26),20,.labelColor,.semibold)
        text("Saldo restante por janela de uso",NSRect(x:20,y:46,width:bounds.width-40,height:18),12,.secondaryLabelColor)
        if cards.isEmpty { text("Nenhuma métrica disponível no momento.",NSRect(x:20,y:88,width:bounds.width-40,height:24),13,.secondaryLabelColor) }
        let width=(bounds.width-40-CGFloat(columns-1)*12)/CGFloat(columns)
        var y:CGFloat=76
        for start in stride(from:0,to:cards.count,by:columns) {
            let row=Array(cards[start..<min(start+columns,cards.count)])
            let height=Self.rowHeight(row)
            for (column,card) in row.enumerated() {
                let x=20+CGFloat(column)*(width+12), rect=NSRect(x:x,y:y,width:width,height:height)
                NSColor.labelColor.withAlphaComponent(0.055).setFill();NSBezierPath(roundedRect:rect,xRadius:12,yRadius:12).fill()
                NSColor.separatorColor.withAlphaComponent(0.35).setStroke();NSBezierPath(roundedRect:rect.insetBy(dx:0.5,dy:0.5),xRadius:12,yRadius:12).stroke()
                if let icon=StatusPresentation.icons[card.key] { icon.draw(in:NSRect(x:x+14,y:y+14,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
                text(card.name,NSRect(x:x+42,y:y+14,width:width-54,height:22),15,.labelColor,.semibold)
                text(card.stale ? "Desatualizado · " + localDate(card.snapshot.queriedAt) : (card.note ?? "Observado " + localDate(card.snapshot.queriedAt)),NSRect(x:x+14,y:y+42,width:width-28,height:18),10,card.stale ? .systemOrange : .secondaryLabelColor)
                for (index,window) in card.windows.enumerated() {
                    let top=y+70+CGFloat(index)*90, remaining=window.remaining!
                    let label=window.durationMinutes.map { $0==10080 ? "Semanal" : durationLabel($0) } ?? window.name
                    text(label,NSRect(x:x+14,y:top,width:width-100,height:20),12,.secondaryLabelColor,.medium)
                    text(percentLabel(remaining),NSRect(x:x+width-78,y:top-4,width:64,height:27),21,.labelColor,.semibold)
                    let track=NSRect(x:x+14,y:top+25,width:width-28,height:5)
                    NSColor.quaternaryLabelColor.setFill();NSBezierPath(roundedRect:track,xRadius:2.5,yRadius:2.5).fill()
                    (remaining <= 10 ? NSColor.systemRed : remaining <= 25 ? NSColor.systemOrange : NSColor.systemGreen).setFill()
                    if remaining>0 {NSBezierPath(roundedRect:NSRect(x:track.minX,y:track.minY,width:track.width*remaining/100,height:5),xRadius:2.5,yRadius:2.5).fill()}
                    text(window.reset.map { "Reset: " + localDate(Date(timeIntervalSince1970:$0)) } ?? "Reset não informado",NSRect(x:x+14,y:top+37,width:width-28,height:18),10,.secondaryLabelColor)
                    if window.reset != nil { text(countdownLabel(reset:window.reset),NSRect(x:x+14,y:top+54,width:width-28,height:18),10,.secondaryLabelColor) }
                }
            }
            y += height+12
        }
        text(pinned ? "Fixado · arraste a faixa superior para mover" : "Clique no conteúdo para fechar",NSRect(x:20,y:bounds.height-26,width:bounds.width-40,height:18),10,.secondaryLabelColor)
    }
}

final class QuotaDashboardHeader: NSView {
    var pinned=false
    override func mouseDown(with event:NSEvent) { if pinned {window?.performDrag(with:event)} }
}

final class QuotaDashboard: NSObject {
    private(set) var panel: NSPanel?
    private var timer: Timer?, localMonitor: Any?, globalMonitor: Any?
    private(set) var pinned=false
    private(set) var scale:CGFloat=1
    var onRefresh: () -> Void = {}
    var refreshEnabled=true
    var refreshMessage=""
    var cards: [QuotaCard] = []
    var isVisible: Bool { panel?.isVisible ?? false }
    func toggle(anchor:NSRect,screen:NSScreen) {
        if isVisible {close()} else {show(anchor:anchor,screen:screen)}
    }
    func show(anchor:NSRect,screen:NSScreen,timeout:TimeInterval=15) {
        close()
        let panel=NSPanel(contentRect:NSRect(x:anchor.maxX-600,y:anchor.minY-300,width:600,height:300),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false;panel.level = .floating;panel.hasShadow=true
        panel.sharingType = .readOnly
        panel.backgroundColor = .windowBackgroundColor;panel.isOpaque=false;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient]
        self.panel=panel
        render(screen:screen,top:NSPoint(x:anchor.maxX-min(600*scale,screen.visibleFrame.width-24),y:anchor.minY-8))
        panel.orderFrontRegardless()
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) { [weak self] event in
            guard let self=self,self.isVisible else{return event}
            if event.type == .keyDown {if event.keyCode==53 {self.close();return nil};return event}
            if event.window === self.panel {
                let point=self.panel!.contentView!.convert(event.locationInWindow,from:nil)
                // Header and all of its buttons stay interactive in transient mode.
                if point.y >= self.panel!.contentView!.bounds.height-64 {self.armTimer();return event}
                if self.pinned {return event}
                self.close();return nil
            }
            return event
        }
        armTimer(timeout)
    }
    func update() { if let panel=panel,let screen=panel.screen ?? NSScreen.main {render(screen:screen,top:NSPoint(x:panel.frame.minX,y:panel.frame.maxY))} }
    private func render(screen:NSScreen,top:NSPoint) {
        guard let panel=panel else{return}
        let area=screen.visibleFrame,width=min(600*scale,area.width-24)
        let view=QuotaDashboardView(cards:QuotaCard.available(cards),width:width/scale)
        view.pinned=pinned
        let logical=view.bounds;view.setFrameSize(NSSize(width:logical.width*scale,height:logical.height*scale));view.bounds=logical
        let height=min(view.frame.height+64,area.height-24)
        let x=max(area.minX+12,min(top.x,area.maxX-width-12))
        let y=max(area.minY+12,min(top.y-height,area.maxY-height-12))
        panel.setFrame(NSRect(x:x,y:y,width:width,height:height),display:true)
        let content=NSView(frame:NSRect(x:0,y:0,width:width,height:height));content.wantsLayer=true;content.layer?.cornerRadius=16;content.layer?.masksToBounds=true
        let header=QuotaDashboardHeader(frame:NSRect(x:0,y:height-64,width:width,height:64));header.pinned=pinned
        func button(_ title:String,_ x:CGFloat,_ width:CGFloat,_ action:Selector)->NSButton {
            let button=NSButton(title:title,target:self,action:action);button.bezelStyle = .rounded
            button.frame=NSRect(x:x,y:31,width:width,height:26);header.addSubview(button);return button
        }
        let refresh=button("Atualizar",14,90,#selector(refreshNow));refresh.isEnabled=refreshEnabled
        _=button(pinned ? "Desafixar" : "Fixar",110,90,#selector(togglePinned))
        let sizes=NSSegmentedControl(labels:["1×","1,25×","1,5×"],trackingMode:.selectOne,target:self,action:#selector(changeScale(_:)))
        sizes.frame=NSRect(x:210,y:31,width:165,height:26);sizes.selectedSegment=scale==1 ? 0 : scale==1.25 ? 1 : 2;header.addSubview(sizes)
        _=button("×",width-46,32,#selector(dismissPanel))
        let message=NSTextField(labelWithString:refreshMessage.isEmpty ? (pinned ? "Fixado · arraste esta faixa para mover" : "Fecha em 15s · clique no conteúdo para fechar") : refreshMessage)
        message.frame=NSRect(x:16,y:8,width:width-32,height:17);message.font = .systemFont(ofSize:10);message.textColor = .secondaryLabelColor;message.lineBreakMode = .byTruncatingTail;header.addSubview(message)
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:width,height:height-64));scroll.drawsBackground=false;scroll.hasVerticalScroller=view.frame.height>height-64
        scroll.documentView=view;view.dismiss = {[weak self] in if self?.pinned == false {self?.close()}}
        content.addSubview(scroll);content.addSubview(header);panel.contentView=content
    }
    func armTimer(_ seconds:TimeInterval=15) {
        timer?.invalidate();timer=nil
        guard isVisible,!pinned else{return}
        let next=Timer(timeInterval:seconds,repeats:false){[weak self] _ in self?.close()}
        RunLoop.main.add(next,forMode:.common);timer=next
    }
    @objc func refreshNow() {
        guard refreshEnabled else{return}
        refreshMessage="Atualização solicitada; limites de cada provedor continuam valendo"
        onRefresh();update();armTimer()
    }
    @objc func togglePinned() {pinned.toggle();armTimer();update()}
    func setScale(_ value:CGFloat) {guard [CGFloat(1),1.25,1.5].contains(value) else{return};scale=value;update();armTimer()}
    @objc func changeScale(_ sender:NSSegmentedControl) {guard (0...2).contains(sender.selectedSegment) else{return};setScale([1,1.25,1.5][sender.selectedSegment])}
    @objc func dismissPanel() {close()}
    func close() {
        timer?.invalidate();timer=nil
        if let monitor=localMonitor {NSEvent.removeMonitor(monitor)};localMonitor=nil
        if let monitor=globalMonitor {NSEvent.removeMonitor(monitor)};globalMonitor=nil
        panel?.orderOut(nil);panel=nil
    }
    deinit {close()}
}

func runQuotaDashboardTests() {
    var count=0
    func check(_ value:Bool,_ label:String) {guard value else{fputs("FAIL dashboard: \(label)\n",stderr);exit(1)};count += 1}
    let known=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"5h",remaining:72,durationMinutes:300,reset:nil),QuotaWindow(name:"week",remaining:45,durationMinutes:10080,reset:nil)])
    let missing=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"unknown",remaining:nil,durationMinutes:300,reset:nil)])
    let cards=[QuotaCard(key:"codex",name:"Codex",snapshot:known,stale:false),QuotaCard(key:"kimi",name:"Kimi Code",snapshot:missing,stale:false)]
    check(QuotaCard.available(cards).count==1,"providers without metrics hidden")
    let zero=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"5h",remaining:0,durationMinutes:300,reset:nil)])
    check(!QuotaCard.available([QuotaCard(key:"kimi",name:"Kimi",snapshot:zero,stale:true)]).isEmpty,"zero remaining is valid data")
    let view=QuotaDashboardView(cards:QuotaCard.available(cards),width:600)
    check(view.columns==2 && view.frame.height>200,"card layout")
    check(QuotaDashboardView(cards:[],width:400).columns==1,"narrow screen layout")
    guard let screen=NSScreen.main else {fatalError("screen required")}
    let dashboard=QuotaDashboard();dashboard.cards=cards
    let anchor=NSRect(x:screen.visibleFrame.maxX-100,y:screen.visibleFrame.maxY,width:80,height:20)
    dashboard.show(anchor:anchor,screen:screen,timeout:0.05)
    check(dashboard.isVisible,"panel shown")
    check(dashboard.panel?.sharingType == .readOnly,"panel allows capture")
    let end=Date().addingTimeInterval(3);while dashboard.isVisible && Date()<end {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
    check(!dashboard.isVisible,"auto dismiss")
    dashboard.show(anchor:anchor,screen:screen);dashboard.close();check(!dashboard.isVisible,"click dismissal cleanup")
    dashboard.show(anchor:anchor,screen:screen,timeout:0.05);dashboard.togglePinned()
    RunLoop.current.run(until:Date().addingTimeInterval(0.1))
    check(dashboard.isVisible && dashboard.pinned,"pin cancels auto dismissal")
    var refreshes=0;dashboard.onRefresh={refreshes += 1};dashboard.refreshNow()
    check(refreshes==1 && dashboard.isVisible,"refresh action does not dismiss")
    let initialWidth=dashboard.panel!.frame.width
    dashboard.setScale(1.25);check(dashboard.scale==1.25 && dashboard.panel!.frame.width>=initialWidth,"125 percent sizing")
    dashboard.setScale(1.5);check(dashboard.scale==1.5,"150 percent sizing")
    dashboard.setScale(1);check(dashboard.scale==1,"size returns to normal")
    dashboard.togglePinned();dashboard.armTimer(0.05)
    let unpinDeadline=Date().addingTimeInterval(3)
    while dashboard.isVisible && Date()<unpinDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
    check(!dashboard.isVisible && !dashboard.pinned,"unpin restores auto dismissal")
    print("PASS quota dashboard: \(count) checks; synthetic data only")
}
