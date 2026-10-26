import AppKit
import UniformTypeIdentifiers

struct RenewalEntry: Codable, Equatable {
    var id=UUID().uuidString
    var provider:String
    var bucket:String
    var identity:String?
    var window:String
    var minutes:Int?
    var startedAt:Double
    var endsAt:Double
    var recordedAt:Date
    var startReported=false
    var detectedBetweenReadings=false
    var evidence:String {
        (detectedBetweenReadings ? "Detectado entre leituras · " : "") + (startReported ? "início informado" : "início inferido")
    }
    var scopeLabel:String {identity.map {"Conta "+String($0.prefix(8))} ?? "Conta não identificada"}
    var providerName:String { ["codex":"Codex","claude":"Claude","zai":"Z.ai","kimi":"Kimi Code","grok":"Grok"][provider] ?? provider }
}
struct RenewalHistory: Codable {
    var entries:[RenewalEntry]=[]
    static let providers=["codex","claude","zai","kimi","grok"]
    var ordered:[RenewalEntry] {entries.sorted {$0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt > $1.startedAt}}
    func recent(_ provider:String)->[RenewalEntry] {Array(ordered.filter {$0.provider==provider}.prefix(5))}
    @discardableResult mutating func merge(_ value:RenewalEntry)->Bool {
        let tolerance=min(120,max(1,(value.endsAt-value.startedAt)*0.01))
        if let index=entries.firstIndex(where:{ entry in
            entry.provider==value.provider && entry.window==value.window && entry.minutes==value.minutes &&
            (entry.identity==nil || value.identity==nil || entry.identity==value.identity) &&
            (entry.bucket==value.bucket || entry.bucket.contains("unknown") || value.bucket.contains("unknown") || entry.bucket=="grok:subscription") &&
            abs(entry.endsAt-value.endsAt)<=tolerance && abs(entry.startedAt-value.startedAt)<=tolerance
        }) {
            var updated=entries[index]
            if value.detectedBetweenReadings && !updated.detectedBetweenReadings {updated.detectedBetweenReadings=true;updated.recordedAt=value.recordedAt}
            if value.startReported && !updated.startReported {updated.startReported=true;updated.startedAt=value.startedAt;updated.endsAt=value.endsAt}
            if updated.identity==nil, value.identity != nil {updated.identity=value.identity;updated.recordedAt=value.recordedAt}
            if updated.bucket.contains("unknown") || updated.bucket=="grok:subscription" {updated.bucket=value.bucket}
            guard updated != entries[index] else{return false}
            entries[index]=updated;return true
        }
        entries.append(value);return true
    }
    @discardableResult mutating func ingest(_ snapshot:QuotaSnapshot)->Bool {
        guard Self.providers.contains(snapshot.effectiveProvider) else{return false}
        var changed=false
        for window in snapshot.windows {
            guard let end=window.reset,end.isFinite,(946684800...4102444800).contains(end) else{continue}
            let reported=window.startedAt
            let inferred=window.durationMinutes.flatMap {$0>0 ? end-Double($0)*60 : nil}
            guard let start=reported ?? inferred,start.isFinite,start>=946684800,start<end,start<=snapshot.queriedAt.timeIntervalSince1970+5 else{continue}
            let row=RenewalEntry(provider:snapshot.effectiveProvider,bucket:snapshot.bucketID ?? "unknown",identity:snapshot.identityFingerprint,window:QuotaCard.windowLabel(window),minutes:window.durationMinutes,startedAt:start,endsAt:end,recordedAt:snapshot.queriedAt,startReported:reported != nil)
            changed=merge(row) || changed
        }
        return changed
    }
    @discardableResult mutating func importDetection(_ record:ResetRecord)->Bool {
        guard record.durationMinutes>0,record.serviceResetAt.isFinite else{return false}
        let start=record.serviceResetAt-Double(record.durationMinutes)*60
        guard start>=946684800,start<record.serviceResetAt,start<=record.detectedAt.timeIntervalSince1970+180 else{return false}
        let label=QuotaCard.windowLabel(QuotaWindow(name:record.window,remaining:nil,durationMinutes:record.durationMinutes,reset:record.serviceResetAt))
        return merge(RenewalEntry(provider:record.provider ?? "codex",bucket:record.bucketID,identity:record.identityFingerprint,window:label,minutes:record.durationMinutes,startedAt:start,endsAt:record.serviceResetAt,recordedAt:record.detectedAt,detectedBetweenReadings:true))
    }
    static func csvCell(_ value:String)->String {
        let first=value.trimmingCharacters(in:.whitespacesAndNewlines).first
        let safe=first.map {"=+-@".contains($0)} == true ? "'"+value : value
        return "\""+safe.replacingOccurrences(of:"\"",with:"\"\"")+"\""
    }
    func csv()->String {
        let date=ISO8601DateFormatter()
        let header=["Provedor","Janela","Início da janela","Próxima renovação","Base do registro","Observado em","Conta identificada","Referência da conta"]
        let rows=ordered.map {row in [row.providerName,row.window,date.string(from:Date(timeIntervalSince1970:row.startedAt)),date.string(from:Date(timeIntervalSince1970:row.endsAt)),row.evidence,date.string(from:row.recordedAt),row.identity == nil ? "Não" : "Sim",row.scopeLabel]}
        return ([header]+rows).map {$0.map(Self.csvCell).joined(separator:",")}.joined(separator:"\r\n")+"\r\n"
    }
    func menu(target:AnyObject,action:Selector)->NSMenu {
        let menu=NSMenu()
        let open=NSMenuItem(title:"Histórico…",action:action,keyEquivalent:"");open.target=target;menu.addItem(open)
        menu.addItem(NSMenuItem.separator())
        let note=NSMenuItem(title:"Últimos 5 por provedor · datas inferidas são identificadas",action:nil,keyEquivalent:"");menu.addItem(note)
        for provider in Self.providers {
            let name=["codex":"Codex","claude":"Claude","zai":"Z.ai","kimi":"Kimi Code","grok":"Grok"][provider]!
            let parent=NSMenuItem(title:name,action:nil,keyEquivalent:"");let sub=NSMenu()
            let rows=recent(provider)
            if rows.isEmpty {sub.addItem(NSMenuItem(title:"Aguardando início ou duração de janela conhecidos",action:nil,keyEquivalent:""))}
            for row in rows {
                let title=row.window+" · "+localDate(Date(timeIntervalSince1970:row.startedAt))
                let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let detail=NSMenu()
                for text in [row.evidence,"Próxima renovação: "+localDate(Date(timeIntervalSince1970:row.endsAt)),"Observado em: "+localDate(row.recordedAt),row.scopeLabel] {detail.addItem(NSMenuItem(title:text,action:nil,keyEquivalent:""))}
                item.submenu=detail;sub.addItem(item)
            }
            parent.submenu=sub;parent.representedObject=provider;menu.addItem(parent)
        }
        return menu
    }
}

