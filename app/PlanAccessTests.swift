import Foundation
import AppKit
func runPlanAccessTests() {
    var n=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL plan access: \(label)")};n += 1}
    var access=PlanAccess()
    check(access.active.isEmpty && !access.insightsAllowed,"free starts with explicit selection")
    check(access.setEnabled("codex",true),"first plan")
    check(access.setEnabled("claude",true),"second plan")
    check(!access.setEnabled("kimi",true) && access.active.count==2,"third plan rejected")
    check(!access.setEnabled("unknown",true),"unknown rejected")
    check(access.setEnabled("claude",false) && access.setEnabled("kimi",true),"selection can be exchanged")
    access.isPro=true
    check(access.setEnabled("grok",true) && access.active.count==3 && access.insightsAllowed,"pro unlocks plans and insights")
    access.isPro=false
    check(access.active.isEmpty && access.needsSelection,"downgrade requires explicit selection")
    check(access.selected.count==3,"downgrade preserves selection and credentials")
    check(access.setEnabled("grok",false) && access.active.count==2,"downgrade resolved")
    let restored=try! JSONDecoder().decode(PlanSelection.self,from:JSONEncoder().encode(PlanSelection(providers:access.selected)))
    check(restored.providers==access.selected,"selection persists independently of license")
    check(!PlanAccess(selected:restored.providers).isPro,"saved selection never proves entitlement")
    check(PlanAccess.migratedSelection(known:[]).isEmpty,"zero account migration")
    check(PlanAccess.migratedSelection(known:["codex"])==["codex"],"one known provider preserved")
    check(PlanAccess.migratedSelection(known:["codex","kimi"])==["codex","kimi"],"two known providers preserved")
    check(PlanAccess.migratedSelection(known:PlanAccess.providers).isEmpty,"five accounts require an explicit choice")
    print("PASS Plan access: \(n) checks")
}

func runPlanAccessUITests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL access UI: \(label)")};count += 1}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app=MenuApp();app.cacheDirectory=directory;app.planAccess=PlanAccess()
    app.status=NSStatusBar.system.statusItem(withLength:0);app.status.isVisible=false;app.celebrationDisplay=false
    defer {app.timer?.invalidate();app.claudeTimer?.invalidate();app.zaiTimer?.invalidate();app.kimi.stop();app.grok.stop();NSStatusBar.system.removeStatusItem(app.status);try? FileManager.default.removeItem(at:directory)}
    app.applyPlanAccess()
    app.zaiClientFactory={fatalError("disabled provider must not start")}
    app.manualRefresh()
    check(app.attempts==0 && app.claudeCacheReads==0 && app.zaiReads==0 && app.kimi.requests==0 && app.grok.requests==0,"free without selection starts no requests")
    let value=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"week",remaining:80,durationMinutes:10080,reset:nil)])
    app.snapshot=value;app.claudeSnapshot=value;app.zaiSnapshot=value
    app.updateDashboard();check(app.dashboard.cards.isEmpty,"unselected cache hidden")
    app.planAccess.selected=["codex","claude"];app.updateDashboard()
    check(app.dashboard.cards.count==2 && app.visible(value,"zai")==nil,"dashboard and bar share the limit")
    app.prepareAccessSettings()
    check(app.accessSetup.providers.filter{$0.enabled}.count==2,"only selected accounts can be configured")
    check(app.accessSetup.summary.contains("2/2"),"limit explained")
    app.planAccess.isPro=true;app.planAccess.selected.insert("zai");app.updateDashboard()
    check(app.dashboard.cards.count==3,"pro shows third selected plan")
    app.planAccess.isPro=false;app.updateDashboard()
    check(app.dashboard.cards.isEmpty && app.zaiSnapshot != nil,"downgrade does not delete cache")
    print("PASS Plan access UI: \(count) checks; no StoreKit purchase or provider requests")
}
