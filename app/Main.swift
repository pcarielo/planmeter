import AppKit
import Foundation

final class MenuApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    let claudeQuota=ClaudeQuotaMonitor()
    let insights=InsightController()
    let licenseStore=LicenseStore()
    #if PLANMETER_DEVELOPMENT
    var simulatedPro:Bool?
    #endif
    func syncLicense() {
        var pro=licenseStore.isPro
        var message=licenseStore.message
        #if PLANMETER_DEVELOPMENT
        if let simulation=simulatedPro {pro=simulation;message=simulation ? "Simulação Pro: todos os planos e insights. Sem compra." : "Simulação Free: até dois planos. Sem compra."}
        #endif
        planAccess.isPro=pro;settingsWindow.model.licenseMessage=message
        settingsWindow.model.licensePrice=licenseStore.price;settingsWindow.model.licenseBusy=licenseStore.busy
        applyPlanAccess()
    }
    var planAccess=PlanAccess(selected:Runtime.isTest ? PlanAccess.providers : [],isPro:Runtime.isTest)
    func allowed(_ provider:String)->Bool {planAccess.active.contains(provider)}
    func visible(_ value:QuotaSnapshot?,_ provider:String)->QuotaSnapshot? {allowed(provider) ? value : nil}
    func applyPlanAccess() {
        if !planAccess.insightsAllowed || !allowed(insights.preferences.provider) {insights.cancel()}
        syncInsightSettings()
        if !allowed("codex") {timer?.invalidate();client?.cancel()}
        if !allowed("claude") {claudeTimer?.invalidate();claudeQuota.stop()}
        zaiEnabled=allowed("zai")
        if !zaiEnabled {zaiTimer?.invalidate();zaiClient?.cancel();zaiManualPending=false}
        kimi.enabled=allowed("kimi");grok.enabled=allowed("grok")
        if !kimi.enabled {kimi.stop()} else if !activity.suspended {kimi.start()}
        if !grok.enabled {grok.stop()} else if !activity.suspended {grok.start()}
        if allowed("codex"),!policy.busy {if policy.lastAttempt==nil {refresh()} else {schedule()}}
        startClaudeTimer();startZaiTimer();updateUI()
        prepareAccessSettings();settingsWindow.model.accessRevision += 1
    }
    func selectPlan(_ key:String,_ selected:Bool) {
        var proposed=planAccess
        guard proposed.setEnabled(key,selected),let data=try? JSONEncoder().encode(PlanSelection(providers:proposed.selected)),writePrivate(data,to:cacheDirectory.appendingPathComponent("plan-selection.json")) else{return}
        planAccess=proposed;audit(.configuration,.app,.settingsChanged,.success);applyPlanAccess()
    }
    let kimi = KimiMonitor()
    let grok = GrokMonitor()
    let dashboard = QuotaDashboard()
    let accessSetup = AccessSetup()
    let settingsWindow=SettingsWindow()
    let renewalWindow=RenewalHistoryWindow()
    var renewalHistory=RenewalHistory()
    var selectionMissing=false
    var usageTimeline=UsageTimeline()
    var timelineWriteBlocked=false
    var timelineDirty=false
    var timelineRevision=0
    var timelineRetryAfter=Date.distantPast
    lazy var usagePersistence=UsagePersistence(file:cacheDirectory.appendingPathComponent("usage-timeline.json"))
    func loadUsageTimeline() {
        let file=cacheDirectory.appendingPathComponent("usage-timeline.json")
        if FileManager.default.fileExists(atPath:file.path) {
            do {usageTimeline=try JSONDecoder().decode(UsageTimeline.self,from:Data(contentsOf:file))}
            catch {timelineWriteBlocked=true;return}
        }
        if usageTimeline.restoreRecordedObservations(["codex":detector.state,"claude":claudeDetector.state]) {
            timelineRevision += 1;timelineDirty=true
        }
    }

    func captureUsageTimeline() {
        var changed=false
        for value in [snapshot,claudeSnapshot,zaiSnapshot,kimi.snapshot,grok.snapshot].compactMap({$0}) {
            changed=usageTimeline.ingest(value,connectionID:value.credentialScope) || changed
        }
        if changed {timelineRevision += 1;timelineDirty=true}
        guard !timelineWriteBlocked,timelineDirty,(changed || Date()>=timelineRetryAfter) else{return}
        timelineRetryAfter=Date().addingTimeInterval(60)
        let revision=timelineRevision
        usagePersistence.submit(usageTimeline){[weak self] success in
            DispatchQueue.main.async {guard let self=self,self.timelineRevision==revision else{return};self.timelineDirty = !success}
        }
    }
    private var importedRenewalDetections=Set<String>()
    private var renewalHistoryDirty=false
    private var renewalHistoryWriteBlocked=false
    private var renewalRecoveryMessage:String?
    var interfacePreferences=InterfacePreferences()
    var operations=OperationsSettings()
    lazy var auditLog=AuditLog(directory:cacheDirectory.appendingPathComponent("Logs"))
    func audit(_ category:AuditCategory,_ provider:AuditProvider,_ action:AuditAction,_ outcome:AuditOutcome) {
        auditLog.record(category,provider:provider,action:action,outcome:outcome,settings:operations)
        settingsWindow.model.logError=auditLog.statusMessage ?? ""
    }
    func applyOperations(_ value:OperationsSettings) {
        let old=operations.refreshSeconds,oldZai=operations.interval(for:"zai")
        operations=value.normalized();policy.baseInterval=operations.interval(for:"codex")
        claudeQuota.setRefreshInterval(operations.interval(for:"claude"))
        kimi.setRefreshInterval(operations.interval(for:"kimi"));grok.setRefreshInterval(operations.interval(for:"grok"))
        zaiAutomaticAfter=max(zaiManualCooldown,zaiAutomaticAfter.addingTimeInterval(operations.interval(for:"zai")-oldZai))
        saveZaiSchedule()
        if old != operations.refreshSeconds {if !policy.busy {schedule()};startClaudeTimer()}
    }
    var menu = NSMenu()
    var snapshot: QuotaSnapshot?
    var zaiReading: ZaiReading?, zaiSnapshot: QuotaSnapshot?
    var zaiError: String? = "Configure a chave Z.ai no menu para consultar quotas"
    var zaiBusy = false, zaiReads = 0
    var zaiGeneration=0
    var zaiCooldown = Date.distantPast
    var zaiClient: ZaiClient?
    var zaiClientFactory: () -> ZaiClient = { ZaiClient() }
    var zaiTimer: Timer?
    var zaiManualRequests = 0, zaiManualPending = false, zaiRequestIsManual = false
    var zaiRefreshMessage: String?
    var zaiManualCooldown = Date.distantPast
    var zaiAutomaticAfter = Date.distantPast
    var zaiEnabled = !CommandLine.arguments.contains { $0.hasSuffix("-self-test") }
    var claudeSnapshot: QuotaSnapshot?
    var detector = ResetDetector(), claudeDetector = ResetDetector()
    let confetti = ConfettiPresenter()
    var countdownTimer: Timer?
    var preferences = CelebrationPreferences()
    var activity = CelebrationActivity()
    var demoPending = false, demoMotion = false
    var shownKey: String?
    var celebrationDisplay = true
    var celebrationRenderOffscreen = false
    var journalHealthy = true
    var policy = RefreshPolicy()
    var timer: Timer?, claudeTimer: Timer?, client: AppServerClient?
    var claudeCacheReads = 0
    var errorText: String?, claudeError: String?
    var attempts = 0, quotaRequests = 0
    var lastElapsed: Double?, wakePending = false
    var observers: [NSObjectProtocol] = [], distributedObservers: [NSObjectProtocol] = []
    var terminationSignal: DispatchSourceSignal?
    var binary = Runtime.codexPath()
    var cacheDirectory = Runtime.stateDirectory
    var cacheFile: URL { cacheDirectory.appendingPathComponent("snapshot.json") }
    var metricsFile: URL { cacheDirectory.appendingPathComponent("metrics.json") }
    var resetFile: URL { cacheDirectory.appendingPathComponent("reset-state.json") }
    var zaiCooldownFile: URL { cacheDirectory.appendingPathComponent("zai-cooldown.json") }
    var zaiFile: URL { cacheDirectory.appendingPathComponent("zai-quota.json") }
    var claudeResetFile: URL { cacheDirectory.appendingPathComponent("claude-reset-state.json") }
    var preferencesFile: URL { cacheDirectory.appendingPathComponent("preferences.json") }
    static let kimiConfigureRequest = Notification.Name("io.github.pcarielo.planmeter.configure-kimi")
    static let zaiRefreshRequest = Notification.Name("io.github.pcarielo.planmeter.refresh-zai")
    static let demoRequest = Notification.Name("io.github.pcarielo.planmeter.explicit-demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let otherMonitors=["io.github.pcarielo.planmeter","local.codex.balance"].flatMap {NSRunningApplication.runningApplications(withBundleIdentifier:$0)}.filter {$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}
        if let other=otherMonitors.first {
            NSApp.setActivationPolicy(.accessory)
            let alert=NSAlert();alert.messageText="Já existe um monitor aberto"
            alert.informativeText="A instalação em uso é " + (other.bundleURL?.path ?? other.localizedName ?? "outro PlanMeter") + ". Esta cópia será encerrada para evitar indicadores duplicados."
            alert.addButton(withTitle:"Usar o monitor aberto");alert.runModal()
            other.activate(options:.activateIgnoringOtherApps);NSApp.terminate(nil);return
        }
        NSApp.setActivationPolicy(.accessory)
        signal(SIGTERM, SIG_IGN)
        terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal?.setEventHandler { NSApp.terminate(nil) }; terminationSignal?.resume()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        status.button?.target = self; status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let data = try? Data(contentsOf: cacheFile) { snapshot = try? JSONDecoder().decode(QuotaSnapshot.self, from: data) }
        if let data = try? Data(contentsOf: resetFile), let state = try? JSONDecoder().decode(ResetState.self, from: data) { detector.state = state }
        if let data = try? Data(contentsOf: claudeResetFile), let state = try? JSONDecoder().decode(ResetState.self, from: data) { claudeDetector.state = state }
        loadRenewalHistory()
        if let data = try? Data(contentsOf: preferencesFile), let pref = try? JSONDecoder().decode(CelebrationPreferences.self, from: data) { preferences = pref }
        if let data = try? Data(contentsOf: zaiFile), let cached = try? JSONDecoder().decode(ZaiReading.self, from: data) { zaiReading = cached; zaiSnapshot = cached.snapshot; zaiError = "Cache Z.ai; aguardando leitura" }
        errorText = snapshot == nil ? nil : "Dados em cache; aguardando leitura"
        if let data=try? Data(contentsOf:cacheDirectory.appendingPathComponent("interface-preferences.json")),let value=try? JSONDecoder().decode(InterfacePreferences.self,from:data) {interfacePreferences=value.normalized()}
        if let data=try? Data(contentsOf:cacheDirectory.appendingPathComponent("operations.json")),let value=try? JSONDecoder().decode(OperationsSettings.self,from:data) {operations=value}
        policy.baseInterval=operations.interval(for:"codex")
        claudeQuota.directory=cacheDirectory;claudeQuota.interval=operations.interval(for:"claude");claudeQuota.load()
        claudeQuota.audit = {[weak self] action,outcome in self?.audit(.queries,.claude,action,outcome)}
        claudeQuota.onChange = {[weak self] in
            guard let self=self,self.claudeQuota.enabled else{return}
            self.claudeSnapshot=self.claudeQuota.snapshot;self.claudeError=self.claudeQuota.error
            if let value=self.claudeSnapshot,self.claudeError==nil {_=self.claudeDetector.accept(value);_=self.saveStates()}
            self.updateUI();self.writeMetrics()
        }
        selectionMissing = !FileManager.default.fileExists(atPath:cacheDirectory.appendingPathComponent("plan-selection.json").path)
        if let data=try? Data(contentsOf:cacheDirectory.appendingPathComponent("plan-selection.json")),let selection=try? JSONDecoder().decode(PlanSelection.self,from:data) {planAccess.selected=selection.providers.intersection(PlanAccess.providers)}
        zaiEnabled=allowed("zai");kimi.enabled=allowed("kimi");grok.enabled=allowed("grok")
        licenseStore.onChange = {[weak self] in
            guard let self=self else{return}
            self.syncLicense()
        }
        licenseStore.start()
        if let data=try? Data(contentsOf:cacheDirectory.appendingPathComponent("insight-preferences.json")),let preferences=try? JSONDecoder().decode(InsightPreferences.self,from:data) {configureInsight(preferences,save:false)}
        else {configureInsight(InsightPreferences(),save:false)}
        insights.onChange = {[weak self] in self?.syncInsightSettings();self?.updateDashboard()}
        loadUsageTimeline()
        applyInterfacePreferences()
        dashboard.onOptionsChanged = { [weak self] scale,pinned in
            guard let self=self else{return};self.interfacePreferences.scale=scale;self.interfacePreferences.pinned=pinned;self.saveInterfacePreferences();self.audit(.configuration,.app,.settingsChanged,.success);self.settingsWindow.model.syncInterface(self.interfacePreferences)
        }
        configureMainMenu()
        menu.delegate = self;menu.autoenablesItems=false
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.setDisplaySleeping(true) })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.setDisplaySleeping(false) })
        let dc = DistributedNotificationCenter.default()
        distributedObservers.append(dc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.setScreenLocked(true) })
        distributedObservers.append(dc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.setScreenLocked(false) })
        distributedObservers.append(dc.addObserver(forName: Self.demoRequest, object: "io.github.pcarielo.planmeter", queue: .main) { [weak self] n in self?.startDemo(motion: n.userInfo?["motion"] as? Bool ?? false) })
        distributedObservers.append(dc.addObserver(forName: Self.zaiRefreshRequest, object: "io.github.pcarielo.planmeter", queue: .main) { [weak self] _ in self?.refreshZaiNow() })
        distributedObservers.append(dc.addObserver(forName:Self.kimiConfigureRequest,object:"io.github.pcarielo.planmeter",queue:.main) { [weak self] _ in self?.kimi.configure() })
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] { activity.screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false; policy.sleeping = activity.suspended }
        if let reading = zaiReading { zaiManualCooldown = reading.nextAttemptAt.map { Date(timeIntervalSince1970:$0) } ?? .distantPast }
        if let data = try? Data(contentsOf:zaiCooldownFile), let schedule = try? JSONDecoder().decode(ZaiSchedule.self,from:data) {
            let now = Date().timeIntervalSince1970
            if schedule.manual.isFinite, schedule.manual > now, schedule.manual <= now + 86400 { zaiManualCooldown = max(zaiManualCooldown,Date(timeIntervalSince1970:schedule.manual)) }
            if schedule.automatic.isFinite, schedule.automatic > now, schedule.automatic <= now + 86400 { zaiAutomaticAfter = Date(timeIntervalSince1970:schedule.automatic) }
        }
        kimi.cacheDirectory = cacheDirectory
        kimi.onChange = { [weak self] in self?.updateUI(); self?.writeMetrics() }
        kimi.load();kimi.automaticInterval=operations.interval(for:"kimi")
        kimi.audit = {[weak self] action,outcome in self?.audit(action == .query ? .queries : .access,.kimi,action,outcome)}
        kimi.setPaused(activity.suspended)
        grok.cacheDirectory=cacheDirectory
        grok.onChange = { [weak self] in self?.updateUI();self?.writeMetrics() }
        grok.load();grok.automaticInterval=operations.interval(for:"grok")
        grok.audit = {[weak self] action,outcome in self?.audit(.queries,.grok,action,outcome)}
        grok.setPaused(activity.suspended)
        if selectionMissing {
            let caches:[String:QuotaSnapshot?]=["codex":snapshot,"claude":claudeQuota.snapshot ?? (try? ClaudeCacheProvider(path:cacheDirectory.appendingPathComponent("claude-statusline.json")).read()),"zai":zaiSnapshot,"kimi":kimi.historySnapshot,"grok":grok.snapshot]
            let known=Set(caches.compactMap{StatusPresentation.validRemaining($0.value) != nil ? $0.key : nil})
            planAccess.selected=PlanAccess.migratedSelection(known:known)
            if let data=try? JSONEncoder().encode(PlanSelection(providers:planAccess.selected)) {writePrivate(data,to:cacheDirectory.appendingPathComponent("plan-selection.json"))}
            applyPlanAccess()
            if known.isEmpty || known.count>2 {showSettings(page:"accounts")}
        }
        startClaudeTimer(); startZaiTimer(); updateUI(); writeMetrics(); refresh()
    }
    func configureMainMenu() {
        let appMenu=NSMenu();let root=NSMenuItem();let actions=NSMenu()
        let settings=NSMenuItem(title:"Configurações…",action:#selector(configureSettings),keyEquivalent:",");settings.target=self;actions.addItem(settings)
        let quit=NSMenuItem(title:"Sair do PlanMeter",action:#selector(quitApp),keyEquivalent:"q");quit.target=self;actions.addItem(quit)
        root.submenu=actions;appMenu.addItem(root)
        let fileMenu=NSMenuItem(title:"Arquivo",action:nil,keyEquivalent:"");let fileActions=NSMenu(title:"Arquivo")
        let close=NSMenuItem(title:"Fechar janela",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        close.target=nil;fileActions.addItem(close);fileMenu.submenu=fileActions;appMenu.addItem(fileMenu)
        NSApp.mainMenu=appMenu
    }
    func stale(_ value: QuotaSnapshot?, error: String? = nil, now: Date = Date()) -> Bool {
        guard let value=value,error==nil else{return true}
        // A live passive feed can deliver unchanged values. Its receipt clock
        // indicates delivery only; the observation clock remains unchanged.
        let timestamp=value.effectiveProvider=="claude" ? (value.receivedAt ?? value.queriedAt) : value.queriedAt
        return now.timeIntervalSince(timestamp) > (value.effectiveProvider == "claude" && value.sourceHost != "claude-code-cli" ? 120 : max(120,operations.interval(for:value.effectiveProvider)+60))
    }
    var realPending: [ResetRecord] {
        (allowed("codex") ? detector.state.activePending(snapshot: snapshot) : []) + (allowed("claude") ? claudeDetector.state.activePending(snapshot: claudeSnapshot) : [])
    }
    func updateUI() {
        refreshRenewalHistory();captureUsageTimeline()
        let badge = demoPending || !realPending.isEmpty ? " 🎉" : ""
        let presentation = StatusPresentation.make(codex: visible(snapshot,"codex"), claude: visible(claudeSnapshot,"claude"), zai: visible(zaiSnapshot,"zai"),
            codexStale: stale(snapshot, error: errorText), claudeStale: stale(claudeSnapshot, error: claudeError),
            zaiStale: stale(zaiSnapshot, error: zaiError), badge: badge, kimi:visible(kimi.snapshot,"kimi"), kimiStale:kimi.stale, showKimi:allowed("kimi"),grok:visible(grok.snapshot,"grok"),grokStale:grok.stale)
        status.button?.attributedTitle = presentation.title
        status.button?.setAccessibilityLabel(presentation.accessibilityText)
        status.button?.toolTip = presentation.accessibilityText + "\nClique abre métricas. Clique direito/Control-clique abre configurações."
        updateDashboard();buildMenu(); reconcileCelebration()
        if settingsWindow.window?.isVisible == true {let previous=accessSetup.providers;prepareAccessSettings();if previous != accessSetup.providers {settingsWindow.model.accessRevision += 1}}
    }
    func configureInsight(_ preferences:InsightPreferences,save:Bool=true) {
        let discovery=HarnessDiscovery(home:FileManager.default.homeDirectoryForCurrentUser.path,environment:ProcessInfo.processInfo.environment)
        insights.configure(preferences,discovery:discovery)
        if save,let data=try? JSONEncoder().encode(preferences) {writePrivate(data,to:cacheDirectory.appendingPathComponent("insight-preferences.json"));audit(.configuration,.app,.settingsChanged,.success)}
        syncInsightSettings()
    }
    func syncInsightSettings() {
        let model=settingsWindow.model
        model.insightPro=planAccess.isPro;model.insightBusy=insights.busy;model.insightModels=insights.models
        model.insightMessage=insights.message;model.insightPath=insights.executable ?? ""
        model.insightProviders=planAccess.active.intersection(["codex","claude","kimi","zai"]).sorted()
    }
    func currentInsightProjections()->[UsageProjection] {
        let values:[(String,QuotaSnapshot?,Bool)]=[
            ("codex",snapshot,stale(snapshot,error:errorText)),("claude",claudeSnapshot,stale(claudeSnapshot,error:claudeError)),
            ("zai",zaiSnapshot,stale(zaiSnapshot,error:zaiError)),("kimi",kimi.snapshot,kimi.stale),("grok",grok.snapshot,grok.stale)]
        return values.filter{allowed($0.0) && !$0.2}.compactMap{$0.1}.flatMap{usageTimeline.projections(for:$0,maximumGap:max(3600,operations.interval(for:$0.effectiveProvider)*1.5),connectionID:$0.credentialScope,renewals:renewalHistory.entries)}
    }
    func generateInsight() {
        guard !timelineWriteBlocked else{settingsWindow.model.insightMessage="O histórico de uso precisa ser recuperado antes de gerar insights.";return}
        insights.generate(currentInsightProjections(),permitted:planAccess.insightsAllowed && allowed(insights.preferences.provider))
    }
    func cardRefreshStatuses()->[String:CardRefreshStatus] {
        let paused=activity.suspended
        let states:[String:CardRefreshStatus]=[
            "codex":CardRefreshStatus(busy:policy.busy,paused:paused),
            "claude":CardRefreshStatus(busy:claudeQuota.busy,nextAllowedAt:claudeQuota.enabled ? claudeQuota.nextManualRefreshAt : .distantPast,paused:paused,actionTitle:claudeQuota.enabled ? "Atualizar agora" : "Reler dados locais"),
            "zai":CardRefreshStatus(busy:zaiBusy,nextAllowedAt:zaiManualCooldown,paused:paused),
            "kimi":CardRefreshStatus(busy:kimi.busy,nextAllowedAt:kimi.schedule.manual,paused:paused),
            "grok":CardRefreshStatus(busy:grok.busy,nextAllowedAt:grok.schedule.manual,paused:paused)]
        return states.filter{allowed($0.key)}
    }
    func refreshCard(_ provider:String) {
        let actions:[String:()->Void]=[
            "codex":{self.refresh()},"claude":{self.refreshClaude(manual:true)},
            "zai":{self.refreshZaiNow()},"kimi":{self.kimi.refreshNow()},"grok":{self.grok.refreshNow()}]
        _=CardRefreshRouting.request(provider,selected:planAccess.active,states:cardRefreshStatuses(),actions:actions)
    }
    func updateDashboard() {
        dashboard.cardRefreshStates=cardRefreshStatuses()
        dashboard.onCardRefresh={[weak self] key in self?.refreshCard(key)}
        dashboard.insight=planAccess.isPro ? insights.text : nil
        dashboard.insightStatus=planAccess.isPro ? (timelineWriteBlocked ? "Histórico de uso indisponível; arquivo original preservado para recuperação." : insights.status(current:currentInsightProjections())) : nil
        dashboard.insightBusy=insights.busy
        dashboard.insightEnabled=planAccess.isPro && allowed(insights.preferences.provider) && !timelineWriteBlocked
        dashboard.onInsight = {[weak self] in self?.generateInsight()}
        dashboard.onInsightSettings = {[weak self] in self?.showSettings(page:"insights")}
        dashboard.cards = [
                snapshot.map {QuotaCard(key:"codex",name:"Codex",snapshot:$0,stale:stale($0,error:errorText))},
                claudeSnapshot.map {QuotaCard(key:"claude",name:"Claude",snapshot:$0,stale:stale($0,error:claudeError))},
                zaiSnapshot.map {QuotaCard(key:"zai",name:"Z.ai",snapshot:$0,stale:stale($0,error:zaiError))},
                kimi.snapshot.map {QuotaCard(key:"kimi",name:"Kimi Code",snapshot:$0,stale:kimi.stale)},
                grok.snapshot.map {QuotaCard(key:"grok",name:"Grok",snapshot:$0,stale:grok.stale,note:grokMeasurementNote($0))}
            ].compactMap {$0}.filter{allowed($0.key)}
        dashboard.onAccess = { [weak self] in guard let self=self else{return};self.showSettings(page:QuotaCard.available(self.dashboard.cards).isEmpty ? "accounts" : "general") }
        dashboard.onRefresh = { [weak self] in self?.manualRefresh() }
        let states=providerRefreshStates()
        let activeBusy=states.contains {allowed($0.provider) && $0.busy && $0.provider != "zai"}
        dashboard.refreshEnabled = !activity.suspended && !activeBusy
        if let warning=auditLog.statusMessage {dashboard.refreshMessage=warning}
        else if !dashboard.refreshMessage.isEmpty {
            dashboard.refreshMessage=ProviderRefreshState.summary(states,selected:planAccess.active)
        }
        dashboard.update()
    }
    func providerRefreshStates()->[ProviderRefreshState] {
        let claudeMessage=claudeQuota.enabled ? claudeQuota.message : claudeError ?? (claudeSnapshot == nil ? "Claude: aguardando dados do cliente" : "Claude: leitura local concluída")
        return [
            ProviderRefreshState(provider:"codex",message:nil,busy:policy.busy),
            ProviderRefreshState(provider:"claude",message:claudeMessage,busy:claudeQuota.busy),
            ProviderRefreshState(provider:"zai",message:zaiRefreshMessage,busy:zaiBusy),
            ProviderRefreshState(provider:"kimi",message:kimi.message,busy:kimi.busy),
            ProviderRefreshState(provider:"grok",message:grok.message,busy:grok.busy)
        ]
    }
    func prepareAccessSettings() {
        func status(_ snapshot:QuotaSnapshot?)->String {StatusPresentation.validRemaining(snapshot)==nil ? "Sem métrica disponível" : "Métrica disponível em cache"}
        accessSetup.providers=[
            ProviderAccess(key:"codex",name:"Codex",status:status(snapshot),detail:"Login ChatGPT pelo Codex CLI oficial.",actionTitle:"Como conectar"),
            ProviderAccess(key:"claude",name:"Claude Code",status:status(claudeSnapshot),detail:claudeQuota.enabled ? "Consulta pela tela /usage do Claude Code oficial." : "Autorize a consulta ativa ou configure a leitura passiva.",actionTitle:"Configurar",actions:["authorize","passive"]),
            ProviderAccess(key:"zai",name:"Z.ai",status:status(zaiSnapshot),detail:"Chave no Keychain deste Mac.",actionTitle:KeychainStore.needsAuthorization ? "Autorizar acesso" : "Cadastrar chave",enabled:!zaiBusy,actions:["authorize","remove"]),
            ProviderAccess(key:"kimi",name:"Kimi Code",status:kimi.errorText ?? status(kimi.snapshot),detail:"Chave do Coding Plan no Keychain. OAuth preservado.",actionTitle:KimiKeychain.needsAuthorization ? "Autorizar acesso" : "Cadastrar chave",enabled:!kimi.busy,actions:["authorize","remove"]),
            ProviderAccess(key:"grok",name:"Grok",status:status(grok.snapshot),detail:grokMeasurementDescription(grok.snapshot),actionTitle:"Como conectar")
        ]
        let connected:[String:Bool] = [
            "codex":StatusPresentation.validRemaining(snapshot) != nil && errorText == nil,
            "claude":StatusPresentation.validRemaining(claudeSnapshot) != nil && claudeError == nil,
            "claude-remote":StatusPresentation.validRemaining(claudeSnapshot) != nil && claudeError == nil,
            "zai":StatusPresentation.validRemaining(zaiSnapshot) != nil && zaiError == nil,
            "kimi":StatusPresentation.validRemaining(kimi.snapshot) != nil && kimi.errorText == nil,
            "grok":StatusPresentation.validRemaining(grok.snapshot) != nil && grok.errorText == nil
        ]
        accessSetup.summary=planAccess.isPro ? "Pro: todos os planos disponíveis." : planAccess.needsSelection ? "Free: escolha até 2 planos. Desmarque os demais para continuar." : "Free: \(planAccess.active.count)/2 planos. Pro libera todos e insights."
        accessSetup.onSelect = {[weak self] key,enabled in self?.selectPlan(key,enabled)}
        accessSetup.onUpgrade = {[weak self] in self?.showSettings(page:"general")}
        for index in accessSetup.providers.indices {
            let key=accessSetup.providers[index].key
            accessSetup.providers[index].selected=planAccess.selected.contains(key)
            accessSetup.providers[index].selectionEnabled=planAccess.selected.contains(key) || planAccess.isPro || planAccess.selected.count<2
            accessSetup.providers[index].enabled=accessSetup.providers[index].enabled && allowed(key)
            accessSetup.providers[index].connected=allowed(key) && (connected[key] ?? false)
        }
        accessSetup.onConfigure = { [weak self] key in
            guard let self=self,(self.allowed(String(key.split(separator:":")[0])) || ["zai:remove","kimi:remove"].contains(key)) else{return}
            switch key {
            case "claude","claude:authorize":self.authorizeClaudeQuota()
            case "claude:passive":self.disableClaudeQuota()
            case "zai:authorize":self.authorizeZai()
            case "zai:remove":self.removeZai()
            case "grok":AccessSetup.guide("grok",measurement:grokMeasurementExplanation(self.grok.snapshot))
            case "kimi:authorize":self.kimi.authorizeAccess()
            case "kimi:remove":self.kimi.removeKey()
            case "kimi":if KimiKeychain.needsAuthorization {self.kimi.authorizeAccess()} else {self.kimi.configure()}
            case "zai":if KeychainStore.needsAuthorization {self.authorizeZai()} else {self.configureZai()}
            default:AccessSetup.guide(key)
            }
        }
    }
    func saveInterfacePreferences() {
        if let data=try? JSONEncoder().encode(interfacePreferences) {writePrivate(data,to:cacheDirectory.appendingPathComponent("interface-preferences.json"))}
    }
    func applyInterfacePreferences() {
        let callback=dashboard.onOptionsChanged;dashboard.onOptionsChanged={_,_ in};defer{dashboard.onOptionsChanged=callback}
        NSApp.appearance=interfacePreferences.appearance=="dark" ? NSAppearance(named:.darkAqua) : interfacePreferences.appearance=="light" ? NSAppearance(named:.aqua) : nil
        dashboard.autoCloseSeconds=interfacePreferences.dismissal
        dashboard.setScale(CGFloat(interfacePreferences.scale))
        if dashboard.pinned != interfacePreferences.pinned {dashboard.togglePinned()}
    }
    @objc func configureAccess() {showSettings(page:"accounts")}
    @objc func configureSettings() {showSettings(page:"general")}
    func showSettings(page:String) {
        prepareAccessSettings()
        let model=settingsWindow.model;model.access=accessSetup;model.accessRevision += 1
        model.configure(interface:interfacePreferences,confetti:preferences.loopEnabled,respect:preferences.respectReduceMotion)
        syncInsightSettings()
        var draft=insights.preferences
        if !model.insightProviders.contains(draft.provider) {draft.provider="";draft.model=""}
        model.configureInsight(draft)
        model.onInsightChange = {[weak self] value in self?.configureInsight(value)}
        model.onInsightModels = {[weak self] in
            guard let self=self,self.planAccess.isPro else{return}
            self.configureInsight(self.settingsWindow.model.insight);self.insights.discoverModels()
        }
        model.onInsightCheck = {[weak self] in
            guard let self=self,self.planAccess.isPro,self.allowed(self.settingsWindow.model.insight.provider) else{return}
            self.configureInsight(self.settingsWindow.model.insight);self.insights.checkConnection()
        }
        model.licenseMessage=licenseStore.message;model.licensePrice=licenseStore.price;model.licenseBusy=licenseStore.busy
        model.onPurchase = {[weak self] in self?.licenseStore.purchase()}
        model.onRestore = {[weak self] in self?.licenseStore.restore()}
        #if PLANMETER_DEVELOPMENT
        model.onSimulation = {[weak self] pro in self?.simulatedPro=pro;self?.syncLicense()}
        #endif
        model.configureOperations(operations,path:auditLog.directory.path,error:auditLog.statusMessage)
        model.onOperationsChange = {[weak self] value in
            guard let self=self else{return}
            if let data=try? JSONEncoder().encode(value),self.writePrivate(data,to:self.cacheDirectory.appendingPathComponent("operations.json")) {
                self.audit(.configuration,.app,.settingsChanged,.success)
                self.applyOperations(value)
            } else {self.settingsWindow.model.logError="Não foi possível salvar as preferências."}
        }
        model.onLoginAudit = {[weak self] result in self?.audit(.configuration,.app,.settingsChanged,result)}
        model.onLogDirectory = {[weak self] in
            guard let self=self,!Runtime.isTest else{return}
            NSWorkspace.shared.open(self.auditLog.directory)
        }
        model.onViewLog = {[weak self] category in
            guard let self=self,!Runtime.isTest else{return}
            let file=self.auditLog.url(category)
            if FileManager.default.fileExists(atPath:file.path) {NSWorkspace.shared.open(file)}
            else {self.settingsWindow.model.logError="Ainda não há registros para esta categoria."}
        }
        model.onChange = { [weak self] interface,confetti,respect in
            guard let self=self else{return};self.interfacePreferences=interface
            self.preferences.loopEnabled=confetti;self.preferences.respectReduceMotion=respect
            self.saveInterfacePreferences();self.savePreferences();self.audit(.configuration,.app,.settingsChanged,.success);self.applyInterfacePreferences();self.updateUI()
        }
        settingsWindow.show(page:page)
    }
    @objc func statusClicked() {
        let event = NSApp.currentEvent
        let right = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if !right {
            if demoPending || !realPending.isEmpty { acknowledge() }
            updateDashboard()
            if let button=status.button,let window=button.window,let screen=window.screen {
                dashboard.toggle(anchor:window.convertToScreen(button.convert(button.bounds,to:nil)),screen:screen)
            }
            return
        }
        if !dashboard.pinned {dashboard.close()}
        if let button = status.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button) }
    }
    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(); countdownTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.updateCountdowns() }
        RunLoop.main.add(timer, forMode: .common); countdownTimer = timer
    }
    func menuDidClose(_ menu: NSMenu) { countdownTimer?.invalidate(); countdownTimer = nil }
    func updateCountdowns() {
        for item in menu.items {
            if let key = item.representedObject as? String {
                for value in [snapshot, claudeSnapshot].compactMap({ $0 }) {
                    for w in value.windows where key == value.effectiveProvider + ":" + w.name { item.title = countdownLabel(reset: w.reset) }
                }
            }
        }
    }
    func info(_ text: String) -> NSMenuItem { let i = NSMenuItem(title: text, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }
    func addProvider(_ title: String, value: QuotaSnapshot?, error: String?, showObservation: Bool = true) {
        menu.addItem(info(title + " — restante"))
        if let value = value {
            if showObservation { menu.addItem(info("Dados observados: \(localDate(value.queriedAt))")) }
            if showObservation && stale(value, error: error) { menu.addItem(info("Desatualizado · não é leitura nova do provedor")) }
            if value.windows.isEmpty { menu.addItem(info("Janelas não informadas")) }
            for w in value.windows {
                menu.addItem(info("\(w.name) · \(durationLabel(w.durationMinutes)): \(percentLabel(w.remaining))"))
                menu.addItem(info(w.reset.map { "Reset previsto: \(localDate(Date(timeIntervalSince1970: $0)))" } ?? "Reset não informado"))
                let countdown = info(countdownLabel(reset: w.reset)); countdown.representedObject = value.effectiveProvider + ":" + w.name; menu.addItem(countdown)
            }
        } else { menu.addItem(info("— · sem dados de quota")) }
        if let error = error { menu.addItem(info(error)) }
    }
    func buildMenu() {
        menu.removeAllItems()
        let access=NSMenuItem(title:"Configurações…",action:#selector(configureSettings),keyEquivalent:"")
        access.target=self;menu.addItem(access);menu.addItem(NSMenuItem.separator())
        let zaiUpdate = NSMenuItem(title: "Z.ai: consultar agora", action: #selector(refreshZaiNow), keyEquivalent: "")
        zaiUpdate.target = self; zaiUpdate.isEnabled = allowed("zai") && !activity.suspended && !zaiRequestIsManual
        if !allowed("zai") {zaiUpdate.title="Z.ai: plano não selecionado"}
        menu.addItem(zaiUpdate)
        menu.addItem(NSMenuItem.separator())
        let kimiUpdate = NSMenuItem(title:"Kimi: consultar agora",action:#selector(KimiMonitor.refreshNow),keyEquivalent:"")
        kimiUpdate.target=kimi;kimiUpdate.isEnabled = allowed("kimi") && !activity.suspended && !kimi.busy;if !allowed("kimi") {kimiUpdate.title="Kimi: plano não selecionado"};menu.addItem(kimiUpdate)
        let grokUpdate=NSMenuItem(title:"Grok: consultar agora",action:#selector(GrokMonitor.refreshNow),keyEquivalent:"")
        grokUpdate.target=grok;grokUpdate.isEnabled = allowed("grok") && !activity.suspended && !grok.busy;if !allowed("grok") {grokUpdate.title="Grok: plano não selecionado"};menu.addItem(grokUpdate)
        let usage = NSMenuItem(title: "Claude: abrir Settings → Usage", action: #selector(openClaudeUsage), keyEquivalent: "")
        usage.target = self; menu.addItem(usage)
        menu.addItem(NSMenuItem.separator())
        let history = NSMenuItem(title: "Histórico de renovações", action: nil, keyEquivalent: "")
        history.submenu = historyMenu(); menu.addItem(history)
        let ack = NSMenuItem(title: "Dispensar aviso/confete", action: #selector(acknowledge), keyEquivalent: "")
        ack.target = self; ack.isEnabled = demoPending || !realPending.isEmpty; menu.addItem(ack)
        let demo = NSMenuItem(title: "DEMO de confete em loop (sem consulta)", action: #selector(demoConfetti), keyEquivalent: "")
        demo.target = self; menu.addItem(demo)
        let animated = NSMenuItem(title: "DEMO animada (exceção somente neste teste)", action: #selector(demoMotionConfetti), keyEquivalent: "")
        animated.target = self; menu.addItem(animated)
        let refresh = NSMenuItem(title: "Atualizar agora", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self; refresh.isEnabled = !policy.busy && !policy.sleeping; menu.addItem(refresh)
        let quit = NSMenuItem(title: "Sair", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
    }
    func loadRenewalHistory() {
        let file=cacheDirectory.appendingPathComponent("renewal-history.json")
        guard FileManager.default.fileExists(atPath:file.path) else{return}
        do {renewalHistory=try JSONDecoder().decode(RenewalHistory.self,from:Data(contentsOf:file))}
        catch {
            let backup=cacheDirectory.appendingPathComponent("renewal-history.corrupt-"+UUID().uuidString+".json")
            do {try FileManager.default.moveItem(at:file,to:backup);renewalRecoveryMessage="Não foi possível ler o histórico anterior; uma cópia foi preservada para recuperação."}
            catch {renewalHistoryWriteBlocked=true;renewalRecoveryMessage="Não foi possível ler o histórico; o arquivo original foi preservado e a gravação suspensa."}
        }
    }
    func refreshRenewalHistory() {
        var changed=false
        for record in detector.state.history+claudeDetector.state.history where !importedRenewalDetections.contains(record.id) {changed=renewalHistory.importDetection(record) || changed;importedRenewalDetections.insert(record.id)}
        for value in [snapshot,claudeSnapshot,zaiSnapshot,kimi.historySnapshot,grok.snapshot].compactMap({$0}) {changed=renewalHistory.ingest(value) || changed}
        renewalHistoryDirty=renewalHistoryDirty || changed
        if renewalHistoryDirty,!renewalHistoryWriteBlocked,let data=try? JSONEncoder().encode(renewalHistory),writePrivate(data,to:cacheDirectory.appendingPathComponent("renewal-history.json")) {renewalHistoryDirty=false}
        renewalWindow.persistenceMessage=renewalRecoveryMessage ?? (renewalHistoryDirty ? "Não foi possível salvar o histórico; nova tentativa na próxima leitura." : nil)
        renewalWindow.update(renewalHistory)
    }
    func historyMenu() -> NSMenu {
        let menu=renewalHistory.menu(target:self,action:#selector(showRenewalHistory))
        if let message=renewalRecoveryMessage {menu.insertItem(info(message),at:1)}
        return menu
    }
    @objc func showRenewalHistory() {refreshRenewalHistory();renewalWindow.show(renewalHistory)}
    func reconcileCelebration() {
        let pending = realPending
        guard !activity.suspended, demoPending || (!pending.isEmpty && journalHealthy) else { confetti.close(); shownKey = nil; return }
        let motion = preferences.loopEnabled && (demoMotion && demoPending || !preferences.respectReduceMotion || !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let key = (demoPending ? "demo" : pending.map(\.id).sorted().joined(separator: ",")) + ":\(motion)"
        guard shownKey != key else { return }
        shownKey = key
        let providers = Set(pending.map { ($0.provider ?? "codex") == "claude" ? "Claude" : "Codex" }).sorted().joined(separator: " + ")
        confetti.onAcknowledge = { [weak self] in self?.acknowledge() }
        confetti.showLoop(message: demoPending ? "DEMO separada. Sem quota/histórico real. Clique neste aviso para dispensar." : "\(providers): \(pending.count) reset(s) detectado(s). Clique neste aviso para reconhecer.", demo: demoPending, motion: motion, display: celebrationDisplay, renderOffscreen: celebrationRenderOffscreen)
    }
    @objc func acknowledge() {
        if demoPending { demoPending = false; demoMotion = false }
        else {
            let pending = Set(realPending.map(\.id)); let old = detector.state, oldClaude = claudeDetector.state
            detector.state.acknowledge(ids: pending); claudeDetector.state.acknowledge(ids: pending)
            if !saveStates() { detector.state = old; claudeDetector.state = oldClaude; errorText = "Reconhecimento não foi salvo; tente novamente" }
        }
        confetti.close(); shownKey = nil; updateUI(); writeMetrics()
    }
    @objc func toggleLoop() { preferences.loopEnabled.toggle(); savePreferences();audit(.configuration,.app,.settingsChanged,.success); shownKey = nil; updateUI() }
    @objc func toggleRespect() { preferences.respectReduceMotion.toggle(); savePreferences();audit(.configuration,.app,.settingsChanged,.success); shownKey = nil; updateUI() }
    func startDemo(motion: Bool) { demoPending = true; demoMotion = motion; shownKey = nil; updateUI(); writeMetrics() }
    @objc func demoConfetti() { startDemo(motion: false) }
    @objc func demoMotionConfetti() { startDemo(motion: true) }
    @discardableResult func writePrivate(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); return true
        } catch { return false }
    }
    func saveStates() -> Bool {
        guard let one = try? JSONEncoder().encode(detector.state), let two = try? JSONEncoder().encode(claudeDetector.state) else { return false }
        journalHealthy = writePrivate(one, to: resetFile) && writePrivate(two, to: claudeResetFile)
        return journalHealthy
    }
    func savePreferences() { if let data = try? JSONEncoder().encode(preferences) { writePrivate(data, to: preferencesFile) } }
    func writeMetrics() {
        let raw: [String:Any] = ["pid":ProcessInfo.processInfo.processIdentifier,"statusItemVisible":status?.isVisible ?? false,
            "claudeActiveEnabled":claudeQuota.enabled,"claudeActiveRequests":claudeQuota.requests,"claudeActiveStatus":claudeQuota.lastStatus,
            "claudeCacheReads":claudeCacheReads,"claudeHasMetrics":StatusPresentation.validRemaining(claudeSnapshot) != nil,
            "claudeFeedStale":stale(claudeSnapshot,error:claudeError),
            "claudeReceivedAtUnix":claudeSnapshot?.receivedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            "claudeObservationAtUnix":claudeSnapshot?.queriedAt.timeIntervalSince1970 as Any? ?? NSNull(),
            "grokStatus":grok.reading?.status ?? "pending","grokBusy":grok.busy,"grokRequests":grok.requests,"kimiStatus":kimi.reading?.status ?? "pending","kimiBusy":kimi.busy,"kimiRequests":kimi.requests,"zaiManualRequests":zaiManualRequests,"zaiAuthStatus":zaiReading?.status ?? "pending","zaiBusy":zaiBusy,
            "zaiRefreshMessage":zaiRefreshMessage as Any? ?? NSNull(),"zaiReads":zaiReads,
            "failures":policy.failures,"busy":policy.busy,"sleeping":policy.sleeping,
            "realHistoryCount":detector.state.history.count+claudeDetector.state.history.count]
        if let data = try? JSONSerialization.data(withJSONObject:raw,options:[.sortedKeys]) { writePrivate(data,to:metricsFile) }
    }
    func schedule() {
        timer?.invalidate(); timer = nil; guard allowed("codex"),!policy.sleeping else { return }
        let next = Timer(timeInterval: policy.delay(), repeats: false) { [weak self] _ in self?.refresh() }
        next.tolerance = 2; RunLoop.main.add(next, forMode: .common); timer = next
    }
    func readClaudeCache() {
        guard allowed("claude"),!claudeQuota.enabled else{return}
        claudeCacheReads += 1
        let provider = ClaudeCacheProvider(path: cacheDirectory.appendingPathComponent("claude-statusline.json"))
        do {
            let current = try provider.read()
            // JSON epoch conversion can shift an unchanged timestamp by a fraction of a millisecond.
            if current.queriedAt.timeIntervalSince(claudeDetector.state.baseline?.queriedAt ?? .distantPast) > 0.001 { _ = claudeDetector.accept(current); _ = saveStates() }
            claudeSnapshot = current; claudeError = nil;audit(.queries,.claude,.readCache,.success)
        } catch { claudeError = "Aguardando dados do uso normal Claude; cache indisponível"; claudeDetector.interrupt();audit(.queries,.claude,.readCache,.failure) }
    }
    func refreshClaude(manual:Bool=false) {
        guard allowed("claude"),!activity.suspended else { return }
        if claudeQuota.enabled {claudeQuota.refresh(manual:manual)} else {readClaudeCache();updateUI()}
    }
    func authorizeClaudeQuota() {
        guard !Runtime.isTest,allowed("claude"),!claudeQuota.busy else{return}
        let alert=NSAlert();alert.messageText="Consultar a quota pelo Claude Code?"
        alert.informativeText="O PlanMeter abrirá o cliente oficial para ler /usage. Ao continuar, você autoriza confirmar confiança somente na pasta vazia e exclusiva ~/Library/Application Support/PlanMeter/ClaudeProbe. Isso altera uma preferência de segurança do Claude Code. O login permanece sob controle do cliente, e a consulta não envia um pedido ao modelo."
        alert.addButton(withTitle:"Ativar e autorizar essa pasta");alert.addButton(withTitle:"Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        guard claudeQuota.setConsent(true) else{return}
        claudeQuota.refresh(manual:true,setup:true)
        audit(.access,.claude,.authorize,.success);startClaudeTimer();prepareAccessSettings();settingsWindow.model.accessRevision += 1
    }
    func disableClaudeQuota() {
        guard !Runtime.isTest,!claudeQuota.busy else{return}
        let alert=NSAlert();alert.messageText="Usar leitura passiva do Claude Code?";alert.informativeText="A consulta ativa será desativada. O login Claude permanece intacto. Na leitura passiva, Atualizar apenas relê a statusline e pode não trazer quotas recentes.";alert.addButton(withTitle:"Usar leitura passiva");alert.addButton(withTitle:"Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn,claudeQuota.setConsent(false) else{return}
        audit(.configuration,.claude,.settingsChanged,.success);startClaudeTimer();prepareAccessSettings();settingsWindow.model.accessRevision += 1;AccessSetup.guide("claude")
    }
    func saveZaiSchedule() {
        let schedule = ZaiSchedule(manual:zaiManualCooldown.timeIntervalSince1970,automatic:zaiAutomaticAfter.timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(schedule) { writePrivate(data,to:zaiCooldownFile) }
    }
    func startZaiTimer() {
        zaiTimer?.invalidate(); zaiTimer = nil
        guard zaiEnabled, !activity.suspended else { return }
        refreshZai()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshZai() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common); zaiTimer = timer
    }
    @objc func refreshZai() { requestZai(manual: false) }
    @objc func refreshZaiNow() { requestZai(manual: true) }
    func requestZai(manual: Bool) {
        guard zaiEnabled, !activity.suspended else { return }
        if zaiBusy {
            if manual && !zaiRequestIsManual { zaiManualPending = true; zaiRefreshMessage = "Z.ai: consulta aguardando leitura em curso"; updateUI() }
            return
        }
        if Date() < zaiManualCooldown {
            let seconds = max(1, Int(ceil(zaiManualCooldown.timeIntervalSinceNow)))
            if manual { zaiRefreshMessage = "Z.ai: aguarde \(seconds)s para nova consulta (limite de frequência)" }
            updateUI(); writeMetrics(); return
        }
        guard manual || (Date() >= zaiCooldown && Date() >= zaiAutomaticAfter) else { return }
        zaiBusy = true; zaiRequestIsManual = manual; zaiReads += 1
        if manual { zaiManualRequests += 1; zaiRefreshMessage = "Z.ai: consultando o serviço…" }
        let started = Date()
        zaiGeneration += 1;let token=zaiGeneration
        zaiManualCooldown = started.addingTimeInterval(60)
        zaiAutomaticAfter = started.addingTimeInterval(operations.interval(for:"zai"))
        saveZaiSchedule()
        let request = zaiClientFactory()
        zaiClient = request;audit(.queries,.zai,.query,.started); updateUI(); writeMetrics()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try request.read() }
            DispatchQueue.main.async { [weak self] in
                guard let self = self,self.zaiGeneration==token else { return }
                self.zaiBusy = false; self.zaiRequestIsManual = false; self.zaiClient = nil
                self.audit(.queries,.zai,.query,(try? result.get()).map{$0.status == "ok"} == true ? .success : .failure)
                guard self.allowed("zai"),!self.activity.suspended else {
                    if manual || self.zaiManualPending { self.zaiRefreshMessage = "Z.ai: consulta interrompida pela pausa; solicite novamente ao retomar" }
                    self.zaiManualPending = false; self.writeMetrics(); return
                }
                switch result {
                case .success(let reading):
                    self.zaiReading = reading
                    self.zaiManualCooldown = reading.nextAttemptAt.map { Date(timeIntervalSince1970: $0) } ?? started.addingTimeInterval(60)
                    self.zaiAutomaticAfter = max(self.zaiAutomaticAfter,self.zaiManualCooldown)
                    self.saveZaiSchedule()
                    if reading.status == "ok" {
                        self.zaiSnapshot = reading.snapshot; self.zaiError = nil
                        if let data = try? JSONEncoder().encode(reading) { self.writePrivate(data, to: self.zaiFile) }
                        if manual {
                            self.zaiRefreshMessage = reading.snapshot.queriedAt >= started.addingTimeInterval(-2)
                                ? "Z.ai: coleta concluída às " + localDate(reading.snapshot.queriedAt)
                                : "Z.ai: coleta recente reutilizada; limite de frequência do serviço"
                        }
                    } else {
                        self.zaiError = zaiStatus(reading)
                        if manual { self.zaiRefreshMessage = "Z.ai: " + zaiStatus(reading) }
                    }
                    if let data = try? JSONEncoder().encode(reading) { self.writePrivate(data,to:self.zaiFile) }
                    self.zaiCooldown = Date().addingTimeInterval(30)
                case .failure:
                    self.zaiError = manual ? "Consulta Z.ai falhou; confira rede e acesso ao Keychain. Quota anterior preservada" : "Consulta automática Z.ai falhou; quota anterior preservada"
                    if manual { self.zaiRefreshMessage = self.zaiError }
                    self.zaiCooldown = Date().addingTimeInterval(60)
                }
                self.updateUI(); self.writeMetrics()
                if self.zaiManualPending { self.zaiManualPending = false; self.refreshZaiNow() }
            }
        }
    }
    @objc func authorizeZai() {
        guard allowed("zai"),!Runtime.isTest,!zaiBusy else{return}
        if KeychainStore.authorize() {audit(.access,.zai,.authorize,.success);if zaiReading?.status=="auth_unavailable" {zaiManualCooldown = .distantPast;zaiAutomaticAfter = .distantPast;saveZaiSchedule()};zaiError=nil;zaiRefreshMessage="Z.ai: acesso autorizado nesta execução";updateUI();refreshZaiNow()}
        else {audit(.access,.zai,.authorize,.failure);let alert=NSAlert();alert.messageText="Z.ai";alert.informativeText="Acesso não autorizado. Use Configurações → Contas para tentar novamente.";alert.runModal()}
    }
    @objc func configureZai() {
        guard allowed("zai"),!Runtime.isTest, !zaiBusy else { return }
        let alert = NSAlert(); alert.messageText = "Chave Z.ai"
        alert.informativeText = "A chave será salva no Keychain deste Mac e usada somente para consultar quotas. Não coloque a chave no chat ou em arquivos de configuração."
        let field = KimiCredentialField(frame:NSRect(x:0,y:0,width:340,height:24))
        alert.window.initialFirstResponder=field
        alert.accessoryView = field; alert.addButton(withTitle:"Salvar"); alert.addButton(withTitle:"Cancelar")
        NSApp.activate(ignoringOtherApps:true)
        guard alert.runModal() == .alertFirstButtonReturn else { field.stringValue = ""; return }
        defer { field.stringValue = "" }
        do {
            try KeychainStore.save(field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines))
            audit(.access,.zai,.saveKey,.success);clearZaiCache(); zaiManualCooldown = .distantPast; refreshZaiNow()
        } catch { audit(.access,.zai,.saveKey,.failure);zaiError = (error as? QuotaError)?.text ?? "Falha ao salvar no Keychain"; updateUI();let errorAlert=NSAlert();errorAlert.messageText="Z.ai";errorAlert.informativeText=zaiError!;errorAlert.runModal() }
    }
    @objc func removeZai() {
        guard !Runtime.isTest, !zaiBusy else { return }
        let alert = NSAlert(); alert.messageText = "Remover a chave Z.ai deste Mac?"
        alert.informativeText = "Isso remove somente o item do PlanMeter no Keychain. Não revoga a chave na Z.ai."
        alert.addButton(withTitle:"Cancelar"); alert.addButton(withTitle:"Remover")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try KeychainStore.remove();audit(.access,.zai,.removeKey,.success); clearZaiCache(); updateUI() }
        catch { audit(.access,.zai,.removeKey,.failure);zaiError = "Não foi possível remover a chave do Keychain"; updateUI() }
    }
    func clearZaiCache() {
        zaiGeneration += 1;zaiClient?.cancel();zaiClient=nil;zaiBusy=false;zaiRequestIsManual=false;zaiManualPending=false
        zaiSnapshot = nil; zaiReading = nil; zaiRefreshMessage = nil
        zaiManualCooldown = .distantPast; zaiAutomaticAfter = .distantPast
        zaiError = "Configure a chave Z.ai no menu para consultar quotas"
        try? FileManager.default.removeItem(at:zaiFile)
        try? FileManager.default.removeItem(at:zaiCooldownFile)
    }
    @objc func openClaudeUsage() { if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) } }
    func startClaudeTimer() {
        claudeTimer?.invalidate(); claudeTimer = nil
        guard allowed("claude"),!activity.suspended else { return }
        if claudeQuota.enabled {claudeQuota.pause(false);return}
        refreshClaude()
        let timer = Timer(timeInterval: operations.interval(for:"claude-passive"), repeats: true) { [weak self] _ in
            self?.refreshClaude(); self?.updateUI(); self?.writeMetrics()
        }
        timer.tolerance = 2; RunLoop.main.add(timer, forMode: .common); claudeTimer = timer
    }
    @objc func manualRefresh() { refreshClaude(manual:true); refresh(); refreshZaiNow(); kimi.refreshNow(); grok.refreshNow() }
    func refresh() {
        guard allowed("codex"),policy.begin() else { return }
        timer?.invalidate(); timer = nil; attempts += 1;audit(.queries,.codex,.query,.started)
        let started = Date(), request = AppServerClient(binary: binary); client = request; updateUI(); writeMetrics()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try request.read() }; let elapsed = Date().timeIntervalSince(started)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.audit(.queries,.codex,.query,(try? result.get()) != nil ? .success : .failure)
                self.quotaRequests += request.quotaRequests; self.lastElapsed = elapsed; self.client = nil
                guard self.allowed("codex") else{self.policy.busy=false;return}
                if self.policy.sleeping || self.wakePending {
                    self.policy.busy = false; self.writeMetrics()
                    if self.wakePending && !self.policy.sleeping { self.wakePending = false; self.refresh() }; return
                }
                switch result {
                case .success(let value):
                    _ = self.detector.accept(value); _ = self.saveStates()
                    self.snapshot = value; self.errorText = nil; self.policy.finish(success: true)
                    if let data = try? JSONEncoder().encode(value) { self.writePrivate(data, to: self.cacheFile) }
                case .failure(let error): self.detector.interrupt(); self.errorText = (error as? QuotaError)?.text ?? "Consulta oficial falhou"; self.policy.finish(success: false)
                }
                self.updateUI(); self.writeMetrics(); self.schedule()
            }
        }
    }
    func syncSuspension() {
        policy.sleeping = activity.suspended
        claudeQuota.pause(activity.suspended || !allowed("claude"))
        kimi.setPaused(activity.suspended);grok.setPaused(activity.suspended)
        if activity.suspended {
            dashboard.close()
            errorText = "Dados em cache; aguardando verificação após pausa"
            claudeError = "Cache aguardando verificação após pausa"
            detector.interrupt(); claudeDetector.interrupt(); timer?.invalidate(); timer = nil; claudeTimer?.invalidate(); claudeTimer = nil; zaiTimer?.invalidate(); zaiTimer = nil; client?.cancel(); zaiClient?.cancel()
            confetti.close(); shownKey = nil; writeMetrics()
        } else {
            startClaudeTimer(); startZaiTimer(); updateUI()
            if policy.busy { wakePending = true } else { refresh() }
        }
    }
    func sleep() { activity.sleeping = true; wakePending = false; syncSuspension() }
    func wake() { activity.sleeping = false; syncSuspension() }
    func setScreenLocked(_ locked: Bool) { activity.screenLocked = locked; syncSuspension() }
    func setDisplaySleeping(_ sleeping: Bool) { activity.displaySleeping = sleeping; syncSuspension() }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        licenseStore.stop();insights.cancel();claudeQuota.stop();usagePersistence.flush()
        dashboard.close();kimi.stop();grok.stop()
        timer?.invalidate(); claudeTimer?.invalidate(); zaiTimer?.invalidate(); countdownTimer?.invalidate(); confetti.close(); client?.stopForExit(); zaiClient?.cancel()
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        for o in distributedObservers { DistributedNotificationCenter.default().removeObserver(o) }
    }
}
@main struct Launcher {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.contains(where:{$0.hasSuffix("-self-test") && !Runtime.testModes.contains($0)}) {
            fputs("Modo de teste desconhecido.\n",stderr);exit(2)
        }
        // AppKit persists status-item visibility under the bundle identity, even in tests.
        // Refuse before any NSApplication/NSStatusItem is created in a normal bundle.
        let uiTests = ["--ui-self-test", "--confetti-self-test", "--loop-self-test"]
        let isUITest = CommandLine.arguments.contains { uiTests.contains($0) }
        let testPrefix = "io.github.pcarielo.planmeter.tests."
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let isolated = bundleID.hasPrefix(testPrefix) && UUID(uuidString: String(bundleID.dropFirst(testPrefix.count))) != nil
        if (isUITest && !isolated) || (isolated && !isUITest) {
            fputs("Testes AppKit exigem pacote isolado. Use python3 tests/run-ui-tests.py.\n", stderr)
            exit(2)
        }
        if CommandLine.arguments.contains("--self-test") { runClaudeCLIProbeTests();runClaudeCLIParserTests();runLicenseTests();runUsagePersistenceTests();runInsightModelTests();runInsightAdapterTests();runInsightRunnerTests();runHarnessDiscoveryTests();runPlanAccessTests();runUsageTimelineTests();runInsightAnalysisTests();runCardRefreshRoutingTests();runProviderRefreshTests();runOperationsTests();runTests(); runResetTests(); runHistoryTests(); runZaiTests(); runKimiTests();runCredentialPolicyTests();runGrokTests(); runLocalClientTests(); return }
        if CommandLine.arguments.contains("--confetti-self-test") { runConfettiTests(); return }
        if CommandLine.arguments.contains("--loop-self-test") { runLoopTests(); return }
        if CommandLine.arguments.contains("--ui-self-test") {
            guard let i = CommandLine.arguments.firstIndex(of: "--codex"), i+1 < CommandLine.arguments.count else { exit(2) }
            runClaudeQuotaMonitorTests();runPlanAccessUITests();runUITests(binary: CommandLine.arguments[i+1]); runZaiUITests(); runZaiRefreshTests(); runKimiMonitorTests(); runQuotaDashboardTests();runResetNoticeTests();runAccessTests();runSettingsTests();runRenewalHistoryUITests(); return
        }
        if CommandLine.arguments.contains("--demo-confetti") || CommandLine.arguments.contains("--demo-confetti-motion") {
            // One request to the running app: no second persistent demo app/process or model call.
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pcarielo.planmeter").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else { print("Abra PlanMeter primeiro, depois use a DEMO no menu."); exit(1) }
            DistributedNotificationCenter.default().postNotificationName(MenuApp.demoRequest, object: "io.github.pcarielo.planmeter", userInfo: ["motion": CommandLine.arguments.contains("--demo-confetti-motion")], deliverImmediately: true)
            return
        }
        if CommandLine.arguments.contains("--configure-kimi") {
            guard NSRunningApplication.runningApplications(withBundleIdentifier:"io.github.pcarielo.planmeter").contains(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) else {exit(1)}
            DistributedNotificationCenter.default().postNotificationName(MenuApp.kimiConfigureRequest,object:"io.github.pcarielo.planmeter",userInfo:nil,deliverImmediately:true)
            return
        }
        if CommandLine.arguments.contains("--refresh-zai-now") {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pcarielo.planmeter").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else { exit(1) }
            DistributedNotificationCenter.default().postNotificationName(MenuApp.zaiRefreshRequest, object: "io.github.pcarielo.planmeter", userInfo: nil, deliverImmediately: true)
            print("Solicitação Z.ai enviada ao monitor; confirme o resultado nas métricas/menu.")
            return
        }
        if CommandLine.arguments.contains("--diagnostic") {
            let args = CommandLine.arguments
            let binary = args.firstIndex(of: "--codex").flatMap { $0+1 < args.count ? args[$0+1] : nil } ?? Runtime.codexPath()
            let client = AppServerClient(binary: binary), start = Date()
            do { let s = try client.read(); print("Consulta: \(localDate(s.queriedAt)); restante: \(percentLabel(s.remaining)); quotaRequests=\(client.quotaRequests); elapsed=\(String(format:"%.3f",Date().timeIntervalSince(start)))s")
                for w in s.windows { print("\(w.name): \(durationLabel(w.durationMinutes)); \(percentLabel(w.remaining))") }
            } catch { print((error as? QuotaError)?.text ?? "Consulta oficial falhou"); exit(1) }; return
        }
        let app = NSApplication.shared, delegate = MenuApp(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
