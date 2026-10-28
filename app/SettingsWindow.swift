import AppKit
import SwiftUI
import ServiceManagement

struct InterfacePreferences: Codable, Equatable {
    var appearance="system"
    var scale:Double=1
    var dismissal:Double=15
    var pinned=false
    func normalized()->Self {
        var value=self
        if !["system","light","dark"].contains(value.appearance) {value.appearance="system"}
        if ![1,1.25,1.5].contains(value.scale) {value.scale=1}
        if ![15,30,60].contains(value.dismissal) {value.dismissal=15}
        return value
    }
}
final class SettingsModel: ObservableObject {
    @Published var selected="general"
    @Published var advancedExpanded=false
    @Published var insight=InsightPreferences()
    @Published var insightApplied=InsightPreferences()
    @Published var insightMessage=""
    @Published var insightPath=""
    @Published var insightBusy=false
    @Published var insightPro=false
    @Published var insightProviders:[String]=[]
    @Published var insightModels:[String]=[]
    var displayedInsightMessage:String {insight != insightApplied ? "Alterações pendentes. Use Aplicar opções ou Buscar modelos para usar esta seleção." : insightMessage}
    var displayedInsightPath:String {insight.sameCatalog(as:insightApplied) ? (insightPath.isEmpty ? "Executável não encontrado" : insightPath) : "Caminho será verificado ao aplicar opções"}
    var onInsightModels:()->Void={}
    var onInsightChange:(InsightPreferences)->Void={_ in}
    var onInsightCheck:()->Void={}
    func chooseInsightProvider(_ provider:String) {
        guard provider != insight.provider else{return}
        insight.provider=provider;insight.model="";insightModels=[]
        if !InsightHarness.compatible(with:provider).contains(insight.harness),let preferred=InsightHarness.preferred(for:provider) {insight.harness=preferred;insight.executablePath=""}
        insightMessage="Aplique as opções e busque os modelos do cliente escolhido."
    }
    func chooseInsightHarness(_ harness:InsightHarness) {
        guard harness != insight.harness,InsightHarness.compatible(with:insight.provider).contains(harness) else{return}
        insight.harness=harness;insight.model="";insight.executablePath="";insightModels=[]
        insightMessage="Aplique as opções e busque os modelos do cliente escolhido."
    }
    func configureInsight(_ value:InsightPreferences) {let previous=updating;updating=true;insight=value;updating=previous}
    @Published var licenseMessage="Free: até dois planos."
    @Published var licensePrice:String?
    @Published var licenseBusy=false
    var onPurchase:()->Void={}
    var onRestore:()->Void={}
    #if PLANMETER_DEVELOPMENT
    @Published var simulationPro=false {didSet{onSimulation(simulationPro)}}
    var onSimulation:(Bool)->Void={_ in}
    #endif
    @Published var operations=OperationsSettings() {didSet{if !updating {onOperationsChange(operations.normalized())}}}
    @Published var logError=""
    var logsPath=""
    var onOperationsChange:(OperationsSettings)->Void={_ in}
    var onViewLog:(AuditCategory)->Void={_ in}
    var onLogDirectory:()->Void={}
    var onLoginAudit:(AuditOutcome)->Void={_ in}
    func configureOperations(_ value:OperationsSettings,path:String,error:String?) {
        let previous=updating;updating=true;operations=value;logsPath=path;logError=error ?? "";updating=previous
    }
    @Published var accessRevision=0
    @Published var interface=InterfacePreferences() {didSet{commit()}}
    @Published var confetti=true {didSet{commit()}}
    @Published var respectMotion=true {didSet{commit()}}
    @Published var loginEnabled=false
    @Published var loginPending=false
    @Published var legacyLogin=false
    @Published var loginMessage=""
    var updating=false
    var onChange:(InterfacePreferences,Bool,Bool)->Void={_,_,_ in}
    var access=AccessSetup()
    var isTest:Bool {CommandLine.arguments.contains{$0.hasSuffix("-self-test")}}
    func commit() {if !updating {onChange(interface.normalized(),confetti,respectMotion)}}
    func configure(interface:InterfacePreferences,confetti:Bool,respect:Bool) {
        updating=true;self.interface=interface.normalized();self.confetti=confetti;respectMotion=respect
        refreshLogin()
        updating=false
    }
    func syncInterface(_ value:InterfacePreferences) {
        let previous=updating;updating=true;interface=value.normalized();updating=previous
    }
    func refreshLogin() {
        guard !isTest else{return}
        legacyLogin=FileManager.default.fileExists(atPath:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/io.github.pcarielo.planmeter.plist").path)
        let status=SMAppService.mainApp.status
        loginEnabled=status == .enabled;loginPending=status == .requiresApproval
        loginMessage=loginPending ? "Aguardando aprovação em Itens de Início. Desmarque para cancelar o registro." : ""
    }
    static func installedLocation(_ path:String,home:String)->Bool {
        path.hasSuffix(".app") && (path.hasPrefix("/Applications/") || path.hasPrefix(home+"/Applications/"))
    }
    func setLogin(_ enabled:Bool) {
        guard !isTest else{return}
        if enabled && legacyLogin {loginMessage="Desative primeiro o início configurado pelo instalador anterior.";return}
        if enabled && !Self.installedLocation(Bundle.main.bundleURL.resolvingSymlinksInPath().path,home:FileManager.default.homeDirectoryForCurrentUser.path) {
            loginMessage="Instale o aplicativo em Aplicativos antes de ativar o início automático.";return
        }
        do {
            if enabled {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
            refreshLogin();onLoginAudit(.success)
            if !loginPending {loginMessage="Preferência atualizada."}
        } catch {onLoginAudit(.failure);refreshLogin();loginMessage="Não foi possível alterar. Confira Itens de Início do macOS."}
    }
}
private struct AccessSettingsView: NSViewRepresentable {
    let access:AccessSetup
    func makeNSView(context:Context)->NSView {access.makeContentView()}
    func updateNSView(_ nsView:NSView,context:Context) {}
}
private struct SettingsRootView: View {
    @ObservedObject var model:SettingsModel
    var body:some View {
        TabView(selection:$model.selected) {
            Form {
                Section("Inicialização") {
                    Toggle("Abrir ao iniciar a sessão",isOn:Binding(get:{model.loginEnabled || model.loginPending},set:{model.setLogin($0)})).disabled(model.legacyLogin && !model.loginEnabled && !model.loginPending)
                    if model.legacyLogin {Text("Há um início automático configurado pelo instalador anterior. Desative essa configuração pelo script login-item.sh antes de ativar a opção nativa.").font(.system(size:13))}
                    Text("Desativado por padrão. O macOS pode pedir aprovação para esta instalação.").font(.system(size:13)).foregroundColor(.secondary)
                    if !model.loginMessage.isEmpty {Text(model.loginMessage).font(.system(size:13))}
                    Button("Abrir Itens de Início do macOS") {if !model.isTest {SMAppService.openSystemSettingsLoginItems()}}
                }
                Section("Licença") {
                    Text(model.licenseMessage)
                    HStack {
                        Button(model.licensePrice.map{"Obter Pro · " + $0} ?? "Obter Pro"){model.onPurchase()}.disabled(model.licenseBusy || model.licensePrice == nil)
                        Button("Restaurar compras"){model.onRestore()}.disabled(model.licenseBusy)
                    }
                    #if PLANMETER_DEVELOPMENT
                    Toggle("Simular Pro (desenvolvimento, sem compra)",isOn:$model.simulationPro)
                    #endif
                }
                Section("Atualizações de quota") {
                    Picker("Intervalo automático",selection:$model.operations.refreshSeconds) {
                        Text("Automático por provedor").tag(0.0)
                        Text("1 minuto").tag(60.0);Text("5 minutos").tag(300.0);Text("15 minutos").tag(900.0);Text("30 minutos").tag(1800.0);Text("1 hora").tag(3600.0)
                    }
                    Text("Atualizar consulta as fontes disponíveis e respeita os intervalos dos provedores. No modo automático, Codex e Claude passivo usam 1 minuto; os demais coletores usam 15 minutos.")
                    Text("Provedores sem métricas ficam ocultos. Saldo zero permanece visível.").foregroundColor(.secondary)
                    if !model.logError.isEmpty {Text(model.logError).foregroundColor(.red)}
                    DisclosureGroup("Avançado: registros locais",isExpanded:$model.advancedExpanded) {
                        HStack {Toggle("Registrar cada consulta",isOn:$model.operations.queries);Button("Visualizar"){model.onViewLog(.queries)}}
                        HStack {Toggle("Registrar mudanças de configuração",isOn:$model.operations.configuration);Button("Visualizar"){model.onViewLog(.configuration)}}
                        HStack {Toggle("Registrar operações de acesso e chaves",isOn:$model.operations.access);Button("Visualizar"){model.onViewLog(.access)}}
                        Text(model.logsPath).font(.system(size:12)).textSelection(.enabled)
                        Button("Abrir pasta de logs e arquivos anteriores"){model.onLogDirectory()}
                        Toggle("Rotacionar por tamanho",isOn:$model.operations.rotateBySize)
                        Stepper("Tamanho por arquivo: \(model.operations.rotationMB) MB",value:$model.operations.rotationMB,in:1...100).disabled(!model.operations.rotateBySize)
                        Picker("Rotacionar por período",selection:$model.operations.rotationDays) {Text("Desativado").tag(0);Text("Diariamente").tag(1);Text("Semanalmente").tag(7);Text("Mensalmente (30 dias)").tag(30)}
                        Stepper("Retenção: \(model.operations.retentionDays) dias, mínimo de 3 meses",value:$model.operations.retentionDays,in:90...3650,step:30)
                        Text("Padrão: 90 dias ou 3 meses completos, o que for maior. A rotação separa arquivos, sem apagar registros dentro da retenção. Chaves, tokens e respostas brutas nunca entram nos logs.").font(.system(size:13)).foregroundColor(.secondary)
                    }
                }
            }.formStyle(.grouped).tabItem{Label("Geral",systemImage:"gearshape")}.tag("general")
            AccessSettingsView(access:model.access).id(model.accessRevision).frame(width:620,height:560)
                .tabItem{Label("Contas",systemImage:"person.crop.circle")}.tag("accounts")
            Form {
                Section("Insights do Pro") {
                    Text("Uma ou duas linhas sobre o ritmo de consumo, com observações de até sete dias. Gerar insight usa o modelo escolhido e pode consumir a quota do plano.")
                    if !model.insightPro {Text("Disponível no Pro. Veja Geral → Licença.").foregroundColor(.secondary)}
                    Picker("Provedor do modelo",selection:Binding(get:{model.insight.provider},set:{model.chooseInsightProvider($0)})) {
                        Text("Escolher…").tag("")
                        ForEach(model.insightProviders,id:\.self) {key in Text(key == "claude" ? "Claude Code" : key == "kimi" ? "Kimi Code" : key.capitalized).tag(key)}
                    }
                    if !model.insightModels.isEmpty && model.insight.sameCatalog(as:model.insightApplied) {
                        Picker("Modelos encontrados",selection:$model.insight.model) {
                            Text("Escolher…").tag("")
                            if !model.insight.model.isEmpty && !model.insightModels.contains(model.insight.model) {Text(model.insight.model+" (manual)").tag(model.insight.model)}
                            ForEach(model.insightModels,id:\.self){name in Text(name).tag(name)}
                        }
                    }
                    TextField("Modelo",text:$model.insight.model)
                    Button("Buscar modelos no harness"){model.onInsightModels()}.disabled(model.insightBusy)
                    Picker("Harness",selection:Binding(get:{model.insight.harness},set:{model.chooseInsightHarness($0)})) {ForEach(InsightHarness.allCases,id:\.self) {harness in
                        let compatible=InsightHarness.compatible(with:model.insight.provider).contains(harness)
                        Text(compatible ? harness.title : harness.title+" · para "+harness.compatibleProviderNames).tag(harness).disabled(!compatible)
                    }}
                    TextField("Caminho alternativo (opcional)",text:$model.insight.executablePath)
                    Text(model.displayedInsightPath).font(.system(size:12)).textSelection(.enabled)
                    Button("Aplicar opções"){model.onInsightChange(model.insight)}
                    Button("Verificar conexão"){model.onInsightCheck()}.disabled(model.insightBusy || !model.insightPro)
                    Text(model.displayedInsightMessage).foregroundColor(.secondary)
                    Text("O provedor que gera o insight é independente dos planos monitorados. A lista de modelos é filtrada por esse provedor; clientes incompatíveis nesta integração ficam visíveis, mas desabilitados.").font(.system(size:13)).foregroundColor(.secondary)
                    Text("Confirme a conta no cliente escolhido; ela pode ser diferente da conta monitorada. O provedor recebe sinais analíticos calculados sobre os planos ativos. Não são enviados chaves, transcrições ou arquivos dos seus projetos. A resposta é uma estimativa, não uma garantia.").font(.system(size:13)).foregroundColor(.secondary)
                }.disabled(!model.insightPro)
            }.formStyle(.grouped).tabItem{Label("Insights",systemImage:"sparkles")}.tag("insights")
            Form {
                Section("Aparência") {
                    Picker("Tema",selection:$model.interface.appearance) {Text("Sistema").tag("system");Text("Claro").tag("light");Text("Escuro").tag("dark")}
                    Picker("Tamanho do painel",selection:$model.interface.scale) {Text("1×").tag(1.0);Text("1,25×").tag(1.25);Text("1,5×").tag(1.5)}
                }
                Section("Painel") {
                    Toggle("Manter o painel fixado",isOn:$model.interface.pinned)
                    Picker("Fechar quando não estiver fixado",selection:$model.interface.dismissal) {Text("15 segundos").tag(15.0);Text("30 segundos").tag(30.0);Text("60 segundos").tag(60.0)}
                    Text("Fixado, o painel pode ser arrastado pela faixa superior. Fechar o painel desativa a fixação. Tema, tamanho e prazo de fechamento são preservados ao reiniciar.").font(.system(size:13)).foregroundColor(.secondary)
                }
            }.formStyle(.grouped).tabItem{Label("Aparência",systemImage:"paintbrush")}.tag("appearance")
            Form {
                Section("Renovação de quota") {
                    Toggle("Animar o confete dos avisos de reset",isOn:$model.confetti)
                    Toggle("Respeitar Reduzir Movimento do macOS",isOn:$model.respectMotion)
                    Text("O aplicativo apenas observa renovações. Não executa resets nem consome modelos para testar limites.").font(.system(size:13)).foregroundColor(.secondary)
                }
            }.formStyle(.grouped).tabItem{Label("Avisos",systemImage:"bell")}.tag("notifications")
            VStack(spacing:16) {
                Image(systemName:"gauge").font(.system(size:48)).foregroundColor(.accentColor)
                Text("PlanMeter").font(.largeTitle.bold())
                Text("Desenvolvido por Paulo Carielo").font(.system(size:16))
                Text("Versão " + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "local"))
                Text("Quotas e histórico locais. Chaves no Keychain. Insights opcionais enviam sinais analíticos ao modelo escolhido.").multilineTextAlignment(.center).foregroundColor(.secondary)
                Link("Privacidade e segurança",destination:URL(string:"https://github.com/pcarielo/planmeter/blob/main/docs/security.md")!)
                Link("Suporte e código-fonte",destination:URL(string:"https://github.com/pcarielo/planmeter")!)
            }.padding(44).tabItem{Label("Sobre",systemImage:"info.circle")}.tag("about")
        }.font(.system(size:15)).padding(12).frame(width:660,height:610)
    }
}
final class SettingsWindow: NSObject, NSWindowDelegate {
    let model=SettingsModel()
    private(set) var window:NSWindow?
    private var keyObserver:NSObjectProtocol?
    func show(page:String="general") {
        model.selected=page
        if window==nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:610),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.title="Configurações do PlanMeter";window.delegate=self;window.level = .floating;window.isReleasedWhenClosed=false
            window.contentViewController=NSHostingController(rootView:SettingsRootView(model:model));window.center();self.window=window
            keyObserver=NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main){[weak self] _ in self?.model.refreshLogin()}
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification:Notification) {if let window=window {refreshUtilityActivation(excluding:window)}}
    deinit {if let observer=keyObserver {NotificationCenter.default.removeObserver(observer)}}
}
func runSettingsTests() {
    var count=0
    func check(_ value:Bool,_ text:String){guard value else{fputs("FAIL settings: \(text)\n",stderr);exit(1)};count += 1}
    check(CelebrationPreferences().respectReduceMotion,"new installations respect reduce motion")
    var value=InterfacePreferences();value.scale=1.5;value.dismissal=30;value.pinned=true;value.appearance="dark"
    let restored=try! JSONDecoder().decode(InterfacePreferences.self,from:JSONEncoder().encode(value))
    check(restored==value,"preferences round trip")
    value.scale=99;value.appearance="unknown";check(value.normalized().scale==1 && value.normalized().appearance=="system","invalid values normalized")
    let model=SettingsModel();var changes=0
    model.onChange={_,_,_ in changes += 1};model.configure(interface:restored,confetti:false,respect:true)
    check(changes==0,"loading does not write preferences")
    var operationsChanges=0
    model.onOperationsChange={_ in operationsChanges += 1}
    model.configureOperations(OperationsSettings(),path:"/fixture/Logs",error:nil)
    check(operationsChanges==0,"loading operations does not save")
    model.operations.refreshSeconds=300
    check(operationsChanges==1,"interval changes propagate")
    var selectedLog:AuditCategory?
    model.onViewLog={selectedLog=$0};model.onViewLog(.access)
    check(selectedLog == .access,"category viewer action is independent")

    model.interface.scale=1.25;check(changes==1,"user change propagates")
    let before=changes;model.syncInterface(restored);check(changes==before && model.interface.scale==1.5,"panel changes resync without writes")
    var latestScale=0.0;model.onChange={value,_,_ in latestScale=value.scale};model.confetti.toggle()
    check(latestScale==1.5,"other setting preserves latest panel scale")
    model.setLogin(true);check(!model.loginEnabled,"tests never register login item")
    check(SettingsModel.installedLocation("/Applications/PlanMeter.app",home:"/fixture"),"installed app eligible for login item")
    check(!SettingsModel.installedLocation("/tmp/PlanMeter.app",home:"/fixture"),"temporary build cannot register login item")
    let settings=SettingsWindow();settings.show(page:"about")
    check(NSApp.activationPolicy() == .regular,"settings participate in app switching")
    settings.window?.close()
    check(NSApp.activationPolicy() == .accessory,"closing settings restores menu bar mode")
    if ProcessInfo.processInfo.environment["PLANMETER_CAPTURE_FIXTURES"]=="1" {
        settings.model.insightPro=true
        settings.model.insightProviders=["codex","claude","kimi"]
        settings.model.insightModels=["fixture-model"]
        settings.model.insight.provider="kimi";settings.model.insight.harness = .pi;settings.model.insight.model="fixture-model"
        settings.model.insightPath="/Applications/Example/bin/pi"
        settings.model.insightMessage="Conexão verificada pelo harness."
        settings.show(page:"insights")
        RunLoop.current.run(until:Date().addingTimeInterval(0.3))
        captureFixturePreview(settings.window!.contentView!,name:"insight-settings")
        settings.show(page:"general");settings.model.advancedExpanded=true
        RunLoop.current.run(until:Date().addingTimeInterval(0.3))
        captureFixturePreview(settings.window!.contentView!,name:"general-advanced")
        settings.window?.close()
    }
    var savedInsight=InsightPreferences();savedInsight.provider="kimi";savedInsight.harness = .pi;savedInsight.model="fixture-model"
    model.configureInsight(savedInsight)
    check(model.insight.harness == .pi && model.insight.model=="fixture-model","loading preserves an explicitly chosen alternate harness")
    model.chooseInsightProvider("claude")
    check(model.insight.harness == .claude && model.insight.model.isEmpty,"user provider change selects native harness and clears incompatible model")
    var piDraft=InsightPreferences();piDraft.provider="codex";piDraft.harness = .pi;piDraft.executablePath="/fixture/custom/pi"
    model.configureInsight(piDraft);model.insightApplied=piDraft
    model.chooseInsightProvider("kimi")
    check(model.insight.harness == .pi && model.insight.executablePath=="/fixture/custom/pi","switching to Kimi preserves explicitly selected compatible pi")
    check(model.displayedInsightMessage.contains("pendentes"),"unapplied model selection is explicit")
    model.chooseInsightProvider("codex");model.chooseInsightHarness(.kimi)
    check(model.insight.harness == .pi,"incompatible native Kimi cannot silently use Codex billing")
    var changedModel=piDraft;changedModel.model="another-model"
    check(changedModel.sameCatalog(as:piDraft),"choosing a model preserves the catalog")
    changedModel.executablePath="/different/pi"
    check(!changedModel.sameCatalog(as:piDraft),"alternate executable invalidates old catalog")
    print("PASS Settings: \(count) checks; no login-item changes")
}
