import AppKit

struct QuotaCard {
    let key: String, name: String
    let snapshot: QuotaSnapshot
    let stale: Bool
    var note: String? = nil
    var windows: [QuotaWindow] { snapshot.windows.filter { $0.remaining.map { $0.isFinite && $0 >= 0 && $0 <= 100 } ?? false }.sorted { ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max) } }
    static func windowLabel(_ window:QuotaWindow)->String {
        if window.name.localizedCaseInsensitiveContains("MCP") {return "MCP"}
        return window.durationMinutes.map {$0 == 10080 ? "Semanal" : durationLabel($0)} ?? window.name
    }
    var detail:String? {
        if key=="claude" {
            return stale ? "Aguardando atualização do Claude Code" : "Leitura passiva do Claude Code"
        }
        let parts=[stale ? "Dados desatualizados" : nil,note].compactMap {$0}
        return parts.isEmpty ? nil : parts.joined(separator:" · ")
    }
    var deliveryDate:Date {snapshot.receivedAt ?? snapshot.queriedAt}
    static func available(_ values: [QuotaCard]) -> [QuotaCard] { values.filter { !$0.windows.isEmpty } }
}

final class QuotaDashboardView: NSView {
    let cards: [QuotaCard]
    let columns: Int
    var dismiss: () -> Void = {}
    var pinned=false
    override var isFlipped: Bool { true }
    static func cardHeight(_ card:QuotaCard)->CGFloat {CGFloat(76 + card.windows.count * 96 + (card.detail == nil ? 0 : 24))}
    static func cardFrames(_ cards:[QuotaCard],width:CGFloat)->[NSRect] {
        let columns=width < 500 ? 1 : 2
        let cardWidth=(width-40-CGFloat(columns-1)*12)/CGFloat(columns)
        var nextY=Array(repeating:CGFloat(76),count:columns)
        return cards.enumerated().map {index,card in
            let column=index % columns
            let rect=NSRect(x:20+CGFloat(column)*(cardWidth+12),y:nextY[column],width:cardWidth,height:cardHeight(card))
            nextY[column]=rect.maxY+12
            return rect
        }
    }
    init(cards: [QuotaCard], width: CGFloat) {
        self.cards=cards;columns=width < 500 ? 1 : 2
        let bottom=Self.cardFrames(cards,width:width).map(\.maxY).max() ?? 112
        super.init(frame:NSRect(x:0,y:0,width:width,height:bottom+38))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        let summaries: [String] = cards.map { card in
            let windows: [String] = card.windows.map { window in
                QuotaCard.windowLabel(window) + " " + percentLabel(window.remaining)
            }
            let freshness = card.detail.map {", "+$0} ?? ""
            return card.name + freshness + ": " + windows.joined(separator:", ")
        }
        setAccessibilityLabel("Quotas disponíveis. " + summaries.joined(separator:". "))
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) not supported") }
    override func mouseDown(with event:NSEvent) { dismiss() }
    private func text(_ value:String,_ rect:NSRect,_ size:CGFloat,_ color:NSColor = .labelColor,_ weight:NSFont.Weight = .regular,alignment:NSTextAlignment = .left,monospaced:Bool=false) {
        let style=NSMutableParagraphStyle();style.lineBreakMode = .byTruncatingTail;style.alignment=alignment
        (value as NSString).draw(in:rect,withAttributes:[.font:monospaced ? NSFont.monospacedDigitSystemFont(ofSize:size,weight:weight) : NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:style])
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.windowBackgroundColor.setFill();bounds.fill()
        text("Disponibilidade",NSRect(x:20,y:18,width:bounds.width-40,height:26),20,.labelColor,.semibold)
        text("Saldo restante por janela de uso",NSRect(x:20,y:46,width:bounds.width-40,height:18),12,.secondaryLabelColor)
        if cards.isEmpty { text("Nenhuma métrica disponível no momento.",NSRect(x:20,y:88,width:bounds.width-40,height:24),13,.secondaryLabelColor) }
        for (card,rect) in zip(cards,Self.cardFrames(cards,width:bounds.width)) {
                let x=rect.minX,y=rect.minY,width=rect.width
                NSColor.labelColor.withAlphaComponent(0.055).setFill();NSBezierPath(roundedRect:rect,xRadius:12,yRadius:12).fill()
                NSColor.separatorColor.withAlphaComponent(0.35).setStroke();NSBezierPath(roundedRect:rect.insetBy(dx:0.5,dy:0.5),xRadius:12,yRadius:12).stroke()
                if let icon=StatusPresentation.icons[card.key] { icon.draw(in:NSRect(x:x+14,y:y+14,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
                text(card.name,NSRect(x:x+42,y:y+14,width:width-54,height:22),15,.labelColor,.semibold)
                text("Recebido em " + localDate(card.deliveryDate),NSRect(x:x+14,y:y+42,width:width-28,height:18),11,.secondaryLabelColor)
                for (index,window) in card.windows.enumerated() {
                    let top=y+76+CGFloat(index)*96, remaining=window.remaining!
                    let label=QuotaCard.windowLabel(window)
                    text(label,NSRect(x:x+14,y:top,width:width-116,height:20),12,.secondaryLabelColor,.medium)
                    text(percentLabel(remaining),NSRect(x:x+width-96,y:top-4,width:82,height:27),21,.labelColor,.semibold,alignment:.right,monospaced:true)
                    let track=NSRect(x:x+14,y:top+25,width:width-28,height:5)
                    NSColor.quaternaryLabelColor.setFill();NSBezierPath(roundedRect:track,xRadius:2.5,yRadius:2.5).fill()
                    (remaining <= 10 ? NSColor.systemRed : remaining <= 25 ? NSColor.systemOrange : NSColor.systemGreen).setFill()
                    if remaining>0 {NSBezierPath(roundedRect:NSRect(x:track.minX,y:track.minY,width:track.width*remaining/100,height:5),xRadius:2.5,yRadius:2.5).fill()}
                    text(window.reset.map { "Renovação: " + localDate(Date(timeIntervalSince1970:$0)) } ?? "Renovação não informada",NSRect(x:x+14,y:top+37,width:width-28,height:18),10,.secondaryLabelColor)
                    if window.reset != nil { text(countdownLabel(reset:window.reset),NSRect(x:x+14,y:top+54,width:width-28,height:18),10,.secondaryLabelColor) }
                }
                if let detail=card.detail {text(detail,NSRect(x:x+14,y:rect.maxY-26,width:width-28,height:18),11,card.stale ? .systemOrange : .secondaryLabelColor)}
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
    private var headerHeight:CGFloat=64
    var onRefresh: () -> Void = {}
    var onAccess: () -> Void = {}
    var onOptionsChanged:(Double,Bool)->Void={_,_ in}
    var autoCloseSeconds:TimeInterval=15
    var refreshEnabled=true
    var refreshMessage=""
    var cards: [QuotaCard] = []
    var isVisible: Bool { panel?.isVisible ?? false }
    func toggle(anchor:NSRect,screen:NSScreen) {
        if isVisible {close()} else {show(anchor:anchor,screen:screen)}
    }
    func show(anchor:NSRect,screen:NSScreen,timeout:TimeInterval?=nil) {
        tearDown()
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
            if event.type == .keyDown {if event.keyCode==53 && (event.window == nil || event.window === self.panel) {self.close();return nil};return event}
            if event.window === self.panel {
                let point=self.panel!.contentView!.convert(event.locationInWindow,from:nil)
                // Header and all of its buttons stay interactive in transient mode.
                if point.y >= self.panel!.contentView!.bounds.height-self.headerHeight {self.armTimer();return event}
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
        headerHeight=width<530 ? 94 : 64
        let height=min(view.frame.height+headerHeight,area.height-24)
        let x=max(area.minX+12,min(top.x,area.maxX-width-12))
        let y=max(area.minY+12,min(top.y-height,area.maxY-height-12))
        panel.setFrame(NSRect(x:x,y:y,width:width,height:height),display:true)
        let content=NSView(frame:NSRect(x:0,y:0,width:width,height:height));content.wantsLayer=true;content.layer?.cornerRadius=16;content.layer?.masksToBounds=true
        let header=QuotaDashboardHeader(frame:NSRect(x:0,y:height-headerHeight,width:width,height:headerHeight));header.pinned=pinned
        func button(_ title:String,_ x:CGFloat,_ width:CGFloat,_ action:Selector)->NSButton {
            let button=NSButton(title:title,target:self,action:action);button.bezelStyle = .rounded
            button.frame=NSRect(x:x,y:headerHeight-33,width:width,height:26);header.addSubview(button);return button
        }
        let refresh=button("Atualizar",14,90,#selector(refreshNow));refresh.isEnabled=refreshEnabled
        _=button(pinned ? "Desafixar" : "Fixar",110,90,#selector(togglePinned))
        let sizes=NSSegmentedControl(labels:["1×","1,25×","1,5×"],trackingMode:.selectOne,target:self,action:#selector(changeScale(_:)))
        sizes.frame=NSRect(x:width<530 ? 14 : 210,y:width<530 ? 8 : 31,width:165,height:26);sizes.selectedSegment=scale==1 ? 0 : scale==1.25 ? 1 : 2;header.addSubview(sizes)
        _=button("Configurações",width<530 ? 210 : 385,130,#selector(openAccess))
        _=button("×",width-46,32,#selector(dismissPanel))
        let message=NSTextField(labelWithString:refreshMessage.isEmpty ? (pinned ? "Fixado · arraste esta faixa para mover" : "Fecha em \(Int(autoCloseSeconds))s · clique no conteúdo para fechar") : refreshMessage)
        message.frame=NSRect(x:width<530 ? 190 : 16,y:8,width:width-(width<530 ? 206 : 32),height:17);message.font = .systemFont(ofSize:10);message.textColor = .secondaryLabelColor;message.lineBreakMode = .byTruncatingTail;header.addSubview(message)
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:width,height:height-headerHeight));scroll.drawsBackground=false;scroll.hasVerticalScroller=view.frame.height>height-headerHeight
        scroll.documentView=view;view.dismiss = {[weak self] in if self?.pinned == false {self?.close()}}
        content.addSubview(scroll);content.addSubview(header);panel.contentView=content
    }
    func armTimer(_ seconds:TimeInterval?=nil) {
        timer?.invalidate();timer=nil
        guard isVisible,!pinned else{return}
        let next=Timer(timeInterval:seconds ?? autoCloseSeconds,repeats:false){[weak self] _ in self?.close()}
        RunLoop.main.add(next,forMode:.common);timer=next
    }
    @objc func refreshNow() {
        guard refreshEnabled else{return}
        refreshMessage="Atualização solicitada; limites de cada provedor continuam valendo"
        onRefresh();update();armTimer()
    }
    @objc func togglePinned() {pinned.toggle();armTimer();update();onOptionsChanged(Double(scale),pinned)}
    func setScale(_ value:CGFloat) {guard [CGFloat(1),1.25,1.5].contains(value) else{return};scale=value;update();armTimer();onOptionsChanged(Double(scale),pinned)}
    @objc func changeScale(_ sender:NSSegmentedControl) {guard (0...2).contains(sender.selectedSegment) else{return};setScale([1,1.25,1.5][sender.selectedSegment])}
    @objc func openAccess() {onAccess()}
    @objc func dismissPanel() {close()}
    func close() {
        let wasPinned=pinned
        pinned=false
        tearDown()
        if wasPinned {onOptionsChanged(Double(scale),false)}
    }
    private func tearDown() {
        timer?.invalidate();timer=nil
        if let monitor=localMonitor {NSEvent.removeMonitor(monitor)};localMonitor=nil
        if let monitor=globalMonitor {NSEvent.removeMonitor(monitor)};globalMonitor=nil
        panel?.orderOut(nil);panel=nil
    }
    deinit {tearDown()}
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
    let compact=[cards[0],QuotaCard(key:"other",name:"Other",snapshot:zero,stale:false),cards[0]]
    let frames=QuotaDashboardView.cardFrames(compact,width:600)
    check(frames[1].height<frames[0].height,"card height follows own content")
    check(frames[2].minY==frames[0].maxY+12,"columns stack without shared row whitespace")
    check(QuotaCard.windowLabel(QuotaWindow(name:"Uso MCP (janela não informada)",remaining:100,durationMinutes:nil,reset:nil))=="MCP","MCP label stays short")
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
    var settingsOpened=false;dashboard.onAccess={settingsOpened=true};dashboard.openAccess()
    check(settingsOpened && dashboard.isVisible && dashboard.pinned,"settings independent of pinned dashboard")
    let initialWidth=dashboard.panel!.frame.width
    dashboard.setScale(1.25);check(dashboard.scale==1.25 && dashboard.panel!.frame.width>=initialWidth,"125 percent sizing")
    dashboard.setScale(1.5);check(dashboard.scale==1.5,"150 percent sizing")
    dashboard.setScale(1);check(dashboard.scale==1,"size returns to normal")
    dashboard.togglePinned();dashboard.armTimer(0.05)
    let unpinDeadline=Date().addingTimeInterval(3)
    while dashboard.isVisible && Date()<unpinDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
    check(!dashboard.isVisible && !dashboard.pinned,"unpin restores auto dismissal")
    dashboard.show(anchor:anchor,screen:screen);dashboard.togglePinned();dashboard.dismissPanel()
    check(!dashboard.pinned && !dashboard.isVisible,"closing clears pin")
    print("PASS quota dashboard: \(count) checks; synthetic data only")
}
