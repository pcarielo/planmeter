import Foundation

struct ClaudeQuotaReading:Codable {
    let snapshot:QuotaSnapshot
    let status:String
    let nextAttemptAt:Date
}
func claudeQuotaStatus(_ status:String)->String {
    switch status {
    case "ok":return "Quota atualizada pelo Claude Code"
    case "setup_required":return "Confirme a pasta de consulta no Claude Code para habilitar Atualizar."
    case "client_unavailable":return "Instale o Claude Code ou configure PLANMETER_CLAUDE_PATH."
    case "auth_unavailable":return "Autorize a consulta de quota em Contas → Claude Code."
    case "unauthorized":return "O login Claude precisa ser renovado no cliente oficial."
    case "stale":return "O Claude exibiu dados anteriores; aguardando uma leitura atualizada."
    case "rate_limited":return "O Claude limitou as consultas. Aguarde o prazo informado."
    default:return "Não foi possível consultar o Claude; última leitura preservada."
    }
}
func runClaudeQuotaMonitorTests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL Claude quota monitor: \(label)")};count += 1}
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let monitor=ClaudeQuotaMonitor();monitor.directory=root
    defer{monitor.stop();try? FileManager.default.removeItem(at:root)}
    var calls=0
    monitor.clientFactory={ClaudeQuotaClient(transport:{
        calls += 1
        return try ClaudeCLIUsageParser.parse("Current session\n9% used\nCurrent week (all models)\n51% used")
    })}
    monitor.refresh(manual:true);check(calls==0,"no active query before consent")
    check(monitor.setConsent(true),"consent stored in fixture directory")
    monitor.refresh(manual:true)
    let end=Date().addingTimeInterval(5);while monitor.busy && Date()<end {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
    check(calls==1 && monitor.snapshot?.remaining==49,"manual update actually reaches collector")
    let observed=monitor.snapshot?.queriedAt
    monitor.refresh(manual:true)
    check(calls==1 && monitor.snapshot?.queriedAt==observed && monitor.message.contains("aguarde"),"throttle never fabricates fresh timestamp")
    let restored=ClaudeQuotaMonitor();restored.directory=root;restored.clientFactory=monitor.clientFactory;restored.load();restored.refresh(manual:true)
    check(restored.requests==0,"cooldown survives restart")
    restored.stop();_=monitor.setConsent(false);monitor.refresh(manual:true)
    check(calls==1,"disabling consent stops queries")
    let expired=["manual":Date.distantPast,"automatic":Date.distantPast]
    try! JSONEncoder().encode(expired).write(to:root.appendingPathComponent("claude-quota-schedule.json"))
    let failed=ClaudeQuotaMonitor();failed.directory=root;failed.load();_=failed.setConsent(true)
    failed.clientFactory={ClaudeQuotaClient(transport:{ClaudeQuotaReading(snapshot:QuotaSnapshot(queriedAt:Date(),windows:[]),status:"stale",nextAttemptAt:Date().addingTimeInterval(60))})}
    failed.refresh(manual:true)
    let limit=Date().addingTimeInterval(5);while failed.busy && Date()<limit {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
    check(failed.snapshot?.queriedAt==observed && failed.lastStatus=="stale","failed official refresh preserves original observation time")
    failed.stop()
    print("PASS Claude active quota monitor: \(count) checks; no Keychain or network")
}
