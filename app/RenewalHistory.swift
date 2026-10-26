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
    var inferenceAdjusted=false
    var evidence:String {
        (detectedBetweenReadings ? "Detectado entre leituras · " : "") + (startReported ? "início informado" : "início inferido") + (inferenceAdjusted && !detectedBetweenReadings && !startReported ? " · prazo alterado" : "")
    }
    var scopeLabel:String {identity.map {"Conta "+String($0.prefix(8))} ?? "Conta não identificada"}
    var providerName:String { ["codex":"Codex","claude":"Claude","zai":"Z.ai","kimi":"Kimi Code","grok":"Grok"][provider] ?? provider }
}
extension RenewalEntry {
    enum CodingKeys:String,CodingKey {case id,provider,bucket,identity,window,minutes,startedAt,endsAt,recordedAt,startReported,detectedBetweenReadings,inferenceAdjusted}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decodeIfPresent(String.self,forKey:.id) ?? UUID().uuidString
        provider=try c.decode(String.self,forKey:.provider);bucket=try c.decode(String.self,forKey:.bucket)
        identity=try c.decodeIfPresent(String.self,forKey:.identity);window=try c.decode(String.self,forKey:.window)
        minutes=try c.decodeIfPresent(Int.self,forKey:.minutes)
        startedAt=try c.decode(Double.self,forKey:.startedAt);endsAt=try c.decode(Double.self,forKey:.endsAt)
        recordedAt=try c.decode(Date.self,forKey:.recordedAt)
        startReported=try c.decodeIfPresent(Bool.self,forKey:.startReported) ?? false
        detectedBetweenReadings=try c.decodeIfPresent(Bool.self,forKey:.detectedBetweenReadings) ?? false
        inferenceAdjusted=try c.decodeIfPresent(Bool.self,forKey:.inferenceAdjusted) ?? false
    }
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
            abs(entry.endsAt-value.endsAt)<=tolerance
        }) {
            var updated=entries[index]
            if value.detectedBetweenReadings && !updated.detectedBetweenReadings {updated.detectedBetweenReadings=true;updated.recordedAt=value.recordedAt}
            if value.startReported && !updated.startReported {updated.startReported=true;updated.startedAt=value.startedAt;updated.endsAt=value.endsAt}
            if updated.identity==nil, value.identity != nil {updated.identity=value.identity;updated.recordedAt=value.recordedAt}
            if updated.bucket.contains("unknown") || updated.bucket=="grok:subscription" {updated.bucket=value.bucket}
            guard updated != entries[index] else{return false}
            entries[index]=updated;return true
        }
        var candidate=value
        if !candidate.startReported && !candidate.detectedBetweenReadings,
           let index=entries.indices.filter({index in
               let old=entries[index]
               return old.provider==value.provider && old.window==value.window && old.minutes==value.minutes && old.identity==value.identity && old.bucket==value.bucket && value.startedAt<old.endsAt-tolerance && value.endsAt>old.startedAt+tolerance
           }).max(by:{entries[$0].recordedAt<entries[$1].recordedAt}) {
            candidate.inferenceAdjusted=true
            if !entries[index].startReported && !entries[index].detectedBetweenReadings {
                guard candidate.recordedAt>=entries[index].recordedAt else{return false}
                candidate.id=entries[index].id;entries[index]=candidate;return true
            }
        }
        entries.append(candidate);return true
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
    func csv(exportRows:[RenewalEntry]?=nil)->String {
        let date=ISO8601DateFormatter()
        let header=["Provedor","Janela","Início da janela","Próxima renovação","Base do registro","Observado em","Conta identificada","Referência da conta"]
        let rows=(exportRows ?? ordered).map {row in [row.providerName,row.window,date.string(from:Date(timeIntervalSince1970:row.startedAt)),date.string(from:Date(timeIntervalSince1970:row.endsAt)),row.evidence,date.string(from:row.recordedAt),row.identity == nil ? "Não" : "Sim",row.scopeLabel]}
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
                let tag=row.detectedBetweenReadings ? "detectado" : row.startReported ? "informado" : row.inferenceAdjusted ? "inferido · prazo alterado" : "inferido"
                let title=row.window+" · "+localDate(Date(timeIntervalSince1970:row.startedAt))+" · "+tag
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
    private(set) var rows:[RenewalEntry]=[]
    let columns=[("provider","Provedor",110.0),("window","Janela",110),("start","Início da janela",180),("end","Próxima renovação",180),("basis","Base do registro",280),("observed","Observado em",180),("scope","Conta",160)]
    func update(_ value:RenewalHistory) {history=value;sortRows();summary?.stringValue=persistenceMessage ?? "\(history.entries.count) registros · datas inferidas não confirmam o instante exato do reset."}
    func show(_ value:RenewalHistory) {
        if window==nil {
            let width=min(1100,NSScreen.main?.visibleFrame.width ?? 1100)-40
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:600),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            w.title="Histórico de renovações · PlanMeter";w.isReleasedWhenClosed=false;w.delegate=self;w.minSize=NSSize(width:700,height:400)
            let content=NSView(frame:NSRect(x:0,y:0,width:width,height:600));w.contentView=content
            let title=NSTextField(labelWithString:"Histórico completo");title.font = .systemFont(ofSize:21,weight:.semibold);title.frame=NSRect(x:20,y:554,width:400,height:28);title.autoresizingMask=[.minYMargin];content.addSubview(title)
            let note=NSTextField(labelWithString:"");note.font = .systemFont(ofSize:13);note.textColor = .secondaryLabelColor;note.frame=NSRect(x:20,y:528,width:width-200,height:22);note.autoresizingMask=[.width,.minYMargin];content.addSubview(note);summary=note
            let export=NSButton(title:"Exportar CSV…",target:self,action:#selector(exportCSV));export.bezelStyle = .rounded;export.frame=NSRect(x:width-170,y:550,width:150,height:30);export.autoresizingMask=[.minXMargin,.minYMargin];content.addSubview(export)
            for (key,title,width) in columns {let col=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(key));col.title=title;col.width=width;col.sortDescriptorPrototype=NSSortDescriptor(key:key,ascending:!["start","end","observed"].contains(key));table.addTableColumn(col)}
            table.sortDescriptors=[NSSortDescriptor(key:"start",ascending:false)]
            table.delegate=self;table.dataSource=self;table.rowHeight=30;table.usesAlternatingRowBackgroundColors=true;table.allowsMultipleSelection=true
            table.setAccessibilityLabel("Histórico completo de renovações")
            let scroll=NSScrollView(frame:NSRect(x:20,y:20,width:width-40,height:496));scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.documentView=table;content.addSubview(scroll)
            w.center();window=w
        }
        update(value);NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    static func sorted(_ values:[RenewalEntry],by descriptors:[NSSortDescriptor])->[RenewalEntry] {
        func compare(_ a:RenewalEntry,_ b:RenewalEntry,key:String)->ComparisonResult {
            func number(_ a:Double,_ b:Double)->ComparisonResult {a<b ? .orderedAscending : a>b ? .orderedDescending : .orderedSame}
            switch key {
            case "start":return number(a.startedAt,b.startedAt)
            case "end":return number(a.endsAt,b.endsAt)
            case "observed":return number(a.recordedAt.timeIntervalSince1970,b.recordedAt.timeIntervalSince1970)
            case "provider":return a.providerName.localizedStandardCompare(b.providerName)
            case "window":return a.window.localizedStandardCompare(b.window)
            case "basis":return a.evidence.localizedStandardCompare(b.evidence)
            case "scope":return a.scopeLabel.localizedStandardCompare(b.scopeLabel)
            default:return .orderedSame
            }
        }
        return values.sorted {a,b in
            for descriptor in descriptors {
                let comparison=compare(a,b,key:descriptor.key ?? "")
                if comparison != .orderedSame {return descriptor.ascending ? comparison == .orderedAscending : comparison == .orderedDescending}
            }
            return a.startedAt == b.startedAt ? a.id<b.id : a.startedAt>b.startedAt
        }
    }
    private func sortRows() {
        let selected=Set(table.selectedRowIndexes.compactMap {rows.indices.contains($0) ? rows[$0].id : nil})
        rows=Self.sorted(history.entries,by:table.sortDescriptors)
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter {selected.contains(rows[$0].id)}),byExtendingSelection:false)
    }
    func tableView(_ tableView:NSTableView,sortDescriptorsDidChange oldDescriptors:[NSSortDescriptor]) {sortRows()}
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
        do {try ("\u{FEFF}"+history.csv(exportRows:rows)).write(to:url,atomically:true,encoding:.utf8)}
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
    var corrected=RenewalHistory();_ = corrected.ingest(known)
    var explicit=known;var explicitWindow=known.windows[0];explicitWindow.startedAt=1799985000
    explicit=QuotaSnapshot(queriedAt:now,windows:[explicitWindow]);explicit.provider="codex";explicit.bucketID=known.bucketID;explicit.identityFingerprint=known.identityFingerprint
    _ = corrected.ingest(explicit)
    check(corrected.entries.count==1 && corrected.entries[0].startReported && corrected.entries[0].startedAt==1799985000,"provider start corrects an inference without a duplicate")
    var sliding=RenewalHistory()
    for offset in 0...20 {_ = sliding.ingest(snapshot("zai",1800003600+Double(offset)*60))}
    check(sliding.entries.count==1 && sliding.entries[0].inferenceAdjusted,"overlapping inferred deadline shifts update one estimate")
    func knownEntry(_ value:RenewalHistory)->RenewalEntry {value.entries[0]}
    let latestEstimate=sliding.entries[0].endsAt
    var oldEstimate=snapshot("zai",1800003600+150);oldEstimate=QuotaSnapshot(queriedAt:now.addingTimeInterval(-10),windows:oldEstimate.windows);oldEstimate.provider="zai";oldEstimate.bucketID="zai:quota"
    check(!sliding.ingest(oldEstimate) && sliding.entries[0].endsAt==latestEstimate,"older cached data cannot rewind the latest estimate")
    var legacy=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(knownEntry(history))) as! [String:Any]
    for key in ["id","startReported","detectedBetweenReadings","inferenceAdjusted"] {legacy.removeValue(forKey:key)}
    check((try? JSONDecoder().decode(RenewalEntry.self,from:JSONSerialization.data(withJSONObject:legacy))) != nil,"optional metadata does not invalidate an old entry")
    for key in ["provider","window","start","end","basis","observed","scope"] {
        var low=history.entries[0],high=history.entries[0]
        low.id="a";high.id="b";low.provider="claude";high.provider="zai";low.window="5 horas";high.window="Semanal"
        low.startedAt=1700000000;high.startedAt=1800000000;low.endsAt=1700010000;high.endsAt=1800010000
        low.recordedAt=Date(timeIntervalSince1970:1700000000);high.recordedAt=now
        low.identity="a";high.identity="z";low.startReported=false;high.startReported=true
        low.detectedBetweenReadings=false;high.detectedBetweenReadings=false;low.inferenceAdjusted=false;high.inferenceAdjusted=false
        let ascending=RenewalHistoryWindow.sorted([high,low],by:[NSSortDescriptor(key:key,ascending:true)])
        let descending=RenewalHistoryWindow.sorted([low,high],by:[NSSortDescriptor(key:key,ascending:false)])
        check(ascending.first?.id=="a" && descending.first?.id=="b","ascending and descending column "+key)
    }
    print("PASS renewal history: \(count) checks; fixtures only")
}
func runRenewalHistoryUITests() {
    var history=RenewalHistory()
    for provider in ["zai","claude"] {
        var snapshot=QuotaSnapshot(queriedAt:Date(),windows:[QuotaWindow(name:"5h",remaining:50,durationMinutes:300,reset:Date().addingTimeInterval(3600).timeIntervalSince1970)])
        snapshot.provider=provider;_ = history.ingest(snapshot)
    }
    let historyWindow=RenewalHistoryWindow();historyWindow.show(history)
    guard historyWindow.table.tableColumns.allSatisfy({$0.sortDescriptorPrototype != nil}) else{fatalError("all columns must be sortable")}
    historyWindow.table.sortDescriptors=[NSSortDescriptor(key:"provider",ascending:true)]
    historyWindow.tableView(historyWindow.table,sortDescriptorsDidChange:[]);historyWindow.update(history)
    guard historyWindow.rows.first?.provider=="claude" else{fatalError("selected sort survives data refresh")}
    guard history.csv(exportRows:historyWindow.rows).components(separatedBy:"\r\n")[1].hasPrefix("\"Claude\"") else{fatalError("export follows the displayed ordering")}
    let settings=SettingsWindow();settings.show();settings.window?.close()
    guard NSApp.activationPolicy() == .regular else{fatalError("history remains reachable after settings closes")}
    settings.show()
    let menuApp=MenuApp();menuApp.configureMainMenu()
    historyWindow.window?.makeKeyAndOrderFront(nil);historyWindow.window?.makeKey();NSApp.mainMenu?.update()
    let close=NSApp.mainMenu?.items.first(where:{$0.title=="Arquivo"})?.submenu?.items.first
    guard close?.keyEquivalent=="w",close?.target==nil else{fatalError("close shortcut must use the responder chain")}
    let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:historyWindow.window!.windowNumber,context:nil,characters:"w",charactersIgnoringModifiers:"w",isARepeat:false,keyCode:13)!
    // Isolated/background test runners may have no system key window.
    // In that case verify the menu's native action against the intended window.
    let handled:Bool
    if NSApp.keyWindow === historyWindow.window {handled=NSApp.mainMenu?.performKeyEquivalent(with:event) ?? false}
    else {handled=NSApp.sendAction(close!.action!,to:historyWindow.window,from:close)}
    guard handled,historyWindow.window?.isVisible==false,settings.window?.isVisible==true else{fatalError("configured close action closes only the history window")}
    let quit=NSApp.mainMenu?.items.first?.submenu?.items.first(where:{$0.keyEquivalent=="q"})
    guard quit?.action == #selector(MenuApp.quitApp) else{fatalError("Command-Q still targets application termination")}
    settings.window?.close()
    guard NSApp.activationPolicy() == .accessory else{fatalError("last utility window restores menu bar mode")}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("history-corrupt-"+UUID().uuidString)
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:directory)}
    let corrupt=directory.appendingPathComponent("renewal-history.json");try! Data("invalid fixture".utf8).write(to:corrupt)
    let app=MenuApp();app.cacheDirectory=directory;app.loadRenewalHistory()
    let saved=try! FileManager.default.contentsOfDirectory(atPath:directory.path)
    guard let backup=saved.first(where:{$0.hasPrefix("renewal-history.corrupt-")}), (try? Data(contentsOf:directory.appendingPathComponent(backup)))==Data("invalid fixture".utf8) else{fatalError("failed history decode must preserve original bytes")}
    print("PASS renewal history UI: independent window and activation lifecycle; no export dialog")
}
