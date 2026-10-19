import Foundation
import Darwin

final class GrokClient {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private(set) var quotaRequests = 0
    private(set) var lastExitStatus: Int32?
    private(set) var didLaunch=false
    let binary: String
    let timeout: TimeInterval
    init(binary: String = GrokEnvironment.binary(), timeout: TimeInterval = 25) { self.binary = binary; self.timeout = timeout }
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
    func read() throws -> GrokReading {
        if !FileManager.default.isExecutableFile(atPath:binary) {
            var snapshot=QuotaSnapshot(queriedAt:Date(),windows:[]);snapshot.provider="grok"
            return GrokReading(snapshot:snapshot,status:"cli_unavailable",nextAttemptAt:Date().addingTimeInterval(60))
        }
        if GrokEnvironment.isTest && !binary.hasPrefix(FileManager.default.temporaryDirectory.path) {throw QuotaError.message("CLI real bloqueado em testes")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("planmeter-grok-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer {try? FileManager.default.removeItem(at:directory)}
        let p = Process(), input = Pipe(), output = Pipe()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["--no-auto-update", "agent", "stdio"]
        p.currentDirectoryURL=directory
        var environment=ProcessInfo.processInfo.environment
        for key in ["XAI_API_KEY","GROK_API_KEY","GROK_DEPLOYMENT_KEY"] {environment.removeValue(forKey:key)}
        p.environment=environment
        p.standardInput = input; p.standardOutput = output
        let null = FileHandle(forWritingAtPath: "/dev/null")!
        p.standardError = null
        lock.lock(); process = p; let stop = cancelled; lock.unlock()
        if stop { throw QuotaError.message("Consulta cancelada") }
        do { try p.run();didLaunch=true } catch { throw QuotaError.message("CLI Grok não pôde iniciar") }
        defer {
            try? input.fileHandleForWriting.close()
            let end = Date().addingTimeInterval(2)
            while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { p.terminate() }
            let hardEnd = Date().addingTimeInterval(1)
            while p.isRunning && Date() < hardEnd { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit();lastExitStatus=p.terminationStatus
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
            if method == "_x.ai/billing" { quotaRequests += 1 }
            try send(["jsonrpc":"2.0", "id": id, "method": method, "params": params])
            while true {
                if isCancelled() { throw QuotaError.message("Consulta cancelada") }
                if Date() >= deadline { throw QuotaError.message("Consulta excedeu 25 segundos") }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    guard let msg = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                        throw QuotaError.message("Resposta oficial inválida")
                    }
                    if let method = msg["method"] as? String {
                        if let serverID = msg["id"] {
                            try send(["jsonrpc":"2.0", "id": serverID, "error": ["code": -32601, "message": "Read-only client"]])
                        }
                        _ = method
                        continue
                    }
                    if number(msg["id"]) == Double(id) {
                        if msg["error"] != nil { throw QuotaError.message("Falha na leitura oficial; confira login/rede no Grok") }
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
                    if count <= 0 { throw QuotaError.message("CLI Grok encerrou a conexão") }
                    buffer.append(contentsOf: bytes.prefix(count))
                    if buffer.count > 1_048_576 { throw QuotaError.message("Resposta excedeu limite local") }
                }
            }
        }
        _ = try request("initialize", ["protocolVersion":1,"clientCapabilities":[:],"clientInfo":["name":"planmeter","version":"1.2.0"]])
        return try parseGrok(request("_x.ai/billing"))
    }
}
