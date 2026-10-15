import Foundation

// A short-lived client: one fixed HTTPS GET, no proxy, redirect, body logging or model request.
final class ZaiClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    typealias Transport = (String) throws -> (Data, Int, String?)
    let keyProvider: () -> String?
    let transport: Transport?
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var body = Data(), response: HTTPURLResponse?, failure = false
    private let finished = DispatchSemaphore(value: 0)
    init(keyProvider: @escaping () -> String? = KeychainStore.read, transport: Transport? = nil) {
        self.keyProvider = keyProvider; self.transport = transport
    }
    func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
    func read() throws -> ZaiReading {
        let now = Date()
        var envelope: [String: Any] = ["source":"zai-official-quota", "host":"local-mac", "queriedAt":now.timeIntervalSince1970,
                                     "nextAttemptAt":now.timeIntervalSince1970 + 60, "status":"auth_unavailable", "limits":[]]
        guard let key = keyProvider(), !key.isEmpty, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            return try parseZai(JSONSerialization.data(withJSONObject: envelope))
        }
        do {
            let (data, code, retry) = try transport?(key) ?? request(key)
            if code == 401 || code == 403 { envelope["status"] = "unauthorized" }
            else if code == 429 {
                envelope["status"] = "rate_limited"
                let numeric = retry.flatMap(Double.init)
                let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0); formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
                let deadline = retry.flatMap { formatter.date(from:$0)?.timeIntervalSince(now) }
                let seconds = min(86400, max(900, (numeric ?? deadline).flatMap { $0.isFinite ? $0 : nil } ?? 900))
                envelope["retryAfter"] = seconds; envelope["nextAttemptAt"] = now.timeIntervalSince1970 + seconds
            } else if code == 200 {
                guard data.count <= 65536, let raw = try JSONSerialization.jsonObject(with: data) as? [String:Any],
                      raw["success"] as? Bool != false else { throw QuotaError.message("Resposta Z.ai inválida") }
                if let code = raw["code"] {
                    let valid = number(code).map { $0 == 0 || $0 == 200 } ?? ((code as? String).map { ["0","200"].contains($0) } ?? false)
                    guard valid else { throw QuotaError.message("Z.ai informou erro") }
                }
                let payload = raw["data"] as? [String:Any] ?? raw
                guard let rows = payload["limits"] as? [[String:Any]], rows.count <= 32 else { throw QuotaError.message("Quota Z.ai inválida") }
                envelope["limits"] = rows.map { row -> [String: Any] in
                    var clean: [String:Any] = [:]
                    for field in ["type","percentage","unit","number"] { if let value = row[field] { clean[field] = value } }
                    return clean
                }
                envelope["status"] = "ok"
            } else { envelope["status"] = "unavailable" }
            let result = try parseZai(JSONSerialization.data(withJSONObject: envelope))
            if result.status == "ok" && result.snapshot.remaining == nil { throw QuotaError.message("Z.ai não informou percentuais reconhecidos") }
            return result
        } catch { throw QuotaError.message("Consulta Z.ai falhou; confira rede, chave e plano. Nenhum detalhe privado foi registrado.") }
    }
    private func request(_ key: String) throws -> (Data, Int, String?) {
        guard !Runtime.isTest else { throw QuotaError.message("Rede bloqueada em testes") }
        var request = URLRequest(url: URL(string:"https://api.z.ai/api/monitor/usage/quota/limit")!)
        request.httpMethod = "GET"; request.timeoutInterval = 12
        request.setValue(key, forHTTPHeaderField:"Authorization")
        request.setValue("application/json", forHTTPHeaderField:"Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField:"Accept-Language")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate:self, delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        lock.lock()
        if cancelled { lock.unlock(); throw QuotaError.message("Consulta cancelada") }
        let newTask = session.dataTask(with:request); task = newTask
        lock.unlock(); newTask.resume()
        guard finished.wait(timeout:.now()+17) == .success else { cancel(); throw QuotaError.message("Timeout") }
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, !failure, let response = response else { throw QuotaError.message("Rede indisponível") }
        return (body, response.statusCode, response.value(forHTTPHeaderField:"Retry-After"))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); self.response = response as? HTTPURLResponse; lock.unlock(); completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); let oversized = body.count + data.count > 65536
        if oversized { failure = true } else { body.append(data) }
        lock.unlock(); if oversized { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); failure = true; lock.unlock(); completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); if error != nil { failure = true }; lock.unlock(); finished.signal()
    }
}
