import Foundation

struct ClaudeCacheProvider {
    let path: URL
    func read(now: Date = Date()) throws -> QuotaSnapshot {
        let data = try Data(contentsOf: path)
        guard data.count < 65536,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              raw["source"] as? String == "claude-code-statusline",
              let observed = number(raw["providerObservedAt"]), observed > 0,
              observed <= now.timeIntervalSince1970 + 5,
              let limits = raw["rateLimits"] as? [String: Any] else { throw QuotaError.message("Cache Claude sem dados verificáveis") }
        var windows: [QuotaWindow] = []
        for (name, duration) in [("five_hour", 300), ("seven_day", 10080)] {
            guard let window = limits[name] as? [String: Any] else { continue }
            let used = number(window["used_percentage"])
            let remaining = used.flatMap { (0...100).contains($0) ? 100 - $0 : nil }
            let reset = number(window["resets_at"]).flatMap { (0...253_402_300_799).contains($0) ? $0 : nil }
            // Claude Code drops expired windows; a cached expired row cannot be promoted to fresh quota.
            if let reset = reset, reset <= now.timeIntervalSince1970 { continue }
            windows.append(QuotaWindow(name: name, remaining: remaining, durationMinutes: duration, reset: reset))
        }
        var snapshot = QuotaSnapshot(queriedAt: Date(timeIntervalSince1970: observed), windows: windows)
        snapshot.provider = "claude"; snapshot.bucketID = "claude_usage"
        if raw["capturedAt"] != nil {
            guard let received = number(raw["capturedAt"]), received > 0,
                  received >= observed - 5, received <= now.timeIntervalSince1970 + 5 else {
                throw QuotaError.message("Horário de entrega Claude inválido")
            }
            snapshot.receivedAt = Date(timeIntervalSince1970: received)
        }
        if let identity = raw["identityFingerprint"] as? String,
           identity.count == 64, identity.allSatisfy({ "0123456789abcdef".contains($0) }) { snapshot.identityFingerprint = identity }
        return snapshot
    }
}
struct CelebrationActivity {
    var sleeping = false
    var screenLocked = false
    var displaySleeping = false
    var suspended: Bool { sleeping || screenLocked || displaySleeping }
}
