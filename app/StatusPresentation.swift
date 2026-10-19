import AppKit

struct StatusPresentation {
    let title: NSAttributedString
    let accessibilityText: String

    static let icons: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["codex", "claude", "zai", "kimi"] {
            if let url = ["svg","ico","png"].compactMap({ Bundle.main.url(forResource:name,withExtension:$0) }).first, let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 14, height: 14)
                result[name] = image
            }
        }
        return result
    }()

    static func zaiText(_ snapshot: QuotaSnapshot?) -> String {
        func remaining(_ minutes: Int) -> Double? {
            snapshot?.windows.filter { $0.durationMinutes == minutes }.compactMap(\.remaining).min()
        }
        return "5h \(percentLabel(remaining(300))) · sem \(percentLabel(remaining(10080)))"
    }

    static func make(codex: QuotaSnapshot?, claude: QuotaSnapshot?, zai: QuotaSnapshot?,
                     codexStale: Bool, claudeStale: Bool, zaiStale: Bool, badge: String, kimi: QuotaSnapshot? = nil, kimiStale: Bool = false, showKimi: Bool = false) -> StatusPresentation {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let title = NSMutableAttributedString(string: "")
        var labels: [String] = []
        var providers: [(String, String, String, Bool)] = [
            ("codex", "Codex", percentLabel(codex?.remaining), codexStale && codex != nil),
            ("claude", "Claude", percentLabel(claude?.remaining), claudeStale && claude != nil),
            ("zai", "Z.ai", zaiText(zai), zaiStale && zai != nil)
        ]
        if showKimi { providers.append(("kimi", "Kimi Code", zaiText(kimi), kimiStale && kimi != nil)) }
        for (index, provider) in providers.enumerated() {
            let (key, name, value, stale) = provider
            if index > 0 { title.append(NSAttributedString(string: "  ", attributes: attributes)) }
            if let image = icons[key] {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: -3, width: 14, height: 14)
                title.append(NSAttributedString(attachment: attachment))
            } else {
                title.append(NSAttributedString(string: name, attributes: attributes))
            }
            title.append(NSAttributedString(string: " " + value + (stale ? " ·" : ""), attributes: attributes))
            labels.append(name + " " + value + (stale ? " (desatualizado)" : ""))
        }
        title.append(NSAttributedString(string: badge, attributes: attributes))
        return StatusPresentation(title: title, accessibilityText: labels.joined(separator: " | ") + badge)
    }
}
