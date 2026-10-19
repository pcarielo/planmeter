import Foundation

struct GrokReading: Codable {
    let snapshot: QuotaSnapshot
    let status: String
    let nextAttemptAt: Date
}
struct GrokSchedule: Codable { var manual: Date; var automatic: Date }
struct GrokCache: Codable { let reading: GrokReading?; let lastGood: QuotaSnapshot? }
enum GrokEnvironment {
    static var isTest: Bool { CommandLine.arguments.contains{$0.hasSuffix("-self-test")} }
    static func binary() -> String {
        if isTest {return "/nonexistent/planmeter-test-grok"}
        let home=FileManager.default.homeDirectoryForCurrentUser.path
        let paths=[home+"/.grok/bin/grok",home+"/.local/bin/grok","/opt/homebrew/bin/grok","/usr/local/bin/grok"]
        return paths.first{FileManager.default.isExecutableFile(atPath:$0)} ?? "/nonexistent/planmeter-grok"
    }
}
func grokStatus(_ status:String) -> String {
    switch status {
    case "cli_unavailable":return "Grok Build não encontrado; instale o cliente oficial"
    case "pending":return "Grok: aguardando a primeira consulta"
    case "ok":return ""
    default:return "Grok: consulta indisponível; confira o login e a rede pelo cliente oficial"
    }
}
func parseGrok(_ result:[String:Any],now:Date=Date()) throws -> GrokReading {
    guard let config=result["config"] as? [String:Any],let used=number(config["creditUsagePercent"]),(0...100).contains(used) else {throw QuotaError.message("Quota Grok não informada")}
    let period=config["currentPeriod"] as? [String:Any] ?? [:]
    let type=period["type"] as? String
    let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    let reset=(period["end"] as? String).flatMap{formatter.date(from:$0) ?? ISO8601DateFormatter().date(from:$0)}?.timeIntervalSince1970
    let unified=config["isUnifiedBillingUser"] as? Bool == true
    let label=type=="USAGE_PERIOD_TYPE_WEEKLY" ? (unified ? "Semanal compartilhado" : "Semanal") : type=="USAGE_PERIOD_TYPE_MONTHLY" ? "Mensal" : "Assinatura"
    var snapshot=QuotaSnapshot(queriedAt:now,windows:[QuotaWindow(name:label,remaining:100-used,durationMinutes:type=="USAGE_PERIOD_TYPE_WEEKLY" ? 10080 : nil,reset:reset)])
    snapshot.provider="grok";snapshot.bucketID=unified ? "grok:unified" : "grok:subscription"
    return GrokReading(snapshot:snapshot,status:"ok",nextAttemptAt:now.addingTimeInterval(60))
}
