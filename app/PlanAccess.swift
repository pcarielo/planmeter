import Foundation

struct PlanSelection:Codable {var providers:Set<String>}
struct PlanAccess {
    static let providers:Set<String>=["codex","claude","zai","kimi","grok"]
    static func migratedSelection(known:Set<String>)->Set<String> {
        let supported=known.intersection(providers)
        return supported.count<=2 ? supported : []
    }
    var selected:Set<String>=[]
    var isPro=false
    var needsSelection:Bool {!isPro && selected.count>2}
    var active:Set<String> {needsSelection ? [] : selected.intersection(Self.providers)}
    var insightsAllowed:Bool {isPro}
    @discardableResult mutating func setEnabled(_ key:String,_ enabled:Bool)->Bool {
        guard Self.providers.contains(key) else{return false}
        if !enabled {selected.remove(key);return true}
        guard isPro || selected.contains(key) || selected.count<2 else{return false}
        selected.insert(key);return true
    }
}
