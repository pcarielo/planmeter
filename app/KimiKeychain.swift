import Foundation

enum KimiKeychain {
    static let service = (Bundle.main.bundleIdentifier ?? "io.github.pcarielo.planmeter") + ".kimi"
    static var needsAuthorization:Bool {CredentialAccess.requiresAuthorization(service)}
    static func read()->String? {CredentialAccess.read(service)}
    static func authorize()->Bool {CredentialAccess.read(service,interactive:true) != nil}
    static func save(_ key:String)throws {try CredentialAccess.save(key,service:service,label:"Kimi Code quota")}
    static func remove()throws {try CredentialAccess.remove(service)}
}
