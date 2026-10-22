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
            refreshLogin()
            if !loginPending {loginMessage="Preferência atualizada."}
        } catch {refreshLogin();loginMessage="Não foi possível alterar. Confira Itens de Início do macOS."}
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
                    if model.legacyLogin {Text("Há um início automático configurado pelo instalador anterior. Desative essa configuração pelo script login-item.sh antes de ativar a opção nativa.").font(.caption)}
                    Text("Desativado por padrão. O macOS pode pedir aprovação para esta instalação.").font(.caption).foregroundColor(.secondary)
                    if !model.loginMessage.isEmpty {Text(model.loginMessage).font(.caption)}
                    Button("Abrir Itens de Início do macOS") {if !model.isTest {SMAppService.openSystemSettingsLoginItems()}}
                }
                Section("Atualizações de quota") {
                    Text("Atualizar consulta as fontes disponíveis e respeita os intervalos dos provedores. O cache Claude se renova com o uso do cliente ou do coletor configurado.")
                    Text("Provedores sem métricas ficam ocultos. Saldo zero permanece visível.").foregroundColor(.secondary)
                }
            }.formStyle(.grouped).tabItem{Label("Geral",systemImage:"gearshape")}.tag("general")
            AccessSettingsView(access:model.access).id(model.accessRevision).frame(width:620,height:560)
                .tabItem{Label("Contas",systemImage:"person.crop.circle")}.tag("accounts")
            Form {
                Section("Aparência") {
                    Picker("Tema",selection:$model.interface.appearance) {Text("Sistema").tag("system");Text("Claro").tag("light");Text("Escuro").tag("dark")}
                    Picker("Tamanho do painel",selection:$model.interface.scale) {Text("1×").tag(1.0);Text("1,25×").tag(1.25);Text("1,5×").tag(1.5)}
                }
                Section("Painel") {
                    Toggle("Manter o painel fixado",isOn:$model.interface.pinned)
                    Picker("Fechar quando não estiver fixado",selection:$model.interface.dismissal) {Text("15 segundos").tag(15.0);Text("30 segundos").tag(30.0);Text("60 segundos").tag(60.0)}
                    Text("Fixado, o painel pode ser arrastado pela faixa superior. As preferências são preservadas ao reiniciar o aplicativo.").font(.caption).foregroundColor(.secondary)
                }
            }.formStyle(.grouped).tabItem{Label("Aparência",systemImage:"paintbrush")}.tag("appearance")
            Form {
                Section("Renovação de quota") {
                    Toggle("Animar o confete dos avisos de reset",isOn:$model.confetti)
                    Toggle("Respeitar Reduzir Movimento do macOS",isOn:$model.respectMotion)
                    Text("O aplicativo apenas observa renovações. Não executa resets nem consome modelos para testar limites.").font(.caption).foregroundColor(.secondary)
                }
            }.formStyle(.grouped).tabItem{Label("Avisos",systemImage:"bell")}.tag("notifications")
            VStack(spacing:16) {
                Image(systemName:"gauge").font(.system(size:48)).foregroundColor(.accentColor)
                Text("PlanMeter").font(.largeTitle.bold())
                Text("Versão " + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "local"))
                Text("Monitor local de quotas. Chaves no Keychain, leituras sem prompts de modelo e dados de quota mantidos neste Mac.").multilineTextAlignment(.center).foregroundColor(.secondary)
                Link("Privacidade e segurança",destination:URL(string:"https://github.com/pcarielo/planmeter/blob/main/docs/security.md")!)
                Link("Suporte e código-fonte",destination:URL(string:"https://github.com/pcarielo/planmeter")!)
            }.padding(44).tabItem{Label("Sobre",systemImage:"info.circle")}.tag("about")
        }.padding(12).frame(width:660,height:610)
    }
}
final class SettingsWindow {
    let model=SettingsModel()
    private(set) var window:NSWindow?
    private var keyObserver:NSObjectProtocol?
    func show(page:String="general") {
        model.selected=page
        if window==nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:610),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.title="Configurações do PlanMeter";window.isReleasedWhenClosed=false
            window.contentViewController=NSHostingController(rootView:SettingsRootView(model:model));window.center();self.window=window
            keyObserver=NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main){[weak self] _ in self?.model.refreshLogin()}
        }
        NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    deinit {if let observer=keyObserver {NotificationCenter.default.removeObserver(observer)}}
}
func runSettingsTests() {
    var count=0
    func check(_ value:Bool,_ text:String){guard value else{fputs("FAIL settings: \(text)\n",stderr);exit(1)};count += 1}
    var value=InterfacePreferences();value.scale=1.5;value.dismissal=30;value.pinned=true;value.appearance="dark"
    let restored=try! JSONDecoder().decode(InterfacePreferences.self,from:JSONEncoder().encode(value))
    check(restored==value,"preferences round trip")
    value.scale=99;value.appearance="unknown";check(value.normalized().scale==1 && value.normalized().appearance=="system","invalid values normalized")
    let model=SettingsModel();var changes=0
    model.onChange={_,_,_ in changes += 1};model.configure(interface:restored,confetti:false,respect:true)
    check(changes==0,"loading does not write preferences")
    model.interface.scale=1.25;check(changes==1,"user change propagates")
    let before=changes;model.syncInterface(restored);check(changes==before && model.interface.scale==1.5,"panel changes resync without writes")
    var latestScale=0.0;model.onChange={value,_,_ in latestScale=value.scale};model.confetti.toggle()
    check(latestScale==1.5,"other setting preserves latest panel scale")
    model.setLogin(true);check(!model.loginEnabled,"tests never register login item")
    check(SettingsModel.installedLocation("/Applications/PlanMeter.app",home:"/fixture"),"installed app eligible for login item")
    check(!SettingsModel.installedLocation("/tmp/PlanMeter.app",home:"/fixture"),"temporary build cannot register login item")
    print("PASS Settings: \(count) checks; no login-item changes")
}
