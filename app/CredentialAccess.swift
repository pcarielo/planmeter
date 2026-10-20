import Foundation
import Security
import LocalAuthentication

// Pure session state. Production callers serialize access with the broker lock.
final class CredentialSession {
    private var memory:[String:String]=[:]
    private var statuses:[String:OSStatus]=[:]
    func requiresAuthorization(_ service:String)->Bool {
        guard let status=statuses[service] else{return false}
        return [errSecInteractionNotAllowed,errSecInteractionRequired,errSecAuthFailed,errSecUserCanceled].contains(status)
    }
    func record(_ service:String,status:OSStatus) {statuses[service]=status}
    func saved(_ service:String,key:String) {memory[service]=key;statuses[service]=errSecSuccess}
    func removed(_ service:String) {memory.removeValue(forKey:service);statuses[service]=errSecItemNotFound}
    func read(_ service:String,interactive:Bool,fetch:()->(OSStatus,String?))->String? {
        if !interactive,let value=memory[service] {return value}
        let (status,value)=fetch();statuses[service]=status
        // A fresh explicit denial or deletion supersedes a previous grant.
        if interactive {memory.removeValue(forKey:service)}
        guard status==errSecSuccess,let value=value,!value.isEmpty else{return nil}
        memory[service]=value;return value
    }
}

// The file-based macOS Keychain has its own process-wide UI policy. LAContext
// alone does not cover legacy item ACL dialogs. Serialize every operation here.
enum CredentialAccess {
    private static let lock=NSLock()
    private static let session=CredentialSession()
    static var isTest:Bool {CommandLine.arguments.contains{$0.hasSuffix("-self-test")}}
    static func requiresAuthorization(_ service:String)->Bool {
        lock.lock();defer{lock.unlock()};return session.requiresAuthorization(service)
    }
    static func baseQuery(_ service:String)->[String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"quota"]
    }
    static func readQuery(_ service:String,interactive:Bool)->[String:Any] {
        var query=baseQuery(service)
        query[kSecReturnData as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
        let context=LAContext();context.interactionNotAllowed = !interactive
        query[kSecUseAuthenticationContext as String]=context
        if !interactive {query[kSecUseAuthenticationUI as String]=kSecUseAuthenticationUIFail}
        return query
    }
    // Call under lock in production. Injectable functions keep tests off Keychain.
    static func withPolicy(interactive:Bool,
        get:(UnsafeMutablePointer<DarwinBoolean>)->OSStatus=SecKeychainGetUserInteractionAllowed,
        set:(Bool)->OSStatus=SecKeychainSetUserInteractionAllowed,
        operation:()->OSStatus)->OSStatus {
        var previous=DarwinBoolean(false)
        guard get(&previous)==errSecSuccess,set(interactive)==errSecSuccess else{return errSecInteractionNotAllowed}
        defer{_ = set(previous.boolValue)}
        return operation()
    }
    static func read(_ service:String,interactive:Bool=false)->String? {
        guard !isTest else{return nil}
        lock.lock();defer{lock.unlock()}
        return session.read(service,interactive:interactive) {
            var result:CFTypeRef?
            let query=readQuery(service,interactive:interactive)
            let status=withPolicy(interactive:interactive){SecItemCopyMatching(query as CFDictionary,&result)}
            let value=(result as? Data).flatMap{String(data:$0,encoding:.utf8)}
            return (status,value)
        }
    }

    static func save(_ key:String,service:String,label:String)throws {
        guard !isTest,!key.isEmpty,key.utf8.count<=4096,key.unicodeScalars.allSatisfy({$0.value>=33 && $0.value<=126}) else{throw QuotaError.message("Chave inválida")}
        lock.lock();defer{lock.unlock()}
        let query=baseQuery(service),data=Data(key.utf8)
        let status=withPolicy(interactive:true){
            let updated=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
            guard updated==errSecItemNotFound else{return updated}
            var item=query;item[kSecValueData as String]=data;item[kSecAttrLabel as String]=label
            return SecItemAdd(item as CFDictionary,nil)
        }
        session.record(service,status:status)
        guard status==errSecSuccess else{throw QuotaError.message("Não foi possível salvar a chave no Keychain")}
        session.saved(service,key:key)
    }
    static func remove(_ service:String)throws {
        guard !isTest else{throw QuotaError.message("Operação indisponível em teste")}
        lock.lock();defer{lock.unlock()}
        let status=withPolicy(interactive:true){SecItemDelete(baseQuery(service) as CFDictionary)}
        guard status==errSecSuccess || status==errSecItemNotFound else{throw QuotaError.message("Não foi possível remover a chave do Keychain")}
        session.removed(service)
    }
}

func runCredentialPolicyTests() {
    var count=0
    func check(_ value:Bool,_ name:String){guard value else{fputs("FAIL credential policy: \(name)\n",stderr);exit(1)};count += 1}
    var changes:[Bool]=[];var operations=0
    let result=CredentialAccess.withPolicy(interactive:false,get:{$0.pointee=true;return errSecSuccess},set:{changes.append($0);return errSecSuccess}){operations += 1;return errSecInteractionNotAllowed}
    check(result==errSecInteractionNotAllowed && changes==[false,true] && operations==1,"background disables legacy UI and restores policy on failure")
    changes=[];operations=0
    _=CredentialAccess.withPolicy(interactive:false,get:{$0.pointee=true;return errSecSuccess},set:{_ in errSecAuthFailed}){operations += 1;return errSecSuccess}
    check(operations==0,"cannot suppress UI means no credential read")
    _=CredentialAccess.withPolicy(interactive:true,get:{$0.pointee=false;return errSecSuccess},set:{changes.append($0);return errSecSuccess}){errSecSuccess}
    check(changes==[true,false],"explicit action allows and restores UI policy")
    let query=CredentialAccess.readQuery("synthetic-only",interactive:false)
    check(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String,"query rejects authentication UI")
    check((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed==true,"local authentication also noninteractive")
    check(CredentialAccess.read("synthetic-only")==nil,"tests never read real keychain")
    let state=CredentialSession();var reads=0
    let first=state.read("fixture",interactive:false){reads += 1;return(errSecSuccess,"synthetic-one")}
    check(first=="synthetic-one" && reads==1,"first read caches value")
    check(state.read("fixture",interactive:false){reads += 1;return(errSecAuthFailed,nil)}=="synthetic-one" && reads==1,"poll uses memory without Keychain")
    check(state.read("fixture",interactive:true){reads += 1;return(errSecSuccess,"synthetic-two")}=="synthetic-two" && reads==2,"explicit action bypasses memory")
    check(state.read("fixture",interactive:true){(errSecAuthFailed,nil)}==nil && state.requiresAuthorization("fixture"),"explicit denial clears grant")
    check(state.read("fixture",interactive:false){reads += 1;return(errSecInteractionNotAllowed,nil)}==nil && reads==3,"denied memory is not reused")
    state.saved("fixture",key:"synthetic-three");state.removed("fixture")
    check(state.read("fixture",interactive:false){reads += 1;return(errSecItemNotFound,nil)}==nil && !state.requiresAuthorization("fixture") && reads==4,"remove clears memory and routes to enrollment")
    for status in [errSecInteractionNotAllowed,errSecInteractionRequired,errSecAuthFailed,errSecUserCanceled] {
        state.record("fixture",status:status);check(state.requiresAuthorization("fixture"),"permission status routing")
    }
    print("PASS credential UI policy: \(count) checks; mocked Keychain only")
}
