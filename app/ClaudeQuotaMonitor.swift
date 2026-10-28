import Foundation

private struct ClaudeQuotaSettings:Codable {let consent:Bool;var method:String?="official-cli"}
final class ClaudeQuotaMonitor {
    var directory=FileManager.default.temporaryDirectory
    var onChange:()->Void={}
    var audit:(AuditAction,AuditOutcome)->Void={_,_ in}
    var clientFactory:(()->ClaudeQuotaClient)?
    private(set) var enabled=false
    private(set) var busy=false
    private(set) var lastStatus="pending"
    private(set) var message=""
    private(set) var requests=0
    private var lastGood:QuotaSnapshot?
    private var paused=false
    private var client:ClaudeQuotaClient?
    private var timer:Timer?
    private var generation=0
    private var manualAfter=Date.distantPast
    private var automaticAfter=Date.distantPast
    var interval:TimeInterval=900
    func setRefreshInterval(_ value:TimeInterval) {
        let old=interval;interval=value;automaticAfter=max(manualAfter,automaticAfter.addingTimeInterval(value-old));saveSchedule()
    }
    var snapshot:QuotaSnapshot? {["auth_unavailable","unauthorized"].contains(lastStatus) ? nil : lastGood}
    var error:String? {lastStatus=="ok" ? nil : (message.isEmpty ? claudeQuotaStatus(lastStatus) : message)}
    @discardableResult private func save<T:Encodable>(_ value:T,_ name:String)->Bool {
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let file=directory.appendingPathComponent(name);try JSONEncoder().encode(value).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path);return true
        } catch {message="Não foi possível salvar o estado da consulta Claude.";return false}
    }
    private func saveSchedule(){_ = save(["manual":manualAfter,"automatic":automaticAfter],"claude-quota-schedule.json")}
    func load() {
        if let data=try? Data(contentsOf:directory.appendingPathComponent("claude-quota-settings.json")),let value=try? JSONDecoder().decode(ClaudeQuotaSettings.self,from:data) {enabled=value.consent && value.method=="official-cli"}
        if let data=try? Data(contentsOf:directory.appendingPathComponent("claude-quota.json")),let value=try? JSONDecoder().decode(ClaudeQuotaReading.self,from:data),value.status=="ok",value.snapshot.sourceHost=="claude-code-cli" {lastGood=value.snapshot}
        if let data=try? Data(contentsOf:directory.appendingPathComponent("claude-quota-schedule.json")),let values=try? JSONDecoder().decode([String:Date].self,from:data) {
            let max=Date().addingTimeInterval(86400)
            if let value=values["manual"],value<=max {manualAfter=value}
            if let value=values["automatic"],value<=max {automaticAfter=value}
        }
    }
    @discardableResult func setConsent(_ consent:Bool)->Bool {
        guard save(ClaudeQuotaSettings(consent:consent),"claude-quota-settings.json") else{return false}
        stop();enabled=consent
        // An unavailable credential did not consume provider quota; explicit reauthorization can retry.
        if consent && lastStatus=="auth_unavailable" {manualAfter = .distantPast;automaticAfter = .distantPast;saveSchedule()}
        onChange();return true
    }
    func start() {
        timer?.invalidate();timer=nil
        guard enabled,!paused else{return}
        refresh(manual:false)
        let next=Timer(timeInterval:30,repeats:true){[weak self] _ in self?.refresh(manual:false)}
        RunLoop.main.add(next,forMode:.common);timer=next
    }
    func pause(_ value:Bool){paused=value;if value {stop()} else{start()}}
    func stop(){generation += 1;client?.cancel();client=nil;busy=false;timer?.invalidate();timer=nil}
    func refresh(manual:Bool,setup:Bool=false) {
        guard enabled,!paused,!busy else{return}
        let now=Date()
        guard now>=manualAfter else {if manual {message="Claude: aguarde \(max(1,Int(ceil(manualAfter.timeIntervalSince(now)))))s para consultar.";onChange()};return}
        guard manual || now>=automaticAfter else{return}
        manualAfter=now.addingTimeInterval(60);automaticAfter=now.addingTimeInterval(interval);saveSchedule()
        busy=true;requests += 1;generation += 1;let token=generation
        let request=clientFactory?() ?? ClaudeQuotaClient(allowTrust:setup && manual)
        client=request;message="Claude: consultando quota…";audit(.query,.started);onChange()
        DispatchQueue.global(qos:.utility).async {
            let result=Result{try request.read()}
            DispatchQueue.main.async {[weak self] in
                guard let self=self,self.generation==token else{return}
                self.busy=false;self.client=nil
                switch result {
                case .success(let value):
                    self.lastStatus=value.status;self.manualAfter=max(self.manualAfter,value.nextAttemptAt)
                    self.automaticAfter=max(self.automaticAfter,self.manualAfter)
                    if value.status=="ok" {self.lastGood=value.snapshot;self.save(value,"claude-quota.json")}
                    self.message=claudeQuotaStatus(value.status);self.audit(.query,value.status=="ok" ? .success : .failure)
                case .failure(let error):self.lastStatus="unavailable";self.message=(error as? QuotaError)?.text ?? claudeQuotaStatus("unavailable");self.audit(.query,.failure)
                }
                self.saveSchedule();self.onChange()
            }
        }
    }
}