func refreshUtilityActivation(excluding:NSWindow) {
    let another=NSApp.windows.contains {$0 !== excluding && !($0 is NSPanel) && $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized)}
    NSApp.setActivationPolicy(another ? .regular : .accessory)
}
final class RenewalHistoryWindow:NSObject,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
    private(set) var window:NSWindow?
    let table=NSTableView()
    var history=RenewalHistory()
    var persistenceMessage:String?
    private var summary:NSTextField?
    private var rows:[RenewalEntry]=[]
    let columns=[("provider","Provedor",110.0),("window","Janela",110),("start","Início da janela",180),("end","Próxima renovação",180),("basis","Base do registro",280),("observed","Observado em",180),("scope","Conta",160)]
    func update(_ value:RenewalHistory) {history=value;rows=history.ordered;table.reloadData();summary?.stringValue=persistenceMessage ?? "\(history.entries.count) registros · datas inferidas não confirmam o instante exato do reset."}
    func show(_ value:RenewalHistory) {
        if window==nil {
            let width=min(1100,NSScreen.main?.visibleFrame.width ?? 1100)-40
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:600),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            w.title="Histórico de renovações · PlanMeter";w.isReleasedWhenClosed=false;w.delegate=self;w.minSize=NSSize(width:700,height:400)
            let content=NSView(frame:NSRect(x:0,y:0,width:width,height:600));w.contentView=content
            let title=NSTextField(labelWithString:"Histórico completo");title.font = .systemFont(ofSize:21,weight:.semibold);title.frame=NSRect(x:20,y:554,width:400,height:28);title.autoresizingMask=[.minYMargin];content.addSubview(title)
            let note=NSTextField(labelWithString:"");note.font = .systemFont(ofSize:13);note.textColor = .secondaryLabelColor;note.frame=NSRect(x:20,y:528,width:width-200,height:22);note.autoresizingMask=[.width,.minYMargin];content.addSubview(note);summary=note
            let export=NSButton(title:"Exportar CSV…",target:self,action:#selector(exportCSV));export.bezelStyle = .rounded;export.frame=NSRect(x:width-170,y:550,width:150,height:30);export.autoresizingMask=[.minXMargin,.minYMargin];content.addSubview(export)
            for (key,title,width) in columns {let col=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(key));col.title=title;col.width=width;table.addTableColumn(col)}
            table.delegate=self;table.dataSource=self;table.rowHeight=30;table.usesAlternatingRowBackgroundColors=true;table.allowsMultipleSelection=true
            table.setAccessibilityLabel("Histórico completo de renovações")
            let scroll=NSScrollView(frame:NSRect(x:20,y:20,width:width-40,height:496));scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.documentView=table;content.addSubview(scroll)
            w.center();window=w
        }
        update(value);NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    func numberOfRows(in tableView:NSTableView)->Int {history.entries.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        guard rows.indices.contains(row) else{return nil}
        let value=rows[row],key=tableColumn?.identifier.rawValue ?? ""
        let text:String
        switch key {
        case "provider":text=value.providerName
        case "window":text=value.window
        case "start":text=localDate(Date(timeIntervalSince1970:value.startedAt))
        case "end":text=localDate(Date(timeIntervalSince1970:value.endsAt))
        case "basis":text=value.evidence
        case "scope":text=value.scopeLabel
        default:text=localDate(value.recordedAt)
        }
        let field=NSTextField(labelWithString:text);field.font = .systemFont(ofSize:13);field.lineBreakMode = .byTruncatingTail;field.toolTip=text+(value.identity == nil ? " · conta não identificada pela fonte" : "");return field
    }
    @objc func exportCSV() {
        guard !CommandLine.arguments.contains(where:{$0.hasSuffix("-self-test")}) else{return}
        let panel=NSSavePanel();panel.allowedContentTypes=[.commaSeparatedText];panel.nameFieldStringValue="planmeter-historico.csv"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try ("\u{FEFF}"+history.csv()).write(to:url,atomically:true,encoding:.utf8)}
        catch {let alert=NSAlert();alert.messageText="Não foi possível exportar o histórico";alert.runModal()}
    }
    func windowWillClose(_ notification:Notification) {if let window=window {refreshUtilityActivation(excluding:window)}}
}

