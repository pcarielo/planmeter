import Foundation

struct KimiReading: Codable {
    let snapshot: QuotaSnapshot
    let status: String
    let nextAttemptAt: Date
}
struct KimiSchedule: Codable { var manual: Date; var automatic: Date }
struct KimiCache: Codable { let reading: KimiReading?; let lastGood: QuotaSnapshot? }

enum KimiEnvironment {
    static var isTest: Bool { CommandLine.arguments.contains { $0.hasSuffix("-self-test") } }
    static let endpoint = URL(string:"https://api.kimi.com/coding/v1/usages")!
}

func kimiCount(_ value: Any?) -> Double? {
    let parsed = number(value) ?? (value as? String).flatMap { Double($0) }
    guard let n = parsed, n.isFinite, n >= 0, n <= 9_007_199_254_740_991, n.rounded() == n else { return nil }
    return n
}
func kimiMinutes(_ window: [String:Any]) -> Int? {
    guard let duration = kimiCount(window["duration"]), duration > 0,
          let unit = window["timeUnit"] as? String else { return nil }
    let scale: Double
    switch unit {
    case "MINUTE", "TIME_UNIT_MINUTE": scale = 1
    case "HOUR", "TIME_UNIT_HOUR": scale = 60
    case "DAY", "TIME_UNIT_DAY": scale = 1440
    case "SECOND", "TIME_UNIT_SECOND": scale = 1.0/60
    default: return nil
    }
    let minutes = duration * scale
    guard minutes > 0, minutes <= 525600, minutes.rounded() == minutes else { return nil }
    return Int(minutes)
}
func parseKimi(_ data: Data, now: Date = Date()) throws -> KimiReading {
    guard data.count <= 65536, let raw = try JSONSerialization.jsonObject(with:data) as? [String:Any] else {
        throw QuotaError.message("Resposta Kimi inválida")
    }
    var windows: [QuotaWindow] = []
    var seen = Set<Int>()
    func row(_ values: [String:Any], minutes: Int?, label: String) throws {
        let limit = kimiCount(values["limit"])
        var remaining: Double?
        if let limit = limit, limit > 0 {
            if let usedValue = values["used"], !(usedValue is NSNull) {
                if let used = kimiCount(values["used"]) { remaining = 100 * max(0, limit-used) / limit }
            } else if let available = kimiCount(values["remaining"]), available <= limit { remaining = 100 * available / limit }
        }
        var reset: Double?
        for key in ["reset_at","resetAt","reset_time","resetTime"] {
            guard let text = values[key] as? String else { continue }
            let formatter = ISO8601DateFormatter();formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let date = formatter.date(from:text) ?? ISO8601DateFormatter().date(from:text) { reset = date.timeIntervalSince1970; break }
        }
        if let reset = reset, reset <= now.timeIntervalSince1970 { return }
        if let minutes = minutes, !seen.insert(minutes).inserted { throw QuotaError.message("Janelas Kimi duplicadas") }
        windows.append(QuotaWindow(name:label,remaining:remaining,durationMinutes:minutes,reset:reset))
    }
    // Kimi CLI's official /usage parser identifies the top-level usage summary as weekly.
    if let usage = raw["usage"] as? [String:Any] { try row(usage,minutes:10080,label:"Kimi semanal") }
    if let limits = raw["limits"] {
        guard let rows = limits as? [[String:Any]], rows.count <= 32 else { throw QuotaError.message("Limites Kimi inválidos") }
        for value in rows {
            let detail = value["detail"] as? [String:Any] ?? value
            let window = value["window"] as? [String:Any] ?? value
            let minutes = kimiMinutes(window) ?? kimiMinutes(value) ?? kimiMinutes(detail)
            let label = minutes == 300 ? "Kimi 5h" : minutes == 10080 ? "Kimi semanal" : "Janela Kimi"
            try row(detail,minutes:minutes,label:label)
        }
    }
    guard !windows.isEmpty, windows.contains(where:{$0.remaining != nil}) else { throw QuotaError.message("Kimi não informou quotas reconhecidas") }
    var snapshot = QuotaSnapshot(queriedAt:now,windows:windows)
    snapshot.provider = "kimi";snapshot.bucketID = "kimi-code:quota"
    return KimiReading(snapshot:snapshot,status:"ok",nextAttemptAt:now.addingTimeInterval(60))
}
func kimiStatus(_ status: String) -> String {
    switch status {
    case "ok": return ""
    case "auth_unavailable": return "Kimi: use Acessos para cadastrar a chave ou autorizar o Keychain"
    case "unauthorized": return "Kimi recusou a credencial; confira a chave do Coding Plan"
    case "rate_limited": return "Kimi limitou consultas; aguarde o intervalo informado"
    default: return "Consulta Kimi indisponível; última quota preservada"
    }
}
