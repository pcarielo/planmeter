import Foundation

struct ResetRecord: Codable {
    let id: String
    var provider: String? = nil
    let identityFingerprint: String
    let bucketID: String
    let window: String
    let durationMinutes: Int
    let detectedAt: Date
    let previousServiceResetAt: Double
    let serviceResetAt: Double
    let previousUsedPercent: Double
    let usedPercent: Double
    var acknowledgedAt: Date?
    var groupKey: String { "\(provider ?? "codex"):\(identityFingerprint):\(bucketID):\(window):\(durationMinutes)" }
}
struct ResetState: Codable {
    var baseline: QuotaSnapshot?
    var recentEventIDs: [String] = []
    var lastDetectedAt: Date?
    var history: [ResetRecord] = []
    init() {}
    enum CodingKeys: String, CodingKey { case baseline, recentEventIDs, lastDetectedAt, history }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseline = try c.decodeIfPresent(QuotaSnapshot.self, forKey: .baseline)
        recentEventIDs = try c.decodeIfPresent([String].self, forKey: .recentEventIDs) ?? []
        lastDetectedAt = try c.decodeIfPresent(Date.self, forKey: .lastDetectedAt)
        // Legacy one-shot events have no factual detail; never fabricate historical records.
        history = try c.decodeIfPresent([ResetRecord].self, forKey: .history) ?? []
    }
    func activePending(snapshot: QuotaSnapshot?) -> [ResetRecord] {
        guard let snapshot = snapshot, let identity = snapshot.identityFingerprint else { return [] }
        return history.filter { record in
            record.acknowledgedAt == nil && (record.provider ?? "codex") == snapshot.effectiveProvider && record.identityFingerprint == identity && record.bucketID == snapshot.bucketID
        }
    }
    mutating func acknowledge(ids: Set<String>, at: Date = Date()) {
        for i in history.indices where ids.contains(history[i].id) && history[i].acknowledgedAt == nil { history[i].acknowledgedAt = at }
    }
}
struct ResetDetector {
    var state = ResetState()
    private var armed = false
    mutating func interrupt() { armed = false }
    mutating func accept(_ current: QuotaSnapshot) -> [ResetRecord] {
        let previous = state.baseline
        defer { state.baseline = current; armed = true }
        guard let prior = previous,
              let identity = current.identityFingerprint, !identity.isEmpty,
              identity == prior.identityFingerprint,
              current.effectiveProvider == prior.effectiveProvider,
              current.bucketID == (current.effectiveProvider == "claude" ? "claude_usage" : "codex"), current.bucketID == prior.bucketID,
              current.queriedAt > prior.queriedAt else { return [] }
        var events: [ResetRecord] = []
        for window in current.windows {
            guard let old = prior.windows.first(where: { $0.name == window.name }),
                  let duration = window.durationMinutes, duration > 0, duration == old.durationMinutes,
                  let before = old.remaining, let after = window.remaining,
                  before.isFinite, after.isFinite, (0...100).contains(before), (0...100).contains(after),
                  after - before >= 1,
                  let oldReset = old.reset, let newReset = window.reset,
                  oldReset.isFinite, newReset.isFinite,
                  newReset >= oldReset + 60,
                  (0...253_402_300_799).contains(newReset),
                  oldReset >= prior.queriedAt.timeIntervalSince1970 - 180,
                  newReset > current.queriedAt.timeIntervalSince1970 else { continue }
            let seconds = Double(duration) * 60, now = current.queriedAt.timeIntervalSince1970
            let gap = current.queriedAt.timeIntervalSince(prior.queriedAt)
            // Early/manual resets still need uninterrupted, closely spaced observations.
            let continuous = armed && gap <= 150 && abs((newReset - now) - seconds) <= 180
            // A scheduled renewal can be confirmed after sleep/restart from the same
            // account: the old deadline passed, quota recovered, and a full window advanced.
            let scheduled = gap <= seconds && oldReset <= now &&
                newReset - oldReset >= seconds - 180 && newReset - now <= seconds + 180
            guard (continuous || scheduled), oldReset - now <= seconds + 180 else { continue }
            let id = "\(current.effectiveProvider):\(identity):\(current.bucketID!):\(window.name):\(duration):\(Int64(newReset))"
            guard !state.recentEventIDs.contains(id), !state.history.contains(where: { $0.id == id }) else { continue }
            let event = ResetRecord(id: id, provider: current.effectiveProvider, identityFingerprint: identity, bucketID: current.bucketID!, window: window.name,
                                    durationMinutes: duration, detectedAt: current.queriedAt,
                                    previousServiceResetAt: oldReset, serviceResetAt: newReset,
                                    previousUsedPercent: 100 - before, usedPercent: 100 - after, acknowledgedAt: nil)
            state.history.append(event)
            state.recentEventIDs.append(id)
            if state.recentEventIDs.count > 32 { state.recentEventIDs.removeFirst(state.recentEventIDs.count - 32) }
            state.lastDetectedAt = current.queriedAt
            events.append(event)
        }
        return events
    }
}
func detectionIntervals(_ records: [ResetRecord]) -> [TimeInterval] {
    let ordered = records.sorted { $0.detectedAt < $1.detectedAt }
    guard ordered.count >= 2 else { return [] }
    return zip(ordered, ordered.dropFirst()).map { $1.detectedAt.timeIntervalSince($0.detectedAt) }
}
func intervalLabel(_ seconds: TimeInterval) -> String {
    let minutes = Int(max(0, seconds) / 60)
    if minutes >= 1440 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h \(minutes % 60)min" }
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)min" }
    return "\(minutes)min"
}
func countdownLabel(reset: Double?, now: Date = Date()) -> String {
    guard let reset = reset, reset.isFinite else { return "Prazo não informado" }
    let difference = reset - now.timeIntervalSince1970
    guard difference > 0 else { return "Horário previsto passou; aguardando leitura" }
    let minutes = Int(min(52_560_000, ceil(difference / 60)))
    let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
    if days > 0 { return "Previsto em \(days)d \(hours)h \(mins)min" }
    if hours > 0 { return "Previsto em \(hours)h \(mins)min" }
    return "Previsto em \(mins)min"
}
struct CelebrationPreferences: Codable {
    var loopEnabled = true
    // New installations respect the system accessibility preference.
    var respectReduceMotion = true
}
