import AppKit

struct ProviderAccess {
    let key:String, name:String, status:String, detail:String, actionTitle:String
    var enabled=true
}
final class AccessSetup: NSObject {
    private(set) var panel:NSPanel?
    var providers:[ProviderAccess]=[]
    var onConfigure:(String)->Void = {_ in}
    func show() {
        panel?.close()
        let width:CGFloat=620,height:CGFloat=560
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title="PlanMeter · Acessos";panel.isReleasedWhenClosed=false;panel.level = .floating;panel.sharingType = .readOnly
        let view=NSView(frame:NSRect(x:0,y:0,width:width,height:height))
        func label(_ text:String,_ frame:NSRect,_ size:CGFloat,_ bold:Bool=false)->NSTextField {
            let label=NSTextField(wrappingLabelWithString:text);label.frame=frame;label.font = .systemFont(ofSize:size,weight:bold ? .semibold : .regular);view.addSubview(label);return label
        }
        _=label("Conecte os serviços que você usa",NSRect(x:22,y:height-48,width:width-44,height:26),19,true)
        _=label("Sem métrica, o provedor fica oculto na barra e no painel.",NSRect(x:22,y:height-73,width:width-44,height:20),12)
        for (index,provider) in providers.enumerated() {
            let y=height-163-CGFloat(index)*87
            _=label(provider.name,NSRect(x:22,y:y+49,width:180,height:23),14,true)
            let status=label(provider.status,NSRect(x:210,y:y+51,width:width-236,height:20),11);status.textColor = .secondaryLabelColor
            _=label(provider.detail,NSRect(x:22,y:y+4,width:width-188,height:43),11)
            let action=NSButton(title:provider.actionTitle,target:self,action:#selector(configure(_:)));action.tag=index;action.isEnabled=provider.enabled;action.bezelStyle = .rounded;action.frame=NSRect(x:width-152,y:y+9,width:128,height:30);view.addSubview(action)
        }
        panel.contentView=view;panel.center();self.panel=panel;NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)
    }
    @objc func configure(_ sender:NSButton) {
        guard providers.indices.contains(sender.tag),providers[sender.tag].enabled else{return}
        panel?.orderOut(nil);onConfigure(providers[sender.tag].key)
    }
    static func instruction(for key:String)->(String,String,String) {
        switch key {
        case "codex": return("Instale o Codex CLI oficial e execute este comando no Terminal. Conclua o login com sua conta ChatGPT e depois atualize o PlanMeter.","codex login","https://developers.openai.com/codex/cli/")
        case "claude": return("Na pasta do projeto PlanMeter, execute o configurador da statusline. Ele faz backup e preserva a configuração existente. A quota se renova com o uso normal do Claude Code.","python3 scripts/configure-claude.py --apply","https://github.com/pcarielo/planmeter/blob/main/docs/getting-started.md#claude-code")
        case "grok": return("Instale o Grok Build oficial e execute este comando no Terminal. Conclua o login da assinatura e depois atualize o PlanMeter. Não use uma chave da API para substituir a assinatura.","grok login","https://docs.x.ai/build/overview")
        default: return("A conexão deste provedor é gerenciada no serviço remoto. Ajuste a autenticação pelo fluxo seguro usado naquele host.","","")
        }
    }
    static func guide(_ key:String) {
        let (detail,command,url)=instruction(for:key)
        let alert=NSAlert();alert.messageText="Conectar " + key.capitalized
        alert.informativeText=detail + (command.isEmpty ? "" : "\n\n"+command)
        alert.addButton(withTitle:"Fechar")
        if !command.isEmpty {alert.addButton(withTitle:"Copiar comando")}
        if !url.isEmpty {alert.addButton(withTitle:"Abrir guia oficial")}
        let answer=alert.runModal()
        if answer == .alertSecondButtonReturn && !command.isEmpty {NSPasteboard.general.clearContents();NSPasteboard.general.setString(command,forType:.string)}
        if answer.rawValue==1002,let link=URL(string:url),!url.isEmpty {NSWorkspace.shared.open(link)}
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
    print("PASS access/visibility: \(count) checks; no credentials, clipboard or login")
}
