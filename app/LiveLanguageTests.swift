import AppKit

func runLiveLanguageTests() {
    var checks=0
    func check(_ value:Bool,_ label:String){guard value else{fatalError("FAIL live language: \(label)")};checks += 1}
    L10n.withTestLanguage("en") {
        let english=L("Atualizando dados…")
        check(english=="Refreshing data…" || english=="Updating data…","English starting state")
        let app=MenuApp();let directory=FileManager.default.temporaryDirectory.appendingPathComponent("live-language-"+UUID().uuidString)
        app.cacheDirectory=directory;app.binary="/nonexistent/language-test-codex";app.celebrationDisplay=false
        app.planAccess.selected=["codex","claude"];app.interfacePreferences.language="en"
        app.status=NSStatusBar.system.statusItem(withLength:0);app.status.isVisible=false
        app.zaiClientFactory={fatalError("language choice must never query Z.ai")}
        defer {app.dashboard.close();app.settingsWindow.window?.close();app.renewalWindow.window?.close();app.timer?.invalidate();app.claudeTimer?.invalidate();app.zaiTimer?.invalidate();app.kimi.stop();app.grok.stop();NSStatusBar.system.removeStatusItem(app.status);try? FileManager.default.removeItem(at:directory)}
        let snapshot=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"primary",remaining:70,durationMinutes:300,reset:Date().addingTimeInterval(3600).timeIntervalSince1970)])
        app.snapshot=snapshot;app.claudeSnapshot=snapshot;app.updateUI()
        app.showSettings(page:"language")
        app.settingsWindow.model.loginMessage=english
        let frame=app.settingsWindow.window!.frame;let window=app.settingsWindow.window!
        let selected=app.planAccess.selected
        let before=[app.attempts,app.quotaRequests,app.zaiReads,app.kimi.requests,app.grok.requests,app.claudeCacheReads]
        app.settingsWindow.model.interface.language="pt-BR"
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        check(L10n.code=="pt-BR" && L("Atualizar")=="Atualizar","Portuguese applies without reopen")
        check(app.settingsWindow.window === window && window.isVisible && window.frame==frame,"same settings window and geometry preserved")
        check(window.title=="Configurações do PlanMeter","native window title updated")
        check(app.settingsWindow.model.selected=="language","selected language tab preserved")
        check(app.settingsWindow.model.loginMessage=="Atualizando dados…","cached app-owned status relocalized")
        check(app.interfacePreferences.language=="pt-BR" && app.settingsWindow.model.languageRevision>0,"saved preference and UI revision updated")
        let decoded=try! JSONDecoder().decode(InterfacePreferences.self,from:Data(contentsOf:directory.appendingPathComponent("interface-preferences.json")))
        check(decoded.language=="pt-BR","choice persisted while app remains open")
        check(app.planAccess.selected==selected && before==[app.attempts,app.quotaRequests,app.zaiReads,app.kimi.requests,app.grok.requests,app.claudeCacheReads],"language switch leaves selections and queries untouched")
        app.settingsWindow.model.interface.language="en"
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        check(L10n.code=="en" && window.title=="PlanMeter Settings","switch back is immediate")
        if ProcessInfo.processInfo.environment["PLANMETER_CAPTURE_FIXTURES"]=="1" {
            app.settingsWindow.model.interface.language="pt-BR"
            app.settingsWindow.show(page:"general");RunLoop.current.run(until:Date().addingTimeInterval(0.15))
            if let view=window.contentView?.superview {captureFixturePreview(view,name:"settings-restored-general-pt")}
            app.settingsWindow.show(page:"language");RunLoop.current.run(until:Date().addingTimeInterval(0.15))
            if let view=window.contentView?.superview {captureFixturePreview(view,name:"settings-live-language-pt")}
        }
    }
    print("PASS live language: \(checks) checks; same window, no provider requests or credentials")
}
