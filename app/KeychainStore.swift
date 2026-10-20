import Foundation

enum KeychainStore {
    static let service = "io.github.pcarielo.planmeter.zai"
    static var needsAuthorization:Bool {CredentialAccess.requiresAuthorization(service)}
    static func read()->String? {CredentialAccess.read(service)}
    static func authorize()->Bool {CredentialAccess.read(service,interactive:true) != nil}
    static func save(_ key:String)throws {try CredentialAccess.save(key,service:service,label:"Z.ai quota")}
    static func remove()throws {try CredentialAccess.remove(service)}
}
