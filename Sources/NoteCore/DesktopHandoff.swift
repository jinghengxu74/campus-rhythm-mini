import CryptoKit
import Foundation

public final class DesktopHandoff {
    private var key: P256.KeyAgreement.PrivateKey?
    private let startedAt: Date
    public let state: String
    public let publicKey: String
    public init() {
        let key = P256.KeyAgreement.PrivateKey()
        self.key = key; startedAt = Date(); state = UUID().uuidString + UUID().uuidString
        publicKey = Self.encode(key.publicKey.x963Representation)
    }
    init(privateKey: Data, state: String, startedAt: Date) throws {
        let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        self.key = key; self.state = state; self.startedAt = startedAt
        publicKey = Self.encode(key.publicKey.x963Representation)
    }
    public func open(_ url: URL, now: Date = Date()) throws -> Data {
        guard let key, now.timeIntervalSince(startedAt) >= 0, now.timeIntervalSince(startedAt) < 600,
              url.scheme == "rhythmnote", url.host == "auth", url.path == "/callback", url.user == nil, url.password == nil, url.port == nil, url.query == nil,
              let fragment = url.fragment, fragment.count < 30000,
              let parts = URLComponents(string: "https://localhost/?" + fragment)?.queryItems,
              parts.filter({ $0.name == "state" }).count == 1,
              parts.filter({ $0.name == "key" }).count == 1,
              parts.filter({ $0.name == "box" }).count == 1,
              parts.first(where: { $0.name == "state" })?.value == state,
              let publicData = parts.first(where: { $0.name == "key" })?.value.flatMap(Self.decode),
              let sealed = parts.first(where: { $0.name == "box" })?.value.flatMap(Self.decode), sealed.count < 20000 else { throw CocoaError(.coderReadCorrupt) }
        let remote = try P256.KeyAgreement.PublicKey(x963Representation: publicData)
        let secret = try key.sharedSecretFromKeyAgreement(with: remote)
        let symmetric = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(state.utf8), sharedInfo: Data("Rhythm Note desktop sign-in v1".utf8), outputByteCount: 32)
        let result = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: symmetric)
        self.key = nil
        return result
    }
    private static func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func decode(_ text: String) -> Data? { let value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); return Data(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4)) }
}
