import Foundation
import Security
import LocalAuthentication

enum KeychainStore {
    static let service = "io.github.pcarielo.planmeter.zai"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "quota"]
    }
    static func read() -> String? {
        guard !Runtime.isTest else { return nil }
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        guard !Runtime.isTest, !key.isEmpty, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            throw QuotaError.message("Chave inválida ou operação indisponível em teste")
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var new = query
            new[kSecValueData as String] = data
            new[kSecAttrLabel as String] = "PlanMeter Z.ai quota"
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw QuotaError.message("Não foi possível salvar a chave no Keychain") }
        } else if status != errSecSuccess { throw QuotaError.message("Não foi possível atualizar a chave no Keychain") }
    }
    static func remove() throws {
        guard !Runtime.isTest else { throw QuotaError.message("Operação indisponível em teste") }
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw QuotaError.message("Não foi possível remover a chave do Keychain") }
    }
}