func runRenewalHistoryTests() {
    var count=0
    func check(_ condition:Bool,_ message:String) {guard condition else{fatalError("renewal history: "+message)};count += 1}
    let now=Date(timeIntervalSince1970:1800000000)
    func snapshot(_ provider:String,_ reset:Double,_ minutes:Int?=300)->QuotaSnapshot {
        var result=QuotaSnapshot(queriedAt:now,windows:[QuotaWindow(name:minutes==300 ? "5h" : "Mensal",remaining:70,durationMinutes:minutes,reset:reset)])
        result.provider=provider;result.bucketID=provider+":quota";return result
    }
    var history=RenewalHistory()
    var persistenceMessage:String?;let first=snapshot("codex",1800003600)
    check(history.ingest(first),"known window inferred")
    check(history.entries[0].startedAt==1799985600 && !history.entries[0].startReported,"subtract actual duration")
    check(!history.ingest(first) && history.entries.count==1,"repeated reads never duplicate")
    var known=first;known.identityFingerprint="synthetic-account"
    check(history.ingest(known) && history.entries.count==1,"identity upgrade merges the same window")
    var another=known;another.identityFingerprint="another-account"
    check(history.ingest(another) && history.entries.count==2,"different identified accounts stay separate")
    check(!history.ingest(snapshot("zai",1800003600,nil)),"no invented duration for unknown window")
    var monthly=snapshot("grok",1800003600,nil)
    var window=monthly.windows[0];window.startedAt=1799900000
    monthly=QuotaSnapshot(queriedAt:now,windows:[window]);monthly.provider="grok";monthly.bucketID="grok:unified"
    check(history.ingest(monthly) && history.entries.last?.startReported==true,"provider start works without a fixed month duration")
    check(!history.ingest(snapshot("zai",1900000000)),"future start cannot be a historical reset")
    for index in 1...12 { _ = history.ingest(snapshot("kimi",1800003600-Double(index)*18000)) }
    check(history.recent("kimi").count==5,"menu capped per provider")
    check(history.entries.filter {$0.provider=="kimi"}.count==12,"complete history retained")
    let restored=try! JSONDecoder().decode(RenewalHistory.self,from:JSONEncoder().encode(history))
    check(restored.entries==history.entries,"history survives restart")
    let csv=history.csv();check(csv.components(separatedBy:"\r\n").count==history.entries.count+2,"CSV contains every row")
    check(RenewalHistory.csvCell("=SUM(A1)")=="\"'=SUM(A1)\"","CSV formula protection")
    check(RenewalHistory.csvCell("a,\"b\"")=="\"a,\"\"b\"\"\"","CSV quote escaping")
    var merged=RenewalHistory()
    let record=ResetRecord(id:"fixture",identityFingerprint:"synthetic-account",bucketID:"codex:quota",window:"5h",durationMinutes:300,detectedAt:now,previousServiceResetAt:1799985600,serviceResetAt:1800003600,previousUsedPercent:70,usedPercent:0,acknowledgedAt:nil)
    _ = merged.ingest(known);_ = merged.importDetection(record)
    check(merged.entries.count==1 && merged.entries[0].detectedBetweenReadings,"observed detection upgrades inference without duplication")
    print("PASS renewal history: \(count) checks; fixtures only")
}
func runRenewalHistoryUITests() {
    let history=RenewalHistory();let historyWindow=RenewalHistoryWindow();historyWindow.show(history)
    let settings=SettingsWindow();settings.show()
    settings.window?.close()
    guard NSApp.activationPolicy() == .regular else{fatalError("history remains reachable after settings closes")}
    historyWindow.window?.close()
    guard NSApp.activationPolicy() == .accessory else{fatalError("last utility window restores menu bar mode")}
    print("PASS renewal history UI: independent window and activation lifecycle; no export dialog")
}
