import Foundation
import Darwin
import CryptoKit

struct QuotaWindow: Codable {
    let name: String
    let remaining: Double?
    let durationMinutes: Int?
    let reset: Double?
    var startedAt: Double? = nil
}
struct QuotaSnapshot: Codable {
    let queriedAt: Date
    let windows: [QuotaWindow]
    var identityFingerprint: String? = nil
    var bucketID: String? = nil
    var provider: String? = nil
    var sourceHost: String? = nil
    // Latest delivery from a passive source; not proof of a fresh provider API query.
    var receivedAt: Date? = nil
    var effectiveProvider: String { provider ?? "codex" }
    var remaining: Double? { windows.compactMap(\.remaining).min() }
}
enum QuotaError: Error {
    case message(String)
    var text: String { switch self { case .message(let value): return value } }
}
func number(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
    return n.doubleValue
}
import CoreFoundation
func parseQuota(_ result: [String: Any], now: Date = Date()) throws -> QuotaSnapshot {
    let map = result["rateLimitsByLimitId"] as? [String: Any]
    let bucket: [String: Any]?
    if let map = map, !map.isEmpty {
        bucket = map["codex"] as? [String: Any]
    } else {
        bucket = result["rateLimits"] as? [String: Any]
    }
    guard let bucket = bucket else { throw QuotaError.message("Quota Codex indisponível") }
    var windows: [QuotaWindow] = []
    for name in ["primary", "secondary"] {
        guard let raw = bucket[name] as? [String: Any] else { continue }
        let used = number(raw["usedPercent"])
        let valid = used != nil && (0...100).contains(used!)
        let duration = number(raw["windowDurationMins"])
        let minutes = duration.flatMap { $0 > 0 && $0.rounded() == $0 && $0 < Double(Int.max) ? Int($0) : nil }
        windows.append(QuotaWindow(name: name, remaining: valid ? 100 - used! : nil,
                                   durationMinutes: minutes, reset: number(raw["resetsAt"]).flatMap { (0...253_402_300_799).contains($0) ? $0 : nil }))
    }
    var snapshot = QuotaSnapshot(queriedAt: now, windows: windows)
    snapshot.bucketID = bucket["limitId"] as? String ?? (map?["codex"] != nil ? "codex" : nil)
    return snapshot
}
func durationLabel(_ minutes: Int?) -> String {
    guard let m = minutes else { return "duração não informada" }
    if m % 1440 == 0 { return "\(m / 1440) dias" }
    if m % 60 == 0 { return "\(m / 60) horas" }
    return "\(m) minutos"
}
func percentLabel(_ value: Double?) -> String {
    guard let value = value else { return "—" }
    return String(format: "%.0f%%", value.rounded())
}
func localDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
    f.dateFormat = "dd/MM HH:mm:ss zzz"
    return f.string(from: date)
}
struct RefreshPolicy {
    var busy = false
    var sleeping = false
    var failures = 0
    var lastAttempt: Date?
    mutating func begin(now: Date = Date()) -> Bool {
        guard !busy, !sleeping else { return false }
        busy = true
        lastAttempt = now
        return true
    }
    mutating func finish(success: Bool) {
        busy = false
        if success { failures = 0 } else if !sleeping { failures = min(5, failures + 1) }
    }
    var interval: TimeInterval { min(900, 60 * pow(2, Double(max(0, failures - 1)))) }
    func delay(now: Date = Date()) -> TimeInterval {
        max(1, (lastAttempt ?? now).addingTimeInterval(interval).timeIntervalSince(now))
    }
}

final class AppServerClient {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private(set) var quotaRequests = 0
    let binary: String
    let timeout: TimeInterval
    init(binary: String, timeout: TimeInterval = 20) { self.binary = binary; self.timeout = timeout }
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p = p, p.isRunning { p.terminate() }
    }
    func stopForExit() {
        cancel()
        lock.lock(); let p = process; lock.unlock()
        guard let p = p else { return }
        let deadline = Date().addingTimeInterval(2)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) }
    }
    private func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func read() throws -> QuotaSnapshot {
        let p = Process(), input = Pipe(), output = Pipe()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["app-server", "--stdio"]
        p.environment = Runtime.cliEnvironment(binary:binary,inherited:ProcessInfo.processInfo.environment)
        p.standardInput = input; p.standardOutput = output
        let null = FileHandle(forWritingAtPath: "/dev/null")!
        p.standardError = null
        lock.lock(); process = p; let stop = cancelled; lock.unlock()
        if stop { throw QuotaError.message("Consulta cancelada") }
        do { try p.run() } catch { throw QuotaError.message("CLI Codex não pôde iniciar") }
        defer {
            try? input.fileHandleForWriting.close()
            let end = Date().addingTimeInterval(2)
            while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { p.terminate() }
            let hardEnd = Date().addingTimeInterval(1)
            while p.isRunning && Date() < hardEnd { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
            try? output.fileHandleForReading.close(); try? null.close()
            lock.lock(); process = nil; lock.unlock()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data(), requestID = 0
        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func request(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
            requestID += 1
            let id = requestID
            if method == "account/rateLimits/read" { quotaRequests += 1 }
            try send(["id": id, "method": method, "params": params])
            while true {
                if isCancelled() { throw QuotaError.message("Consulta cancelada") }
                if Date() >= deadline { throw QuotaError.message("Consulta excedeu 20 segundos") }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    guard let msg = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                        throw QuotaError.message("Resposta oficial inválida")
                    }
                    if let method = msg["method"] as? String {
                        if let serverID = msg["id"] {
                            try send(["id": serverID, "error": ["code": -32601, "message": "Read-only client"]])
                        }
                        _ = method
                        continue
                    }
                    if number(msg["id"]) == Double(id) {
                        if msg["error"] != nil { throw QuotaError.message("Falha na leitura oficial; confira login/rede no Codex") }
                        guard let value = msg["result"] as? [String: Any] else { throw QuotaError.message("Resposta oficial inválida") }
                        return value
                    }
                }
                var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let ready = Darwin.poll(&fd, 1, 200)
                if ready < 0 { if errno == EINTR { continue }; throw QuotaError.message("Transporte indisponível") }
                if ready > 0 {
                    var bytes = [UInt8](repeating: 0, count: 8192)
                    let count = Darwin.read(fd.fd, &bytes, bytes.count)
                    if count <= 0 { throw QuotaError.message("App-server encerrou a conexão") }
                    buffer.append(contentsOf: bytes.prefix(count))
                    if buffer.count > 1_048_576 { throw QuotaError.message("Resposta excedeu limite local") }
                }
            }
        }
        _ = try request("initialize", ["clientInfo": ["name": "planmeter", "title": "PlanMeter", "version": "1.0.0"]])
        try send(["method": "initialized", "params": [:]])
        let account = try request("account/read", ["refreshToken": false])["account"] as? [String: Any]
        guard account?["type"] as? String == "chatgpt" else { throw QuotaError.message("Login ChatGPT gerenciado indisponível") }
        let result = try request("account/rateLimits/read")
        var snapshot = try parseQuota(result)
        // Hash an official opaque account ID; never retain email, ID, or tokens.
        if let accountID = result["accountId"] as? String, !accountID.isEmpty {
            snapshot.identityFingerprint = SHA256.hash(data: Data(("chatgpt:" + accountID).utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return snapshot
    }
}
