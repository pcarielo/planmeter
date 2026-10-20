import AppKit

final class KimiCredentialField: NSSecureTextField {
    // Keep paste inside the secure editor, including in a menu-only application.
    var pasteText: () -> String? = { NSPasteboard.general.string(forType:.string) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers=event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command, let editor=currentEditor() else {return super.performKeyEquivalent(with:event)}
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v":
            if let text=pasteText() { (editor as? NSTextView)?.insertText(text,replacementRange:editor.selectedRange) }
            return true
        case "a": editor.selectAll(nil);return true
        default:return super.performKeyEquivalent(with:event)
        }
    }
}

final class KimiMonitor: NSObject {
    var cacheDirectory = FileManager.default.temporaryDirectory
    var onChange: () -> Void = {}
    var clientFactory: () -> KimiClient = { KimiClient() }
    var enabled = !KimiEnvironment.isTest
    private(set) var reading: KimiReading?
    private(set) var snapshot: QuotaSnapshot?
    private(set) var busy = false
    private(set) var requests = 0
    private(set) var message: String?
    private(set) var paused = false
    var schedule = KimiSchedule(manual:.distantPast,automatic:.distantPast)
    private var timer: Timer?, client: KimiClient?, generation = 0
    var errorText: String? {
        guard let reading = reading else { return kimiStatus("auth_unavailable") }
        return reading.status == "ok" ? nil : kimiStatus(reading.status)
    }
    var stale: Bool { errorText != nil || snapshot == nil || Date().timeIntervalSince(snapshot!.queriedAt) > 960 }
    private var cacheFile: URL { cacheDirectory.appendingPathComponent("kimi-quota.json") }
    private var scheduleFile: URL { cacheDirectory.appendingPathComponent("kimi-schedule.json") }
    @discardableResult private func save<T:Encodable>(_ value: T, to path: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at:cacheDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(value).write(to:path,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            return true
        } catch { message = "Kimi: não foi possível salvar o estado local"; return false }
    }
    func load() {
        if let data = try? Data(contentsOf:cacheFile),data.count <= 65536, let cached = try? JSONDecoder().decode(KimiCache.self,from:data) {
            reading = cached.reading; snapshot = cached.lastGood
        }
        if let data = try? Data(contentsOf:scheduleFile), let cached = try? JSONDecoder().decode(KimiSchedule.self,from:data) {
            let maxDate=Date().addingTimeInterval(86400)
            if cached.manual <= maxDate { schedule.manual = cached.manual }
            if cached.automatic <= maxDate { schedule.automatic = cached.automatic }
        }
    }
    func start() {
        timer?.invalidate(); timer=nil
        guard enabled, !paused else { return }
        refresh(manual:false)
        let next=Timer(timeInterval:30,repeats:true){[weak self] _ in self?.refresh(manual:false)}
        next.tolerance=2;RunLoop.main.add(next,forMode:.common);timer=next
    }
    func setPaused(_ value: Bool) {
        paused=value
        if value {
            if busy {message="Kimi: consulta interrompida pela pausa"}
            generation += 1;client?.cancel();client=nil;busy=false;timer?.invalidate();timer=nil;onChange()
        } else {start()}
    }
    func stop() {timer?.invalidate();timer=nil;generation += 1;client?.cancel();client=nil;busy=false}
    @objc func refreshNow() { refresh(manual:true) }
    func refresh(manual: Bool) {
        guard enabled,!paused else { return }
        if busy { if manual {message="Kimi: uma consulta já está em andamento";onChange()};return }
        let now=Date()
        if now < schedule.manual {
            if manual {message="Kimi: aguarde \(max(1,Int(ceil(schedule.manual.timeIntervalSince(now)))))s para consultar";onChange()}
            return
        }
        guard manual || now >= schedule.automatic else {return}
        schedule=KimiSchedule(manual:now.addingTimeInterval(60),automatic:now.addingTimeInterval(900))
        guard save(schedule,to:scheduleFile) else { onChange();return }
        busy=true;requests += 1;generation += 1;let token=generation
        message="Kimi: consultando quota…"
        let request=clientFactory();client=request;onChange()
        DispatchQueue.global(qos:.utility).async {
            let result=Result {try request.read()}
            DispatchQueue.main.async { [weak self] in
                guard let self=self,self.generation==token else {return}
                self.busy=false;self.client=nil
                switch result {
                case .success(let value):
                    self.reading=value
                    self.schedule.manual=max(self.schedule.manual,value.nextAttemptAt)
                    self.schedule.automatic=max(self.schedule.automatic,self.schedule.manual)
                    if value.status=="ok" {self.snapshot=value.snapshot;self.message="Kimi: coleta concluída às " + localDate(value.snapshot.queriedAt)}
                    else {self.message=kimiStatus(value.status)}
                case .failure:
                    var empty=QuotaSnapshot(queriedAt:now,windows:[]);empty.provider="kimi"
                    self.reading=KimiReading(snapshot:empty,status:"unavailable",nextAttemptAt:self.schedule.manual)
                    self.message="Kimi: consulta falhou; última quota preservada"
                }
                self.save(KimiCache(reading:self.reading,lastGood:self.snapshot),to:self.cacheFile)
                self.save(self.schedule,to:self.scheduleFile);self.onChange()
                if manual, self.reading?.status != "ok" { self.showFeedback(self.message ?? "Kimi: consulta indisponível") }
            }
        }
    }
    func prepareAfterAuthorization() {
        // Missing credentials never reached the provider, so no provider cooldown was spent.
        guard reading?.status=="auth_unavailable" else{return}
        schedule=KimiSchedule(manual:.distantPast,automatic:.distantPast)
        save(schedule,to:scheduleFile)
    }
    @objc func authorizeAccess() {
        guard !KimiEnvironment.isTest,!busy else{return}
        if KimiKeychain.authorize() {prepareAfterAuthorization();message="Kimi: acesso autorizado nesta execução";onChange();refreshNow()}
        else {message="Kimi: acesso não autorizado. Use Acessos para tentar novamente.";onChange();showFeedback(message!)}
    }
    @objc func configure() {
        guard !KimiEnvironment.isTest,!busy else {return}
        let alert=NSAlert();alert.messageText="Chave do Kimi Code / Coding Plan"
        alert.informativeText="Use a chave emitida no console Kimi Code. Ela ficará no Keychain deste Mac e será usada somente para consultar quotas. O OAuth de outros aplicativos não será alterado."
        let field=KimiCredentialField(frame:NSRect(x:0,y:0,width:360,height:24));alert.accessoryView=field
        alert.addButton(withTitle:"Salvar");alert.addButton(withTitle:"Cancelar")
        field.placeholderString="Cole a chave aqui (⌘V)"
        alert.window.initialFirstResponder=field
        alert.window.makeFirstResponder(field)
        NSApp.activate(ignoringOtherApps:true)
        defer {field.stringValue=""}
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        do {try KimiKeychain.save(field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines));clear();refreshNow()}
        catch {
            message=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
                ? "Kimi: o campo está vazio. Nenhuma chave foi salva."
                : "Kimi: confira se a chave é válida e se o Keychain permite salvá-la"
            onChange();showFeedback(message!)
        }
    }
    func showFeedback(_ text: String) {
        guard !KimiEnvironment.isTest else{return}
        let alert=NSAlert();alert.messageText="Kimi Code";alert.informativeText=text
        alert.addButton(withTitle:"OK");NSApp.activate(ignoringOtherApps:true);alert.runModal()
    }
    @objc func removeKey() {
        guard !KimiEnvironment.isTest,!busy else{return}
        let alert=NSAlert();alert.messageText="Remover a chave Kimi deste monitor?"
        alert.informativeText="Isso remove apenas o item deste aplicativo no Keychain. Não revoga a chave no provedor nem altera o OAuth."
        alert.addButton(withTitle:"Cancelar");alert.addButton(withTitle:"Remover")
        guard alert.runModal() == .alertSecondButtonReturn else{return}
        do {try KimiKeychain.remove();clear();message="Kimi: chave removida deste monitor";onChange()}
        catch {message="Kimi: não foi possível remover a chave";onChange()}
    }
    func clear() {
        client?.cancel();client=nil;busy=false
        generation += 1;reading=nil;snapshot=nil;message=nil;schedule=KimiSchedule(manual:.distantPast,automatic:.distantPast)
        try? FileManager.default.removeItem(at:cacheFile);try? FileManager.default.removeItem(at:scheduleFile)
    }
}
