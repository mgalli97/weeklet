import CryptoKit
import Foundation
import Security

let service = "Weeklet Release Signing"
let account = "com.mgalli97.weeklet.ed25519"
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service, kSecAttrAccount as String: account,
    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
let key: Curve25519.Signing.PrivateKey
if status == errSecSuccess, let data = result as? Data {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else if status == errSecItemNotFound {
    key = Curve25519.Signing.PrivateKey()
    let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: account,
        kSecAttrLabel as String: "Weeklet update signing key",
        kSecValueData as String: key.rawRepresentation]
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        fputs("Could not store the update signing key in Keychain.\n", stderr); exit(1)
    }
} else {
    fputs("Could not read the update signing key from Keychain.\n", stderr); exit(1)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
