import Foundation

// Quotas are read from the unmodified official client's /usage screen.
// PlanMeter never reads, stores or forwards the client's subscription token.
final class ClaudeQuotaClient {
    typealias Transport=() throws -> ClaudeQuotaReading
    let transport:Transport?
    let allowTrust:Bool
    private let lock=NSLock()
    private var probe:ClaudeCLIProbe?
    private var cancelled=false
    init(transport:Transport?=nil,allowTrust:Bool=false){self.transport=transport;self.allowTrust=allowTrust}
    static var directory:URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PlanMeter/ClaudeProbe",isDirectory:true)
    }
    func cancel(){lock.lock();cancelled=true;let probe=probe;lock.unlock();probe?.cancel()}
    func read(now:Date=Date())throws->ClaudeQuotaReading {
        lock.lock();let stopped=cancelled;lock.unlock()
        guard !stopped else{throw QuotaError.message("Consulta Claude cancelada")}
        if let transport=transport {return try transport()}
        guard !Runtime.isTest else{throw QuotaError.message("Cliente real bloqueado em testes")}
        let discovery=HarnessDiscovery(home:FileManager.default.homeDirectoryForCurrentUser.path,environment:ProcessInfo.processInfo.environment)
        guard let binary=discovery.resolve(.claude) else {
            var snapshot=QuotaSnapshot(queriedAt:now,windows:[]);snapshot.provider="claude"
            return ClaudeQuotaReading(snapshot:snapshot,status:"client_unavailable",nextAttemptAt:now.addingTimeInterval(60))
        }
        let reader=ClaudeCLIProbe(binary:binary,directory:Self.directory)
        lock.lock();if cancelled {lock.unlock();throw QuotaError.message("Consulta Claude cancelada")};probe=reader;lock.unlock()
        defer{lock.lock();probe=nil;lock.unlock()}
        return try reader.read(allowTrust:allowTrust)
    }
}
