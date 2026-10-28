import Foundation

// A short-lived client: one fixed HTTPS GET, no proxy, redirect, body logging or model request.
final class KimiClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    typealias Transport = (String) throws -> (Data, Int, String?)
    let keyProvider: () -> String?
    let transport: Transport?
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var body = Data(), response: HTTPURLResponse?, failure = false
    private let finished = DispatchSemaphore(value: 0)
    init(keyProvider: @escaping () -> String? = KimiKeychain.read, transport: Transport? = nil) {
        self.keyProvider = keyProvider; self.transport = transport
    }
    func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
    func read() throws -> KimiReading {
        let now = Date()
        func status(_ value: String, wait: Double = 60) -> KimiReading {
            var snapshot = QuotaSnapshot(queriedAt:now,windows:[]);snapshot.provider = "kimi"
            return KimiReading(snapshot:snapshot,status:value,nextAttemptAt:now.addingTimeInterval(wait))
        }
        guard let key = keyProvider(), !key.isEmpty, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({$0.value >= 33 && $0.value <= 126}) else { return status("auth_unavailable") }
        do {
            let (data,code,retry) = try transport?(key) ?? request(key)
            switch code {
            case 200:
                let reading=try parseKimi(data,now:now);var snapshot=reading.snapshot
                snapshot.credentialScope=quotaCredentialScope(provider:"kimi",key:key)
                return KimiReading(snapshot:snapshot,status:reading.status,nextAttemptAt:reading.nextAttemptAt)
            case 401,403: return status("unauthorized")
            case 429:
                let formatter = DateFormatter();formatter.locale = Locale(identifier:"en_US_POSIX");formatter.timeZone = TimeZone(secondsFromGMT:0);formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
                let seconds = retry.flatMap(Double.init) ?? retry.flatMap {formatter.date(from:$0)?.timeIntervalSince(now)} ?? 900
                return status("rate_limited",wait:seconds.isFinite ? min(86400,max(900,seconds)) : 900)
            default: return status("unavailable")
            }
        } catch { throw QuotaError.message("Consulta Kimi falhou; nenhum detalhe privado foi registrado") }
    }
    private func request(_ key: String) throws -> (Data, Int, String?) {
        guard !KimiEnvironment.isTest else { throw QuotaError.message("Rede bloqueada em testes") }
        var request = URLRequest(url: KimiEnvironment.endpoint)
        request.httpMethod = "GET"; request.timeoutInterval = 12
        request.setValue("Bearer " + key, forHTTPHeaderField:"Authorization")
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
