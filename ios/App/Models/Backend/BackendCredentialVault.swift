import Foundation
import Security

struct BackendCredentialVault {
  private let service = "hybrd.backend.session.v1"
  func read(environment: BackendEnvironment) throws -> BackendSession.Credential? {
    var query = base(environment)
    query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw VaultError.status(status) }
    return try JSONDecoder().decode(BackendSession.Credential.self, from: data)
  }
  func write(_ credential: BackendSession.Credential?, environment: BackendEnvironment) throws {
    let query = base(environment)
    guard let credential else {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.status(status) }; return
    }
    let data = try JSONEncoder().encode(credential)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if status == errSecItemNotFound {
      var add = query; add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      let result = SecItemAdd(add as CFDictionary, nil)
      guard result == errSecSuccess else { throw VaultError.status(result) }
    } else if status != errSecSuccess { throw VaultError.status(status) }
  }
  private func base(_ env: BackendEnvironment) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: env.storageID, kSecAttrSynchronizable as String: false]
  }
  enum VaultError: Error { case status(OSStatus) }
}
