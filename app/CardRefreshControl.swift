import AppKit

struct CardRefreshStatus {
    var busy=false
    var nextAllowedAt=Date.distantPast
    var paused=false
    var actionTitle="Atualizar agora"
    func enabled(now:Date=Date())->Bool {!busy && !paused && now>=nextAllowedAt}
    func label(now:Date=Date())->String {
        if busy {return "Atualizando…"}
        if paused {return "Atualizações pausadas"}
        if now<nextAllowedAt {return "Disponível em \(Int(ceil(nextAllowedAt.timeIntervalSince(now))))s"}
        return actionTitle
    }
}

enum CardRefreshRouting {
    @discardableResult static func request(_ provider:String,selected:Set<String>,states:[String:CardRefreshStatus],actions:[String:()->Void],now:Date=Date())->Bool {
        guard selected.contains(provider),let status=states[provider],status.enabled(now:now),let action=actions[provider] else{return false}
        action();return true
    }
}

final class CardRefreshControl:NSButton {
    let provider:String
    let providerName:String
    var status:CardRefreshStatus
    var onRefresh:(String)->Void={_ in}
    private(set) var hovered=false
    private var keyboardFocused=false
    private var tracking:NSTrackingArea?
    private var clock:Timer?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(provider:String,name:String,frame:NSRect,status:CardRefreshStatus) {
        self.provider=provider;self.providerName=name;self.status=status
        super.init(frame:frame)
        title="";isBordered=false;setButtonType(.momentaryChange);target=self;action=#selector(refreshCard)
        focusRingType = .exterior;refreshState()
    }
    required init?(coder:NSCoder){fatalError("init(coder:) not supported")}
    @objc private func refreshCard(){guard status.enabled() else{return};onRefresh(provider)}
    func refreshState(now:Date=Date()) {
        let wasEnabled=isEnabled
        isEnabled=status.enabled(now:now)
        if wasEnabled != isEnabled {window?.invalidateCursorRects(for:self)}
        setAccessibilityLabel(providerName+": "+status.label(now:now))
        setAccessibilityHelp("Atualiza somente este provedor e mantém o painel aberto.")
        needsDisplay=true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking=tracking {removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window=window {setHovered(visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil)))} else {setHovered(false)}
    }
    private func updateClock() {
        clock?.invalidate();clock=nil;refreshState()
        if (hovered || keyboardFocused) && !status.busy && status.nextAllowedAt>Date() {
            let timer=Timer(timeInterval:1,repeats:true){[weak self] timer in
                guard let self=self else{timer.invalidate();return}
                self.refreshState()
                if self.status.nextAllowedAt<=Date() {timer.invalidate();self.clock=nil}
            }
            RunLoop.main.add(timer,forMode:.common);clock=timer
        }
    }
    func setHovered(_ value:Bool) {hovered=value;updateClock()}
    override func mouseEntered(with event:NSEvent){setHovered(true)}
    override func mouseExited(with event:NSEvent){setHovered(false)}
    override func resetCursorRects(){addCursorRect(bounds,cursor:isEnabled ? .pointingHand : .arrow)}
    override func becomeFirstResponder()->Bool {let result=super.becomeFirstResponder();keyboardFocused=result;updateClock();return result}
    override func resignFirstResponder()->Bool {let result=super.resignFirstResponder();if result {keyboardFocused=false};updateClock();return result}
    override func keyDown(with event:NSEvent) {
        if event.keyCode==36 || event.keyCode==49 {if isEnabled {performClick(nil)}} else {super.keyDown(with:event)}
    }
    override func draw(_ dirtyRect:NSRect) {
        guard hovered || status.busy || (keyboardFocused && window?.isKeyWindow==true) else{return}
        let color=isEnabled || status.busy ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        let box=NSRect(x:1,y:23,width:bounds.width-2,height:bounds.height-24)
        color.withAlphaComponent(0.06).setFill();let path=NSBezierPath(roundedRect:box,xRadius:12,yRadius:12);path.fill()
        color.setStroke();path.lineWidth=2;path.stroke()
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        (status.label() as NSString).draw(in:NSRect(x:0,y:0,width:bounds.width,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:color,.paragraphStyle:paragraph])
    }
    deinit {clock?.invalidate()}
}

func runCardRefreshRoutingTests() {
    var calls:[String]=[];let now=Date()
    let actions:[String:()->Void]=["codex":{calls.append("codex")},"grok":{calls.append("grok")}]
    let states=["codex":CardRefreshStatus(),"grok":CardRefreshStatus(busy:true)]
    guard CardRefreshRouting.request("codex",selected:["codex","grok"],states:states,actions:actions),calls==["codex"],
          !CardRefreshRouting.request("grok",selected:["codex","grok"],states:states,actions:actions),
          !CardRefreshRouting.request("codex",selected:[],states:states,actions:actions),
          !CardRefreshStatus(nextAllowedAt:now.addingTimeInterval(60)).enabled(now:now) else{fatalError("FAIL individual refresh routing")}
    print("PASS individual refresh: only selected target, busy and cooldown guarded")
}
