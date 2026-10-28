import AppKit

struct ProviderAccess: Equatable {
    let key:String, name:String, status:String, detail:String, actionTitle:String
    var connected=false
    var selected=true
    var selectionEnabled=true
    var enabled=true
    var actions:[String]=[]
}
final class ConnectionButton: NSButton {
    var connected=false
    override func draw(_ dirtyRect:NSRect) {
        let color=connected ? NSColor.systemGreen : NSColor.systemGray
        color.withAlphaComponent(isEnabled ? (isHighlighted ? 0.75 : 1) : 0.45).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7).fill()
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        let text=NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:NSColor.white,.paragraphStyle:paragraph])
        text.draw(in:NSRect(x:2,y:(bounds.height-text.size().height)/2,width:bounds.width-4,height:text.size().height))
    }
}
final class AccessSetup: NSObject {
    private(set) var panel:NSPanel?
    var providers:[ProviderAccess]=[]
    var summary="Sem métrica, o provedor fica oculto na barra e no painel."
    var onSelect:(String,Bool)->Void={_,_ in}
    var onUpgrade:()->Void={}
    @objc func upgrade(){onUpgrade()}
    @objc func togglePlan(_ sender:NSButton) {
        guard providers.indices.contains(sender.tag),providers[sender.tag].selectionEnabled else{return}
        onSelect(providers[sender.tag].key,sender.state == .on)
    }
    var onConfigure:(String)->Void = {_ in}
    func show() {
        panel?.close()
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:620,height:560),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title="PlanMeter · Contas";panel.isReleasedWhenClosed=false
        panel.contentView=makeContentView();panel.center();self.panel=panel
        NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)
    }
    func makeContentView()->NSView {
        let width:CGFloat=620,height:CGFloat=560
        let view=NSView(frame:NSRect(x:0,y:0,width:width,height:height))
        func label(_ text:String,_ frame:NSRect,_ size:CGFloat,_ bold:Bool=false)->NSTextField {
            let label=NSTextField(wrappingLabelWithString:text);label.frame=frame;label.font = .systemFont(ofSize:size,weight:bold ? .semibold : .regular);view.addSubview(label);return label
        }
        _=label("Conecte os serviços que você usa",NSRect(x:22,y:height-48,width:width-44,height:26),21,true)
        _=label(summary,NSRect(x:22,y:height-90,width:width-158,height:40),13)
        let upgrade=NSButton(title:"Sobre o Pro",target:self,action:#selector(upgrade));upgrade.bezelStyle = .rounded;upgrade.frame=NSRect(x:width-130,y:height-82,width:108,height:28);view.addSubview(upgrade)
        for (index,provider) in providers.enumerated() {
            let y=height-163-CGFloat(index)*87
            let toggle=NSButton(checkboxWithTitle:"",target:self,action:#selector(togglePlan(_:)))
            toggle.tag=index;toggle.state=provider.selected ? .on : .off;toggle.isEnabled=provider.selectionEnabled;toggle.frame=NSRect(x:22,y:y+49,width:22,height:23);toggle.setAccessibilityLabel("Monitorar "+provider.name);view.addSubview(toggle)
            _=label(provider.name,NSRect(x:48,y:y+49,width:180,height:23),16,true)
            _=label(provider.detail,NSRect(x:22,y:y+4,width:width-(provider.actions.isEmpty ? 188 : 230),height:43),13)
            let action=ConnectionButton(title:provider.connected ? "Conectado" : "Conectar",target:self,action:#selector(configure(_:)));action.connected=provider.connected;action.tag=index;action.isEnabled=provider.enabled;action.bezelStyle = .rounded;action.font = .systemFont(ofSize:14,weight:.medium);action.bezelColor=provider.connected ? .systemGreen : .systemGray;action.contentTintColor = .white;action.setAccessibilityLabel(provider.name + (provider.connected ? ", conectado" : ", conectar"));action.frame=NSRect(x:width-(provider.actions.isEmpty ? 152 : 194),y:y+39,width:128,height:30);view.addSubview(action)
            if !provider.actions.isEmpty {
                let more=NSPopUpButton(frame:NSRect(x:width-54,y:y+39,width:32,height:30),pullsDown:true)
                more.menu?.autoenablesItems=false;more.addItem(withTitle:"•••");more.isEnabled=provider.enabled || provider.actions.contains("remove")
                for action in provider.actions {
                    let label=action=="authorize" ? "Autorizar acesso" : action=="passive" ? "Usar leitura passiva…" : "Remover chave…"
                    let item=NSMenuItem(title:label,action:#selector(extraAction(_:)),keyEquivalent:"")
                    item.target=self;item.isEnabled=provider.enabled || action=="remove";item.representedObject=provider.key+":"+action;more.menu?.addItem(item)
                }
                more.setAccessibilityLabel("Mais opções de "+provider.name);view.addSubview(more)
            }
        }
        return view
    }
    @objc func configure(_ sender:NSButton) {
        guard providers.indices.contains(sender.tag),providers[sender.tag].enabled else{return}
        panel?.orderOut(nil);onConfigure(providers[sender.tag].key)
    }
    @objc func extraAction(_ sender:NSMenuItem) {
        guard let key=sender.representedObject as? String else{return}
        let parts=key.split(separator:":",maxSplits:1).map(String.init)
        guard parts.count==2,let provider=providers.first(where:{$0.key==parts[0]}),(provider.enabled || parts[1]=="remove"),provider.actions.contains(parts[1]) else{return}
        onConfigure(key)
    }
    static func helperCommand(_ path:String)->String {
        guard path.hasPrefix("/") else{return ""}
        let quoted="'"+path.replacingOccurrences(of:"'",with:"'\\''")+"'"
        return "python3 "+quoted+" --apply"
    }
    static func instruction(for key:String)->(String,String,String) {
        switch key {
        case "codex": return("Instale o Codex CLI oficial e execute este comando no Terminal. Conclua o login com sua conta ChatGPT e depois atualize o PlanMeter.","codex login","https://developers.openai.com/codex/cli/")
        case "claude":
            guard let helper=Bundle.main.url(forResource:"configure-claude",withExtension:"py",subdirectory:"Integration") else {
                return("O configurador não foi encontrado nesta instalação. Reinstale a versão atual do PlanMeter ou siga o guia oficial.","","https://github.com/pcarielo/planmeter/blob/main/docs/getting-started.md#claude-code")
            }
            return("Execute o comando em qualquer pasta do Terminal. O configurador incluído no aplicativo faz backup e preserva sua statusline. Os dados se renovam com o uso normal do Claude Code.",helperCommand(helper.path),"https://github.com/pcarielo/planmeter/blob/main/docs/getting-started.md#claude-code")
        case "grok": return("Instale o Grok Build oficial e execute este comando no Terminal. Conclua o login da assinatura e depois atualize o PlanMeter. Não use uma chave da API para substituir a assinatura.","grok login","https://docs.x.ai/build/overview")
        default: return("A conexão deste provedor é gerenciada no serviço remoto. Ajuste a autenticação pelo fluxo seguro usado naquele host.","","")
        }
    }
    static func guideURLResponse(command:String,url:String)->NSApplication.ModalResponse? {
        guard !url.isEmpty else{return nil}
        return NSApplication.ModalResponse(rawValue:command.isEmpty ? 1001 : 1002)
    }
    static func guide(_ key:String,measurement:String?=nil) {
        let (detail,command,url)=instruction(for:key)
        let alert=NSAlert();alert.messageText="Conectar " + key.capitalized
        alert.informativeText=(measurement.map {$0 + "\n\n"} ?? "") + detail + (command.isEmpty ? "" : "\n\n"+command)
        alert.addButton(withTitle:"Fechar")
        if !command.isEmpty {alert.addButton(withTitle:"Copiar comando")}
        if !url.isEmpty {alert.addButton(withTitle:"Abrir guia oficial")}
        let answer=alert.runModal()
        if answer == .alertSecondButtonReturn && !command.isEmpty {NSPasteboard.general.clearContents();NSPasteboard.general.setString(command,forType:.string)}
        if let expected=guideURLResponse(command:command,url:url),answer==expected,let link=URL(string:url) {NSWorkspace.shared.open(link)}
    }
}

func runAccessTests() {
    var count=0
    func check(_ value:Bool,_ label:String) {guard value else{fputs("FAIL accesses: \(label)\n",stderr);exit(1)};count += 1}
    let absent=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"unknown",remaining:nil,durationMinutes:nil,reset:nil)])
    let zero=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"5h",remaining:0,durationMinutes:300,reset:nil)])
    let empty=StatusPresentation.make(codex:nil,claude:absent,zai:nil,codexStale:false,claudeStale:false,zaiStale:false,badge:"")
    check(empty.title.string=="PlanMeter","neutral entry keeps setup reachable")
    let partial=StatusPresentation.make(codex:zero,claude:absent,zai:nil,codexStale:true,claudeStale:false,zaiStale:false,badge:"")
    check(partial.accessibilityText.contains("Codex 0%") && !partial.accessibilityText.contains("Claude") && !partial.accessibilityText.contains("Z.ai"),"only valid provider remains including zero")
    check(StatusPresentation.zaiText(zero)=="5h 0%","missing weekly window not shown")
    check(!QuotaCard.available([QuotaCard(key:"codex",name:"Codex",snapshot:zero,stale:true)]).isEmpty,"stale last known data retained")
    let access=AccessSetup();var selected=""
    access.providers=[ProviderAccess(key:"kimi",name:"Kimi",status:"Sem métrica",detail:"Chave",actionTitle:"Cadastrar chave")]
    access.onConfigure={selected=$0}
    let action=NSButton();action.tag=0;access.configure(action)
    check(selected=="kimi","configuration routes to selected provider")
    check(AccessSetup.instruction(for:"codex").1=="codex login","official login guide")
    check(AccessSetup.instruction(for:"grok").1=="grok login","subscription login guide")
    let dashboard=QuotaDashboard();var opened=false;dashboard.onAccess={opened=true};dashboard.openAccess()
    check(opened,"dashboard setup accessible without data")
    let view=access.makeContentView()
    let connect=view.subviews.compactMap {$0 as? NSButton}.first {$0.title=="Conectar"}
    check(connect?.bezelColor == NSColor.systemGray,"disconnected action is gray")
    access.providers[0].connected=true
    let connected=access.makeContentView().subviews.compactMap {$0 as? NSButton}.first {$0.title=="Conectado"}
    check(connected?.bezelColor == NSColor.systemGreen,"connected action is green")
    check(!view.subviews.compactMap {$0 as? NSTextField}.contains {$0.stringValue=="Sem métrica"},"connection status uses button only")
    let claude=AccessSetup.instruction(for:"claude")
    check(claude.1.contains("/Contents/Resources/Integration/configure-claude.py"),"Claude command uses bundled absolute path")
    check(AccessSetup.helperCommand("scripts/configure-claude.py").isEmpty,"relative helper path is rejected")
    check(AccessSetup.helperCommand("/fixture/Paulo's App/helper.py").contains("'\\''"),"apostrophes are shell quoted")
    let path="/fixture/Paulo's App/$title.py"
    let command=AccessSetup.helperCommand(path)
    let argument=String(command.dropFirst("python3 ".count).dropLast(" --apply".count))
    let shell=Process(),output=Pipe();shell.executableURL=URL(fileURLWithPath:"/bin/sh");shell.arguments=["-c","printf '%s' "+argument];shell.standardOutput=output
    try! shell.run();shell.waitUntilExit()
    check(shell.terminationStatus==0 && String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)==path,"copied helper path survives shell parsing literally")
    check(AccessSetup.guideURLResponse(command:"",url:"https://example.invalid")==NSApplication.ModalResponse.alertSecondButtonReturn,"guide button works without a bundled helper")
    check(AccessSetup.guideURLResponse(command:"fixture",url:"https://example.invalid")==NSApplication.ModalResponse.alertThirdButtonReturn,"guide button follows copy command")
    check(AccessSetup.guideURLResponse(command:"fixture",url:"")==nil,"no guide action without URL")
    print("PASS access/visibility: \(count) checks; no credentials, clipboard or login")
}
