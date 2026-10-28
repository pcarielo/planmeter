import AppKit

final class GrokMonitor: NSObject {
    var cacheDirectory = FileManager.default.temporaryDirectory
    var onChange: () -> Void = {}
    var clientFactory: () -> GrokClient = { GrokClient() }
    var enabled = !GrokEnvironment.isTest
    private(set) var reading: GrokReading?
    private(set) var snapshot: QuotaSnapshot?
    private(set) var busy = false
    private(set) var requests = 0
    private(set) var message: String?
    private(set) var paused = false
    var schedule = GrokSchedule(manual:.distantPast,automatic:.distantPast)
    var automaticInterval:TimeInterval=900
    func setRefreshInterval(_ value:TimeInterval) {
        let previous=automaticInterval;automaticInterval=value
        schedule.automatic=max(schedule.manual,schedule.automatic.addingTimeInterval(value-previous))
        save(schedule,to:scheduleFile)
    }
    var audit:(AuditAction,AuditOutcome)->Void={_,_ in}
    private var timer: Timer?, client: GrokClient?, generation = 0
    var errorText: String? {
        guard let reading = reading else { return grokStatus("pending") }
        return reading.status == "ok" ? nil : grokStatus(reading.status)
    }
    var stale: Bool { errorText != nil || snapshot == nil || Date().timeIntervalSince(snapshot!.queriedAt) > automaticInterval+60 }
    private var cacheFile: URL { cacheDirectory.appendingPathComponent("grok-quota.json") }
    private var scheduleFile: URL { cacheDirectory.appendingPathComponent("grok-schedule.json") }
    @discardableResult private func save<T:Encodable>(_ value: T, to path: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at:cacheDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(value).write(to:path,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
            return true
        } catch { message = "Grok: não foi possível salvar o estado local"; return false }
    }
    func load() {
        if let data = try? Data(contentsOf:cacheFile),data.count <= 65536, let cached = try? JSONDecoder().decode(GrokCache.self,from:data) {
            reading = cached.reading; snapshot = cached.lastGood
        }
        if let data = try? Data(contentsOf:scheduleFile), let cached = try? JSONDecoder().decode(GrokSchedule.self,from:data) {
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
            if busy {message="Grok: consulta interrompida pela pausa"}
            generation += 1;client?.cancel();client=nil;busy=false;timer?.invalidate();timer=nil;onChange()
        } else {start()}
    }
    func stop() {timer?.invalidate();timer=nil;generation += 1;client?.stopForExit();client=nil;busy=false}
    @objc func refreshNow() { refresh(manual:true) }
    func refresh(manual: Bool) {
        guard enabled,!paused else { return }
        if busy { if manual {message="Grok: uma consulta já está em andamento";onChange()};return }
        let now=Date()
        if now < schedule.manual {
            if manual {message="Grok: aguarde \(max(1,Int(ceil(schedule.manual.timeIntervalSince(now)))))s para consultar";onChange()}
            return
        }
        guard manual || now >= schedule.automatic else {return}
        schedule=GrokSchedule(manual:now.addingTimeInterval(60),automatic:now.addingTimeInterval(automaticInterval))
        guard save(schedule,to:scheduleFile) else { onChange();return }
        busy=true;requests += 1;generation += 1;let token=generation
        message="Grok: consultando quota…"
        let request=clientFactory();client=request;audit(.query,.started);onChange()
        DispatchQueue.global(qos:.utility).async {
            let result=Result {try request.read()}
            DispatchQueue.main.async { [weak self] in
                guard let self=self,self.generation==token else {return}
                self.busy=false;self.client=nil
                self.audit(.query,(try? result.get()).map{$0.status == "ok"} == true ? .success : .failure)
                switch result {
                case .success(let value):
                    self.reading=value
                    self.schedule.manual=max(self.schedule.manual,value.nextAttemptAt)
                    self.schedule.automatic=max(self.schedule.automatic,self.schedule.manual)
                    if value.status=="ok" {self.snapshot=value.snapshot;self.message="Grok: coleta concluída às " + localDate(value.snapshot.queriedAt)}
                    else {self.message=grokStatus(value.status)}
                case .failure:
                    var empty=QuotaSnapshot(queriedAt:now,windows:[]);empty.provider="grok"
                    self.reading=GrokReading(snapshot:empty,status:"unavailable",nextAttemptAt:self.schedule.manual)
                    self.message="Grok: consulta falhou; última quota preservada"
                }
                self.save(GrokCache(reading:self.reading,lastGood:self.snapshot),to:self.cacheFile)
                self.save(self.schedule,to:self.scheduleFile);self.onChange()
                if manual, self.reading?.status != "ok" { self.showFeedback(self.message ?? "Grok: consulta indisponível") }
            }
        }
    }
    func showFeedback(_ text:String) {
        guard !GrokEnvironment.isTest else{return}
        let alert=NSAlert();alert.messageText="Grok";alert.informativeText=text
        alert.addButton(withTitle:"OK");NSApp.activate(ignoringOtherApps:true);alert.runModal()
    }
}
