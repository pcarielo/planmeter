import AppKit
import Foundation

final class MenuApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var menu = NSMenu()
    var snapshot: QuotaSnapshot?
    var zaiReading: ZaiReading?, zaiSnapshot: QuotaSnapshot?
    var zaiError: String? = "Configure a chave Z.ai no menu para consultar quotas"
    var zaiBusy = false, zaiReads = 0
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
    static let zaiRefreshRequest = Notification.Name("io.github.pcarielo.planmeter.refresh-zai")
    static let demoRequest = Notification.Name("io.github.pcarielo.planmeter.explicit-demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pcarielo.planmeter").count > 1 { NSApp.terminate(nil); return }
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
        if let data = try? Data(contentsOf: preferencesFile), let pref = try? JSONDecoder().decode(CelebrationPreferences.self, from: data) { preferences = pref }
        if let data = try? Data(contentsOf: zaiFile), let cached = try? JSONDecoder().decode(ZaiReading.self, from: data) { zaiReading = cached; zaiSnapshot = cached.snapshot; zaiError = "Cache Z.ai; aguardando leitura" }
        errorText = snapshot == nil ? nil : "Dados em cache; aguardando leitura"
        menu.delegate = self
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
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] { activity.screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false; policy.sleeping = activity.suspended }
        if let reading = zaiReading { zaiManualCooldown = reading.nextAttemptAt.map { Date(timeIntervalSince1970:$0) } ?? .distantPast }
        if let data = try? Data(contentsOf:zaiCooldownFile), let schedule = try? JSONDecoder().decode(ZaiSchedule.self,from:data) {
            let now = Date().timeIntervalSince1970
            if schedule.manual.isFinite, schedule.manual > now, schedule.manual <= now + 86400 { zaiManualCooldown = max(zaiManualCooldown,Date(timeIntervalSince1970:schedule.manual)) }
            if schedule.automatic.isFinite, schedule.automatic > now, schedule.automatic <= now + 86400 { zaiAutomaticAfter = Date(timeIntervalSince1970:schedule.automatic) }
        }
        startClaudeTimer(); startZaiTimer(); updateUI(); writeMetrics(); refresh()
    }
    func stale(_ value: QuotaSnapshot?, error: String? = nil, now: Date = Date()) -> Bool {
        error != nil || value == nil || now.timeIntervalSince(value!.queriedAt) > (value!.effectiveProvider == "zai" ? 960 : 120)
    }
    var realPending: [ResetRecord] {
        detector.state.activePending(snapshot: snapshot) + claudeDetector.state.activePending(snapshot: claudeSnapshot)
    }
    func updateUI() {
        let badge = demoPending || !realPending.isEmpty ? " 🎉" : ""
        let presentation = StatusPresentation.make(codex: snapshot, claude: claudeSnapshot, zai: zaiSnapshot,
            codexStale: stale(snapshot, error: errorText), claudeStale: stale(claudeSnapshot, error: claudeError),
            zaiStale: stale(zaiSnapshot, error: zaiError), badge: badge)
        status.button?.attributedTitle = presentation.title
        status.button?.setAccessibilityLabel(presentation.accessibilityText)
        status.button?.toolTip = presentation.accessibilityText + "\nClique único dispensa aviso pendente. Clique direito/Control-clique abre menu."
        buildMenu(); reconcileCelebration()
    }
    @objc func statusClicked() {
        let event = NSApp.currentEvent
        let right = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if !right && (demoPending || !realPending.isEmpty) { acknowledge(); return }
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
        addProvider("Codex", value: snapshot, error: errorText)
        menu.addItem(NSMenuItem.separator())
        addProvider("Claude", value: claudeSnapshot, error: claudeError)
        menu.addItem(info("Claude: cache local da statusline; atualizado durante o uso do Claude Code"))
        menu.addItem(NSMenuItem.separator())
        addProvider("Z.ai", value: zaiSnapshot, error: zaiError)
        menu.addItem(info("Z.ai: consulta HTTPS local; chave no Keychain"))
        menu.addItem(info("Coleta automática: 15 min; consulta manual com intervalo de 60s"))
        if let reading = zaiReading {
            menu.addItem(info("Última coleta Z.ai: " + localDate(reading.snapshot.queriedAt)))
            let age = max(0, Int(Date().timeIntervalSince(reading.snapshot.queriedAt)))
            menu.addItem(info("Idade da coleta Z.ai: \(age)s"))
        }
        if let message = zaiRefreshMessage { menu.addItem(info(message)) }
        menu.addItem(info("Sem janela semanal ou reset presumidos"))
        let zaiUpdate = NSMenuItem(title: "Z.ai: consultar agora", action: #selector(refreshZaiNow), keyEquivalent: "")
        zaiUpdate.target = self; zaiUpdate.isEnabled = !activity.suspended && !zaiRequestIsManual
        menu.addItem(zaiUpdate)
        let configure = NSMenuItem(title:"Z.ai: configurar chave…",action:#selector(configureZai),keyEquivalent:"")
        configure.target = self; configure.isEnabled = !zaiBusy; menu.addItem(configure)
        let remove = NSMenuItem(title:"Z.ai: remover chave…",action:#selector(removeZai),keyEquivalent:"")
        remove.target = self; remove.isEnabled = !zaiBusy; menu.addItem(remove)
        let usage = NSMenuItem(title: "Claude: abrir Settings → Usage", action: #selector(openClaudeUsage), keyEquivalent: "")
        usage.target = self; menu.addItem(usage)
        menu.addItem(NSMenuItem.separator())
        let history = NSMenuItem(title: "Histórico de resets detectados", action: nil, keyEquivalent: "")
        history.submenu = historyMenu(); menu.addItem(history)
        let ack = NSMenuItem(title: "Dispensar aviso/confete", action: #selector(acknowledge), keyEquivalent: "")
        ack.target = self; ack.isEnabled = demoPending || !realPending.isEmpty; menu.addItem(ack)
        let loop = NSMenuItem(title: "Loop de confete (15 FPS)", action: #selector(toggleLoop), keyEquivalent: "")
        loop.target = self; loop.state = preferences.loopEnabled ? .on : .off; menu.addItem(loop)
        let respect = NSMenuItem(title: "Respeitar Reduzir Movimento do Mac", action: #selector(toggleRespect), keyEquivalent: "")
        respect.target = self; respect.state = preferences.respectReduceMotion ? .on : .off; menu.addItem(respect)
        let demo = NSMenuItem(title: "DEMO de confete em loop (sem consulta)", action: #selector(demoConfetti), keyEquivalent: "")
        demo.target = self; menu.addItem(demo)
        let animated = NSMenuItem(title: "DEMO animada (exceção somente neste teste)", action: #selector(demoMotionConfetti), keyEquivalent: "")
        animated.target = self; menu.addItem(animated)
        let refresh = NSMenuItem(title: "Atualizar agora", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self; refresh.isEnabled = !policy.busy && !policy.sleeping; menu.addItem(refresh)
        let quit = NSMenuItem(title: "Sair", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
    }
    func historyMenu() -> NSMenu {
        let menu = NSMenu()
        let history = detector.state.history + claudeDetector.state.history
        guard !history.isEmpty else { menu.addItem(info("Nenhum reset real registrado")); return menu }
        menu.addItem(info("Intervalos entre detecções, não instantes exatos de reset"))
        menu.addItem(info("Períodos offline/recovery podem deixar eventos sem registro"))
        for (key, group) in Dictionary(grouping: history, by: \.groupKey).sorted(by: { $0.key < $1.key }) {
            let ordered = group.sorted { $0.detectedAt < $1.detectedAt }; let first = ordered[0]
            let provider = (first.provider ?? "codex") == "claude" ? "Claude" : "Codex"
            let parent = NSMenuItem(title: "\(provider) · \(first.bucketID) · conta \(first.identityFingerprint.prefix(8)) · \(durationLabel(first.durationMinutes))", action: nil, keyEquivalent: "")
            let sub = NSMenu(); let intervals = detectionIntervals(ordered)
            if let last = intervals.last {
                sub.addItem(info("Último intervalo detectado: \(intervalLabel(last))"))
                sub.addItem(info("Média (\(intervals.count) intervalos): \(intervalLabel(intervals.reduce(0,+) / Double(intervals.count)))"))
            } else { sub.addItem(info("Estatística pendente: requer ≥2 eventos reais")) }
            for (index, record) in ordered.enumerated().reversed() {
                let row = NSMenuItem(title: "Detectado \(localDate(record.detectedAt))\(record.acknowledgedAt == nil ? " · pendente" : " · reconhecido")", action: nil, keyEquivalent: "")
                let detail = NSMenu()
                detail.addItem(info("Próximo reset informado: \(localDate(Date(timeIntervalSince1970: record.serviceResetAt)))"))
                detail.addItem(info("Reset anterior informado: \(localDate(Date(timeIntervalSince1970: record.previousServiceResetAt)))"))
                detail.addItem(info("Uso: \(percentLabel(record.previousUsedPercent)) → \(percentLabel(record.usedPercent))"))
                if index > 0 { detail.addItem(info("Intervalo desde detecção anterior: \(intervalLabel(record.detectedAt.timeIntervalSince(ordered[index-1].detectedAt)))")) }
                if let ack = record.acknowledgedAt { detail.addItem(info("Reconhecido: \(localDate(ack))")) }
                row.submenu = detail; sub.addItem(row)
            }
            _ = key; parent.submenu = sub; menu.addItem(parent)
        }
        return menu
    }
    func reconcileCelebration() {
        let pending = realPending
        guard !activity.suspended, demoPending || (!pending.isEmpty && journalHealthy) else { confetti.close(); shownKey = nil; return }
        // Pending real events are displayed only with a fresh verified account; stale data keeps the badge/history.
        if !demoPending && pending.allSatisfy({ r in
            let value = (r.provider ?? "codex") == "claude" ? claudeSnapshot : snapshot
            return stale(value, error: (r.provider ?? "codex") == "claude" ? claudeError : errorText)
        }) { confetti.close(); shownKey = nil; return }
        let motion = preferences.loopEnabled && (demoMotion && demoPending || !preferences.respectReduceMotion || !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let key = (demoPending ? "demo" : pending.map(\.id).sorted().joined(separator: ",")) + ":\(motion)"
        guard shownKey != key else { return }
        shownKey = key
        let providers = Set(pending.map { ($0.provider ?? "codex") == "claude" ? "Claude" : "Codex" }).sorted().joined(separator: " + ")
        confetti.showLoop(message: demoPending ? "DEMO separada. Sem quota/histórico real. Clique em Codex na barra para dispensar." : "\(providers): \(pending.count) reset(s) detectado(s). Clique em Codex na barra para reconhecer.", demo: demoPending, motion: motion, display: celebrationDisplay, renderOffscreen: celebrationRenderOffscreen)
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
    @objc func toggleLoop() { preferences.loopEnabled.toggle(); savePreferences(); shownKey = nil; updateUI() }
    @objc func toggleRespect() { preferences.respectReduceMotion.toggle(); savePreferences(); shownKey = nil; updateUI() }
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
            "zaiManualRequests":zaiManualRequests,"zaiAuthStatus":zaiReading?.status ?? "pending","zaiBusy":zaiBusy,
            "zaiRefreshMessage":zaiRefreshMessage as Any? ?? NSNull(),"zaiReads":zaiReads,
            "failures":policy.failures,"busy":policy.busy,"sleeping":policy.sleeping,
            "realHistoryCount":detector.state.history.count+claudeDetector.state.history.count]
        if let data = try? JSONSerialization.data(withJSONObject:raw,options:[.sortedKeys]) { writePrivate(data,to:metricsFile) }
    }
    func schedule() {
        timer?.invalidate(); timer = nil; guard !policy.sleeping else { return }
        let next = Timer(timeInterval: policy.delay(), repeats: false) { [weak self] _ in self?.refresh() }
        next.tolerance = 2; RunLoop.main.add(next, forMode: .common); timer = next
    }
    func readClaudeCache() {
        claudeCacheReads += 1
        let provider = ClaudeCacheProvider(path: cacheDirectory.appendingPathComponent("claude-statusline.json"))
        do {
            let current = try provider.read()
            if current.queriedAt > (claudeSnapshot?.queriedAt ?? .distantPast) { _ = claudeDetector.accept(current); _ = saveStates() }
            claudeSnapshot = current; claudeError = nil
        } catch { claudeError = "Aguardando dados do uso normal Claude; cache indisponível"; claudeDetector.interrupt() }
    }
    func refreshClaude() {
        guard !activity.suspended else { return }
        readClaudeCache(); updateUI()
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
        zaiManualCooldown = started.addingTimeInterval(60)
        zaiAutomaticAfter = started.addingTimeInterval(900)
        saveZaiSchedule()
        let request = zaiClientFactory()
        zaiClient = request; updateUI(); writeMetrics()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try request.read() }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.zaiBusy = false; self.zaiRequestIsManual = false; self.zaiClient = nil
                guard !self.activity.suspended else {
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
    @objc func configureZai() {
        guard !Runtime.isTest, !zaiBusy else { return }
        let alert = NSAlert(); alert.messageText = "Chave Z.ai"
        alert.informativeText = "A chave será salva no Keychain deste Mac e usada somente para consultar quotas. Não coloque a chave no chat ou em arquivos de configuração."
        let field = NSSecureTextField(frame:NSRect(x:0,y:0,width:340,height:24))
        alert.accessoryView = field; alert.addButton(withTitle:"Salvar"); alert.addButton(withTitle:"Cancelar")
        NSApp.activate(ignoringOtherApps:true)
        guard alert.runModal() == .alertFirstButtonReturn else { field.stringValue = ""; return }
        defer { field.stringValue = "" }
        do {
            try KeychainStore.save(field.stringValue)
            clearZaiCache(); zaiManualCooldown = .distantPast; refreshZaiNow()
        } catch { zaiError = (error as? QuotaError)?.text ?? "Falha ao salvar no Keychain"; updateUI() }
    }
    @objc func removeZai() {
        guard !Runtime.isTest, !zaiBusy else { return }
        let alert = NSAlert(); alert.messageText = "Remover a chave Z.ai deste Mac?"
        alert.informativeText = "Isso remove somente o item do PlanMeter no Keychain. Não revoga a chave na Z.ai."
        alert.addButton(withTitle:"Cancelar"); alert.addButton(withTitle:"Remover")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try KeychainStore.remove(); clearZaiCache(); updateUI() }
        catch { zaiError = "Não foi possível remover a chave do Keychain"; updateUI() }
    }
    func clearZaiCache() {
        zaiSnapshot = nil; zaiReading = nil; zaiRefreshMessage = nil
        zaiManualCooldown = .distantPast; zaiAutomaticAfter = .distantPast
        zaiError = "Configure a chave Z.ai no menu para consultar quotas"
        try? FileManager.default.removeItem(at:zaiFile)
        try? FileManager.default.removeItem(at:zaiCooldownFile)
    }
    @objc func openClaudeUsage() { if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) } }
    func startClaudeTimer() {
        claudeTimer?.invalidate(); claudeTimer = nil
        guard !activity.suspended else { return }
        refreshClaude()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshClaude(); self?.updateUI(); self?.writeMetrics()
        }
        timer.tolerance = 2; RunLoop.main.add(timer, forMode: .common); claudeTimer = timer
    }
    @objc func manualRefresh() { refreshClaude(); refresh(); refreshZaiNow() }
    func refresh() {
        guard policy.begin() else { return }
        timer?.invalidate(); timer = nil; attempts += 1
        let started = Date(), request = AppServerClient(binary: binary); client = request; updateUI(); writeMetrics()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try request.read() }; let elapsed = Date().timeIntervalSince(started)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.quotaRequests += request.quotaRequests; self.lastElapsed = elapsed; self.client = nil
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
        if activity.suspended {
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
        timer?.invalidate(); claudeTimer?.invalidate(); zaiTimer?.invalidate(); countdownTimer?.invalidate(); confetti.close(); client?.stopForExit(); zaiClient?.cancel()
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        for o in distributedObservers { DistributedNotificationCenter.default().removeObserver(o) }
    }
}
@main struct Launcher {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
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
        if CommandLine.arguments.contains("--self-test") { runTests(); runResetTests(); runHistoryTests(); runZaiTests(); runLocalClientTests(); return }
        if CommandLine.arguments.contains("--confetti-self-test") { runConfettiTests(); return }
        if CommandLine.arguments.contains("--loop-self-test") { runLoopTests(); return }
        if CommandLine.arguments.contains("--ui-self-test") {
            guard let i = CommandLine.arguments.firstIndex(of: "--codex"), i+1 < CommandLine.arguments.count else { exit(2) }
            runUITests(binary: CommandLine.arguments[i+1]); runZaiUITests(); runZaiRefreshTests(); return
        }
        if CommandLine.arguments.contains("--demo-confetti") || CommandLine.arguments.contains("--demo-confetti-motion") {
            // One request to the running app: no second persistent demo app/process or model call.
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pcarielo.planmeter").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else { print("Abra PlanMeter primeiro, depois use a DEMO no menu."); exit(1) }
            DistributedNotificationCenter.default().postNotificationName(MenuApp.demoRequest, object: "io.github.pcarielo.planmeter", userInfo: ["motion": CommandLine.arguments.contains("--demo-confetti-motion")], deliverImmediately: true)
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
