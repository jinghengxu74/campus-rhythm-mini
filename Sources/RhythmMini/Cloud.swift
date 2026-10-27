import Foundation
import Security
import RhythmCore

struct AccountSession: Codable {
    struct User: Codable { let id: String; let email: String? }
    let access_token: String
    let refresh_token: String
    let expires_at: Double?
    let user: User
}

enum MiniError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

enum SessionVault {
    static let service = "com.campusrhythm.mini.session"
    static func read() -> AccountSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: "account", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }
    static func save(_ session: AccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "account"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MiniError.message("Could not save this session in Keychain.") }
        } else if status != errSecSuccess { throw MiniError.message("Could not update this session in Keychain.") }
    }
    static func clear() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "account"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MiniError.message("Could not remove the saved session. Unlock Keychain and retry.") }
    }
}

struct PublicConfig: Decodable {
    let url: String
    let publishableKey: String
    func validatedURL() throws -> URL {
        guard let u = URL(string: url), u.scheme == "https", u.host?.hasSuffix(".supabase.co") == true,
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/",
              publishableKey.range(of: "^sb_publishable_[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw MiniError.message("Account service configuration is invalid.")
        }
        return u
    }
}

struct CloudSnapshot: Decodable { let revision: Int; let plan: PlanDocument }

struct CloudAPI {
    let config: PublicConfig
    static func connect() async throws -> CloudAPI {
        var req = URLRequest(url: URL(string: "https://campus-rhythm-one.vercel.app/api/client-config")!)
        req.timeoutInterval = 15; req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MiniError.message("Account service is unavailable. Local mode still works.") }
        let config = try JSONDecoder().decode(PublicConfig.self, from: data)
        _ = try config.validatedURL(); return CloudAPI(config: config)
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, session: AccountSession? = nil) async throws -> Data {
        let base = try config.validatedURL()
        guard let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw MiniError.message("Invalid request.") }
        var req = URLRequest(url: url); req.httpMethod = method; req.httpBody = body
        req.timeoutInterval = 18; req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session { req.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if String(data: data, encoding: .utf8)?.contains("revision_conflict") == true {
                throw MiniError.message("Your plan changed elsewhere. Nothing was overwritten. Refresh, then try again.")
            }
            if code == 400 || code == 401 { throw MiniError.message("Sign-in expired or the email/password was not accepted. Sign in again.") }
            if code == 429 { throw MiniError.message("Too many requests. Please wait before trying again.") }
            throw MiniError.message("Account service could not complete this request. No cloud change was confirmed.")
        }
        return data
    }
    func signIn(email: String, password: String) async throws -> AccountSession {
        let data = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try JSONDecoder().decode(AccountSession.self, from: await request("/auth/v1/token?grant_type=password", method: "POST", body: data))
    }
    func refresh(_ session: AccountSession) async throws -> AccountSession {
        let data = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refresh_token])
        return try JSONDecoder().decode(AccountSession.self, from: await request("/auth/v1/token?grant_type=refresh_token", method: "POST", body: data))
    }
    func read(_ session: AccountSession) async throws -> CloudSnapshot {
        guard UUID(uuidString: session.user.id) != nil else { throw MiniError.message("Account identity is invalid.") }
        let data = try await request("/rest/v1/rhythm_snapshots?select=revision,plan&user_id=eq.\(session.user.id)", session: session)
        let snapshots = try JSONDecoder().decode([CloudSnapshot].self, from: data)
        guard let snapshot = snapshots.first, snapshot.plan.isValid else { throw MiniError.message("No saved plan is available. Finish account setup in the web app first.") }
        return snapshot
    }
    func save(_ plan: PlanDocument, revision: Int, session: AccountSession) async throws -> Int {
        guard plan.isValid else { throw MiniError.message("The plan format could not be verified. Nothing was sent.") }
        let value: JSONValue = .object(["expected_revision": .number(Double(revision)), "new_plan": .object(plan.fields), "new_health": .null, "health_mode": .string("keep")])
        let response = try await request("/rest/v1/rpc/save_rhythm", method: "POST", body: JSONEncoder().encode(value), session: session)
        return try JSONDecoder().decode(Int.self, from: response)
    }
}
