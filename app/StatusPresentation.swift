import AppKit

struct StatusPresentation {
    let title: NSAttributedString
    let accessibilityText: String

    static let icons: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["codex", "claude", "zai", "kimi", "grok"] {
            if let url = ["svg","ico","png"].compactMap({ Bundle.main.url(forResource:name,withExtension:$0) }).first, let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 14, height: 14)
                result[name] = image
            }
        }
        return result
    }()

    static func validRemaining(_ snapshot:QuotaSnapshot?) -> Double? {
        snapshot?.windows.compactMap(\.remaining).filter{$0.isFinite && (0...100).contains($0)}.min()
    }
    static func zaiText(_ snapshot: QuotaSnapshot?) -> String {
        let periods:[(Int,String)]=[(300,"5h"),(10080,"sem")]
        let values=periods.compactMap { minutes,label -> String? in
            let remaining=snapshot?.windows.filter{$0.durationMinutes==minutes}.compactMap(\.remaining).filter{$0.isFinite && (0...100).contains($0)}.min()
            return remaining.map{label+" "+percentLabel($0)}
        }
        return values.isEmpty ? percentLabel(validRemaining(snapshot)) : values.joined(separator:" · ")
    }

    static func make(codex: QuotaSnapshot?, claude: QuotaSnapshot?, zai: QuotaSnapshot?,
                     codexStale: Bool, claudeStale: Bool, zaiStale: Bool, badge: String, kimi: QuotaSnapshot? = nil, kimiStale: Bool = false, showKimi: Bool = false, grok:QuotaSnapshot? = nil, grokStale:Bool = false) -> StatusPresentation {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let title = NSMutableAttributedString(string: "")
        var labels: [String] = []
        var providers: [(String, String, String, Bool)] = []
        if let value=validRemaining(codex) {providers.append(("codex","Codex",percentLabel(value),codexStale))}
        if let value=validRemaining(claude) {providers.append(("claude","Claude",percentLabel(value),claudeStale))}
        if validRemaining(zai) != nil {providers.append(("zai","Z.ai",zaiText(zai),zaiStale))}
        if showKimi && validRemaining(kimi) != nil {providers.append(("kimi","Kimi Code",zaiText(kimi),kimiStale))}
        if let value=validRemaining(grok) {providers.append(("grok","Grok",percentLabel(value),grokStale))}
        if providers.isEmpty {
            return StatusPresentation(title:NSAttributedString(string:"PlanMeter"+badge,attributes:attributes),accessibilityText:"PlanMeter · configurar acessos"+badge)
        }
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
