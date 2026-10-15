import Foundation

struct ZaiSchedule: Codable { let manual: Double; let automatic: Double }

struct ZaiReading: Codable {
    let snapshot: QuotaSnapshot
    let status: String
    let retryAfter: Double?
    let nextAttemptAt: Double?
    var fresh: Bool { status == "ok" && Date().timeIntervalSince(snapshot.queriedAt) <= 960 }
}
func parseZai(_ data: Data, now: Date = Date()) throws -> ZaiReading {
    guard data.count <= 65536, let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          raw["source"] as? String == "zai-official-quota", raw["host"] as? String == "local-mac",
          let time = number(raw["queriedAt"]), time > 0, time <= now.timeIntervalSince1970 + 5,
          let status = raw["status"] as? String, ["ok","test_mode","auth_unavailable","unauthorized","rate_limited","unavailable"].contains(status) else { throw QuotaError.message("Quota Z.ai sem origem verificável") }
    let rows = raw["limits"] as? [[String: Any]] ?? []
    guard rows.count <= 32 else { throw QuotaError.message("Quota Z.ai excessiva") }
    var windows: [QuotaWindow] = []
    var seen = Set<String>()
    if status == "ok" {
        for row in rows {
            guard let type = row["type"] as? String, ["TOKENS_LIMIT","CREDIT_LIMIT","TIME_LIMIT"].contains(type) else { continue }
            let unit = number(row["unit"]), count = number(row["number"])
            let metadata = unit.map { $0 >= 1 && $0 <= 10 && $0.rounded() == $0 } == true && count.map { $0 >= 1 && $0 <= 366 && $0.rounded() == $0 } == true
            let identity = metadata ? "\(type):\(unit!):\(count!)" : type
            guard seen.insert(identity).inserted else { throw QuotaError.message("Quota Z.ai duplicada") }
            let used = number(row["percentage"]).flatMap { (0...100).contains($0) ? $0 : nil }
            let tokenWindow = type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT"
            let minutes: Int? = tokenWindow && unit == 3 && count == 5 ? 300 : tokenWindow && unit == 6 && count == 1 ? 10080 : nil
            let base = type == "TIME_LIMIT" ? "Uso MCP" : type == "CREDIT_LIMIT" ? "Uso de créditos" : "Uso de tokens"
            let label = minutes == 300 ? base + " (5h)" : minutes == 10080 ? base + " (semanal)" : base + " (janela não informada)"
            windows.append(QuotaWindow(name: label, remaining: used.map {100-$0}, durationMinutes: minutes, reset: nil))
        }
    }
    var snapshot = QuotaSnapshot(queriedAt: Date(timeIntervalSince1970: time), windows: windows)
    snapshot.provider = "zai"; snapshot.sourceHost = "local-mac"; snapshot.bucketID = "zai:quota"
    return ZaiReading(snapshot: snapshot, status: status, retryAfter: number(raw["retryAfter"]).flatMap { $0 >= 0 && $0 <= 86400 ? $0 : nil }, nextAttemptAt: number(raw["nextAttemptAt"]).flatMap { $0 >= time && $0 <= time + 86400 ? $0 : nil })
}
func zaiStatus(_ reading: ZaiReading?) -> String {
    guard let reading = reading else { return "Autenticação Z.ai ainda não vinculada" }
    switch reading.status {
    case "ok": return reading.snapshot.windows.isEmpty ? "Servidor não informou janelas reconhecidas" : ""
    case "test_mode": return "Serviço em teste; cadastro privado da chave Z.ai pendente"
    case "auth_unavailable": return "Chave ausente ou Keychain bloqueado; configure Z.ai no menu"
    case "unauthorized": return "Z.ai recusou autenticação; sem tentativa de login"
    case "rate_limited": return "Z.ai limitou consultas; aguarde cooldown"
    default: return "Consulta Z.ai indisponível; última quota preservada"
    }
}

func runZaiTests() {
    var count=0
    func check(_ ok: Bool) { if !ok {fputs("FAIL Z.ai parser\n",stderr);exit(1)};count += 1 }
    let now=Date()
    func payload(_ rows:[[String:Any]], status:String="ok") -> Data { try! JSONSerialization.data(withJSONObject:["source":"zai-official-quota","host":"local-mac","queriedAt":now.timeIntervalSince1970,"status":status,"limits":rows]) }
    let good=try! parseZai(payload([["type":"TOKENS_LIMIT","percentage":25],["type":"TIME_LIMIT","percentage":80]]),now:now)
    check(good.snapshot.windows.count==2);check(good.snapshot.remaining==20);check(good.snapshot.windows[0].remaining==75);check(good.snapshot.windows[1].durationMinutes==nil);check(good.snapshot.windows.allSatisfy{$0.reset==nil});check(good.snapshot.identityFingerprint==nil)
    for value:Any in [-1,101,true,"25",NSNull()] { let reading=try! parseZai(payload([["type":"TOKENS_LIMIT","percentage":value]]));check(reading.snapshot.remaining==nil) }
    check((try! parseZai(payload([["type":"WEEKLY_LIMIT","percentage":0]]))).snapshot.windows.isEmpty)
    for status in ["auth_unavailable","unauthorized","rate_limited","unavailable"] {let r=try! parseZai(payload([["type":"TOKENS_LIMIT","percentage":0]],status:status));check(r.snapshot.windows.isEmpty);check(!r.fresh);check(!zaiStatus(r).isEmpty)}
    do {_=try parseZai(payload([["type":"TOKENS_LIMIT","percentage":0],["type":"TOKENS_LIMIT","percentage":1]]));check(false)}catch{check(true)}
    let synthetic = try! parseZai(payload([["type":"TOKENS_LIMIT","percentage":0]],status:"test_mode"))
    check(synthetic.snapshot.windows.isEmpty); check(!synthetic.fresh); check(zaiStatus(synthetic).contains("cadastro privado"))
    for kind in ["CREDIT_LIMIT", "TOKENS_LIMIT"] {
        let windows = try! parseZai(payload([["type":kind,"percentage":20,"unit":3,"number":5],["type":kind,"percentage":40,"unit":6,"number":1]]))
        check(windows.snapshot.windows.count == 2)
        check(windows.snapshot.windows[0].durationMinutes == 300)
        check(windows.snapshot.windows[1].durationMinutes == 10080)
        check(windows.snapshot.remaining == 60)
    }
    print("PASS Z.ai: \(count) parser/provenance/error/no-model checks")
}
