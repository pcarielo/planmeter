import Foundation

struct LocalizedMessage:ExpressibleByStringLiteral,ExpressibleByStringInterpolation {
    let key:String
    let arguments:[String]
    init(stringLiteral value:String){key=value;arguments=[]}
    init(stringInterpolation value:StringInterpolation){key=value.key;arguments=value.arguments}
    struct StringInterpolation:StringInterpolationProtocol {
        var key=""
        var arguments:[String]=[]
        init(literalCapacity:Int,interpolationCount:Int){key.reserveCapacity(literalCapacity);arguments.reserveCapacity(interpolationCount)}
        mutating func appendLiteral(_ value:String){key += value}
        mutating func appendInterpolation<T>(_ value:T){arguments.append(String(describing:value));key += "%\(arguments.count)$@"}
    }
}
func L(_ message:LocalizedMessage)->String {L10n.render(message.key,arguments:message.arguments)}

// Localization changes presentation only. Provider IDs, quota window identities,
// stored history and authentication do not pass through this catalog.
enum L10n {
    struct Choice {let code:String;let name:String}
    static let languages=["en","es","pt-BR","ko","ja","fr","zh-Hant","hi"]
    static let supportedSelections=Set(languages+["system"])
    private static var testMode:Bool {Runtime.isTest || CommandLine.arguments.contains{$0.hasSuffix("-self-test")}}
    private static let savedSelection:String = {
        guard !testMode,
              let data=try? Data(contentsOf:Runtime.stateDirectory.appendingPathComponent("interface-preferences.json")),
              let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let value=object["language"] as? String,supportedSelections.contains(value) else{return "system"}
        return value
    }()
    private static var activeCode=resolvedCode(selection:savedSelection,preferredLanguage:Locale.preferredLanguages.first)
    private static let lock=NSRecursiveLock()
    private static var cache:[String:[String:String]]=[:]
    private static var testCode:String?
    static var code:String {
        lock.lock();defer{lock.unlock()}
        if testMode {return testCode ?? "pt-BR"}
        return activeCode
    }
    private struct MessageRecord {let key:String;let arguments:[String]}
    private static var rendered:[String:MessageRecord]=[:]
    private static var renderedOrder:[String]=[]
    private static var renderedDates:[String:Date]=[:]
    @discardableResult static func apply(selection:String)->Bool {
        let next=resolvedCode(selection:selection,preferredLanguage:Locale.preferredLanguages.first)
        lock.lock();defer{lock.unlock()}
        let previous=testMode ? (testCode ?? "pt-BR") : activeCode
        if testMode {testCode=next} else {activeCode=next}
        return previous != next
    }
    static func rememberDate(_ text:String,date:Date) {
        lock.lock();defer{lock.unlock()}
        if renderedDates.count>512 {renderedDates.removeAll()}
        renderedDates[text]=date
    }
    // Presentation only: never pass model IDs, paths or persisted data through this.
    static func relocalized(_ text:String)->String {
        lock.lock();defer{lock.unlock()}
        if let record=rendered[text] {
            let arguments=record.arguments.map {value in renderedDates[value].map{localDate($0)} ?? value}
            return render(record.key,arguments:arguments)
        }
        if catalog("pt-BR")[text] != nil {return render(text)}
        for language in languages where language != code {
            if let key=catalog(language).first(where:{$0.value==text && !$0.key.contains("$@")})?.key {return render(key)}
        }
        return text
    }
    static func resolvedCode(selection:String,preferredLanguage:String?)->String {
        if languages.contains(selection){return selection}
        let value=(preferredLanguage ?? "en").replacingOccurrences(of:"_",with:"-").lowercased()
        let parts=value.split(separator:"-").map(String.init)
        guard let primary=parts.first else{return "en"}
        if primary=="pt" {return "pt-BR"}
        if primary=="zh" {
            if parts.contains("hans"){return "en"}
            return parts.contains("hant") || !Set(parts).isDisjoint(with:["tw","hk","mo"]) ? "zh-Hant" : "en"
        }
        return ["en","es","ko","ja","fr","hi"].contains(primary) ? primary : "en"
    }
    static var locale:Locale {Locale(identifier:["en":"en_US","es":"es_ES","pt-BR":"pt_BR","ko":"ko_KR","ja":"ja_JP","fr":"fr_FR","zh-Hant":"zh_TW","hi":"hi_IN"][code] ?? "en_US")}
    static func decimal(_ value:Double)->String {String(format:"%.1f",locale:locale,value)}
    static var choices:[Choice] {
        [Choice(code:"system",name:L("Idioma do sistema"))]+[
            Choice(code:"en",name:"English"),Choice(code:"es",name:"Español"),Choice(code:"pt-BR",name:"Português"),
            Choice(code:"ko",name:"한국어"),Choice(code:"ja",name:"日本語"),Choice(code:"fr",name:"Français"),
            Choice(code:"zh-Hant",name:"繁體中文"),Choice(code:"hi",name:"हिन्दी")]
    }
    static func catalog(_ language:String)->[String:String] {
        lock.lock();defer{lock.unlock()}
        if let value=cache[language]{return value}
        let value: [String:String]
        if let url=Bundle.main.url(forResource:language,withExtension:"json",subdirectory:"Locales"),
           let data=try? Data(contentsOf:url),let decoded=try? JSONDecoder().decode([String:String].self,from:data){value=decoded}
        else{value=[:]}
        cache[language]=value;return value
    }
    static func render(_ key:String,arguments:[String]=[],language:String?=nil)->String {
        let language=language ?? code
        let template=catalog(language)[key] ?? catalog("en")[key] ?? key
        let result=substitute(template,arguments:arguments)
        lock.lock()
        if rendered[result]==nil {renderedOrder.append(result)}
        rendered[result]=MessageRecord(key:key,arguments:arguments)
        if renderedOrder.count>4096 {
            for value in renderedOrder.prefix(512){rendered.removeValue(forKey:value)}
            renderedOrder.removeFirst(512)
        }
        lock.unlock()
        return result
    }
    static func substitute(_ template:String,arguments:[String])->String {
        let regex=try! NSRegularExpression(pattern:"%([1-9][0-9]*)\\$@")
        var result=template
        for match in regex.matches(in:template,range:NSRange(template.startIndex...,in:template)).reversed() {
            guard let indexRange=Range(match.range(at:1),in:template),let number=Int(template[indexRange]),
                  arguments.indices.contains(number-1),let range=Range(match.range,in:result) else{continue}
            result.replaceSubrange(range,with:arguments[number-1])
        }
        return result
    }
    static func withTestLanguage<T>(_ value:String,_ body:()->T)->T {
        precondition(Runtime.isTest && languages.contains(value))
        lock.lock();let previous=testCode;testCode=value;lock.unlock()
        defer{lock.lock();testCode=previous;lock.unlock()}
        return body()
    }
}
