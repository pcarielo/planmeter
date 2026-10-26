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
    let unified=config["isUnifiedBillingUser"] as? Bool
    let label=type=="USAGE_PERIOD_TYPE_WEEKLY" ? "Semanal" : type=="USAGE_PERIOD_TYPE_MONTHLY" ? "Mensal" : "Uso incluído"
    var snapshot=QuotaSnapshot(queriedAt:now,windows:[QuotaWindow(name:label,remaining:100-used,durationMinutes:type=="USAGE_PERIOD_TYPE_WEEKLY" ? 10080 : nil,reset:reset)])
    if let text=period["start"] as? String,let start=formatter.date(from:text) ?? ISO8601DateFormatter().date(from:text) {
        var window=snapshot.windows[0];window.startedAt=start.timeIntervalSince1970
        var updated=QuotaSnapshot(queriedAt:snapshot.queriedAt,windows:[window]);updated.provider=snapshot.provider;updated.bucketID=snapshot.bucketID;snapshot=updated
    }
    snapshot.provider="grok";snapshot.bucketID=unified == true ? "grok:unified" : unified == false ? "grok:build" : "grok:unknown"
    return GrokReading(snapshot:snapshot,status:"ok",nextAttemptAt:now.addingTimeInterval(60))
}

func grokMeasurementNote(_ snapshot:QuotaSnapshot?) -> String {
    switch snapshot?.bucketID {
    case "grok:unified":return "Créditos unificados"
    case "grok:build":return "Créditos do Grok Build"
    default:return "Tipo de crédito não informado"
    }
}
func grokMeasurementDescription(_ snapshot:QuotaSnapshot?) -> String {
    switch snapshot?.bucketID {
    case "grok:unified":return "Limite de uso incluído, unificado entre os produtos elegíveis da assinatura."
    case "grok:build":return "Limite de créditos incluídos do Grok Build, sem somar cotas de outros produtos."
    default:return "Uso incluído informado pelo Grok Build; a resposta não identifica se a cota é unificada."
    }
}
func grokMeasurementExplanation(_ snapshot:QuotaSnapshot?) -> String {
    grokMeasurementDescription(snapshot) + "\n\nMedimos o saldo de créditos incluídos na assinatura para o período informado. Créditos adicionais comprados, saldo pré-pago e consumo adicional cobrado à parte não entram nesse percentual.\n\nQuando os créditos são unificados, os recursos elegíveis do plano consomem o mesmo saldo. O provedor define essa cobertura: recursos do Grok e, quando incluídos no plano, Grok Bot e uso elegível do Cursor. A consulta retorna o total agregado; não permite dividir o consumo por recurso nem confirmar quais benefícios estão habilitados na conta.\n\nQuando o provedor identifica créditos específicos do Grok Build, medimos somente essa cota de programação. Não somamos cotas de Chat, Imagine, Voice, Bot, Cursor ou outros produtos. Se o tipo de crédito não for informado, não presumimos nenhuma dessas modalidades."
}
