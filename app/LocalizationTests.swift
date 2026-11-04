import Foundation
import AppKit
import Security

func runLocalizationTests() {
    var checks=0
    func check(_ value:Bool,_ label:String){guard value else{fatalError("FAIL localization: \(label)")};checks += 1}
    check(L10n.languages.count==8 && L10n.choices.count==9,"eight languages plus system")
    check(L10n.choices.first{$0.code=="pt-BR"}?.name=="Português","Portuguese name has no region suffix")
    for (primary,expected) in [("en-GB","en"),("es-MX","es"),("pt-PT","pt-BR"),("ko-KR","ko"),("ja-JP","ja"),("fr-CA","fr"),("zh-Hant-HK","zh-Hant"),("zh-TW","zh-Hant"),("zh-Hans-CN","en"),("hi-IN","hi"),("de-DE","en")] {
        check(L10n.resolvedCode(selection:"system",preferredLanguage:primary)==expected,"system mapping \(primary)")
    }
    check(L10n.resolvedCode(selection:"fr",preferredLanguage:"ko-KR")=="fr","manual choice wins")
    let legacy=try! JSONDecoder().decode(InterfacePreferences.self,from:Data(#"{"appearance":"dark","scale":1.25,"dismissal":30,"pinned":false}"#.utf8))
    check(legacy.language=="system" && legacy.scale==1.25,"existing preferences migrate without loss")
    var saved=legacy;saved.language="hi"
    let decoded=try! JSONDecoder().decode(InterfacePreferences.self,from:JSONEncoder().encode(saved))
    check(decoded==saved,"language choice round trips")
    saved.language="unsupported";check(saved.normalized().language=="system","unknown preference safely returns to automatic")
    check(L10n.render("Atualizar",language:"unsupported")=="Refresh","missing catalog falls back to English")
    check(L10n.substitute("%2$@ / %1$@",arguments:["A","B"])=="B / A","translations may reorder arguments")
    check(L10n.substitute("%1$@",arguments:["literal %2$@ value"])=="literal %2$@ value","arguments cannot inject placeholders")
    let window=QuotaWindow(name:"stable-provider-window",remaining:80,durationMinutes:10080,reset:1_900_000_000)
    var snapshot=QuotaSnapshot(queriedAt:Date(timeIntervalSince1970:1_899_999_000),windows:[window]);snapshot.provider="codex";snapshot.identityFingerprint="synthetic-account"
    var history=RenewalHistory();var expectedID:String?
    let keys=Set(L10n.catalog("pt-BR").keys)
    for code in L10n.languages {
        L10n.withTestLanguage(code) {
            check(Set(L10n.catalog(code).keys)==keys && !keys.isEmpty,"complete catalog \(code)")
            check(!L("Atualizar").isEmpty && !L("Configurações").isEmpty,"core UI translates \(code)")
            let result=L("Disponível em \(15)s")
            check(result.contains("15") && !result.contains("$@"),"parameter interpolation \(code)")
            _=history.ingest(snapshot)
            if let id=expectedID {check(history.entries.first?.id==id && history.entries.count==1,"history dedup independent of \(code)")}
            else {expectedID=history.entries.first?.id}
            check(history.entries.first?.window=="Semanal" && quotaWindowIdentityLabel(window)=="Semanal","stored identity is language independent \(code)")
            check(history.entries.first?.displayWindow==L("Semanal"),"history display follows locale \(code)")
            check(!localDate(snapshot.queriedAt).isEmpty,"localized date \(code)")
            check(CredentialAccess.baseQuery("synthetic-service")[kSecAttrAccount as String] as? String == "quota","Keychain account never localized \(code)")
            let payload=try! JSONSerialization.data(withJSONObject:["usage":["limit":"1000","used":"200"],"limits":[["window":["duration":300,"timeUnit":"TIME_UNIT_MINUTE"],"detail":["limit":100,"remaining":70]]]])
            let kimi=try! parseKimi(payload)
            check(kimi.snapshot.windows.first{$0.durationMinutes==10080}?.name=="Kimi semanal","Kimi stored window never localized \(code)")
        }
    }
    check(snapshot.windows[0].name=="stable-provider-window","provider snapshot never translated in storage")
    print("PASS localization: \(checks) checks; no OS language or credential changes")
}

func runLocalizationUITests() {
    let previous=NSApp.appearance
    defer {NSApp.appearance=previous}
    for code in L10n.languages {
        L10n.withTestLanguage(code) {
            let settings=SettingsWindow()
            settings.model.interface.language=code
            settings.show(page:"general")
            settings.window?.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.15))
            if ProcessInfo.processInfo.environment["PLANMETER_CAPTURE_FIXTURES"]=="1",let content=settings.window?.contentView {
                captureFixturePreview(content,name:"language-settings-"+code)
                let stamp=Date()
                let snapshot=QuotaSnapshot(queriedAt:stamp,windows:[QuotaWindow(name:"primary",remaining:65,durationMinutes:300,reset:stamp.addingTimeInterval(7200).timeIntervalSince1970),QuotaWindow(name:"secondary",remaining:80,durationMinutes:10080,reset:stamp.addingTimeInterval(86400*3).timeIntervalSince1970)])
                let view=QuotaDashboardView(cards:[QuotaCard(key:"codex",name:"Codex",snapshot:snapshot,stale:false),QuotaCard(key:"claude",name:"Claude",snapshot:snapshot,stale:false)],width:600)
                view.pinned=true
                let host=NSWindow(contentRect:view.bounds,styleMask:[.borderless],backing:.buffered,defer:false);host.isReleasedWhenClosed=false;host.contentView=view
                captureFixturePreview(view,name:"language-dashboard-"+code);host.close()
            }
            settings.window?.close()
        }
    }
    print("PASS localized UI: eight Settings and dashboard fixtures; no login or provider activity")
}
