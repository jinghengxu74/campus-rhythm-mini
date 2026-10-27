import AppKit
import AuthenticationServices
import Foundation
import Security
import NoteCore

struct NoteAccountError: LocalizedError {
    let message: String
    static func message(_ text: String) -> Self { Self(message: text) }
    var errorDescription: String? { message }
}
struct NoteAccountSession: Codable {
    struct User: Codable { let id: String; let email: String? }
    var access_token: String
    var refresh_token: String
    var expires_at: Double?
    var expires_in: Double?
    let user: User
    func withFreshTokens(access: String, refresh: String?, expiresAt: Double?, expiresIn: Double?) -> NoteAccountSession {
        NoteAccountSession(
            access_token: access,
            refresh_token: refresh ?? refresh_token,
            expires_at: expiresAt,
            expires_in: expiresIn,
            user: user
        )
    }
    func normalizedExpiry(at now: Date = Date()) -> NoteAccountSession {
        var next = self
        if let expires_at = next.expires_at, expires_at > 1_000_000_000_000 { next.expires_at = expires_at / 1000 }
        let nowSeconds = now.timeIntervalSince1970
        if next.expires_at == nil || (next.expires_at ?? 0) < nowSeconds + 30 {
            next.expires_at = nowSeconds + (next.expires_in ?? 3600)
        }
        return next
    }
    var isExpired: Bool { (expires_at ?? 0) < Date().timeIntervalSince1970 + 60 }
}
private struct NoteRefreshPayload: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_at: Double?
    let expires_in: Double?
}
/// Session tokens live in the app data folder (mode 600), not Keychain — ad-hoc rebuilds otherwise re-prompt every launch.
private enum NoteSessionVault {
    static let legacyService = "com.campusrhythm.note.account.v1"
    static var fileURL: URL { NoteRepository.directory.appendingPathComponent("account-session-v1.json") }
    private static var legacyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: legacyService, kSecAttrAccount as String: "account"]
    }
    static func read() -> NoteAccountSession? {
        if let file = readFile() { return file.normalizedExpiry() }
        guard let migrated = readLegacyKeychain()?.normalizedExpiry() else { return nil }
        try? save(migrated)
        return migrated
    }
    static func save(_ value: NoteAccountSession) throws {
        let normalized = value.normalizedExpiry()
        try FileManager.default.createDirectory(at: NoteRepository.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(normalized)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        clearLegacyKeychain()
    }
    static func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        clearLegacyKeychain()
    }
    private static func readFile() -> NoteAccountSession? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(NoteAccountSession.self, from: data)
    }
    private static func readLegacyKeychain() -> NoteAccountSession? {
        var q = legacyQuery; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(NoteAccountSession.self, from: data)
    }
    private static func clearLegacyKeychain() {
        SecItemDelete(legacyQuery as CFDictionary)
    }
}
private struct NotePublicConfig: Decodable {
    let url: String; let publishableKey: String
    var base: URL? {
        guard let u = URL(string: url), u.scheme == "https", u.host == "etmyeyemqgsjeupzgjdn.supabase.co", u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/", publishableKey.hasPrefix("sb_publishable_") else { return nil }; return u
    }
}
private struct NoteSnapshot: Decodable { let revision: Int; let plan: [String: PlanValue] }
private final class NoteRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Password/refresh-token requests must never follow a redirect to another endpoint.
        completionHandler(nil)
    }
}
private struct NoteAccountAPI {
    let config: NotePublicConfig
    private static let network: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: NoteRedirectBlocker(), delegateQueue: nil)
    }()
    static func connect() async throws -> Self {
        var req = URLRequest(url: URL(string: "https://campus-rhythm-one.vercel.app/api/client-config")!); req.timeoutInterval = 15; req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await network.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NoteAccountError.message("Campus Rhythm is unavailable. Local notes still work.") }
        let config = try JSONDecoder().decode(NotePublicConfig.self, from: data)
        guard config.base != nil else { throw NoteAccountError.message("The account configuration could not be verified.") }; return Self(config: config)
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, session: NoteAccountSession? = nil) async throws -> Data {
        let url = URL(string: config.base!.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)!
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session { request.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await Self.network.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if String(data: data, encoding: .utf8)?.contains("revision_conflict") == true { throw NoteAccountError.message("The account changed while saving. Retry sync; no remote note was overwritten.") }
            if code == 401 || code == 403 { throw NoteAccountError.message("Sign-in expired. Connect your account again.") }
            if code == 400 { throw NoteAccountError.message("Sign-in or account data was not accepted. Check your details and retry.") }
            throw NoteAccountError.message("The account could not be reached. This Mac’s edits are kept.")
        }; return data
    }
    func signIn(_ email: String, _ password: String) async throws -> NoteAccountSession {
        let data = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try JSONDecoder().decode(NoteAccountSession.self, from: await request("/auth/v1/token?grant_type=password", method: "POST", body: data))
    }
    func refreshed(_ value: NoteAccountSession) async throws -> NoteAccountSession {
        let data = try JSONSerialization.data(withJSONObject: ["refresh_token": value.refresh_token])
        let payload = try JSONDecoder().decode(NoteRefreshPayload.self, from: await request("/auth/v1/token?grant_type=refresh_token", method: "POST", body: data))
        return value.withFreshTokens(access: payload.access_token, refresh: payload.refresh_token, expiresAt: payload.expires_at, expiresIn: payload.expires_in).normalizedExpiry()
    }
    func verify(_ value: NoteAccountSession) async throws {
        let user = try JSONDecoder().decode(NoteAccountSession.User.self, from: await request("/auth/v1/user", session: value))
        guard user.id == value.user.id else { throw NoteAccountError.message("The account identity could not be verified.") }
    }
    func read(_ session: NoteAccountSession) async throws -> NoteSnapshot? {
        guard UUID(uuidString: session.user.id) != nil else { throw NoteAccountError.message("Invalid account identity.") }
        return try JSONDecoder().decode([NoteSnapshot].self, from: await request("/rest/v1/rhythm_snapshots?select=revision,plan&user_id=eq." + session.user.id, session: session)).first
    }
    func save(_ plan: NotePlan, revision: Int, session: NoteAccountSession) async throws -> Int {
        let body: PlanValue = .object(["expected_revision": .number(Decimal(revision)), "new_plan": .object(plan.fields), "new_health": .null, "health_mode": .string("keep")])
        return try JSONDecoder().decode(Int.self, from: await request("/rest/v1/rpc/save_rhythm", method: "POST", body: JSONEncoder().encode(body), session: session))
    }
}

@MainActor final class AccountConnection: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AccountConnection()
    @Published private(set) var email: String?
    @Published private(set) var status = "Local · saved on this Mac"
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var conflict = false
    @Published private(set) var planTasks: [PlanTaskBrief] = []
    private let repository = NoteRepository.shared
    private var resumeCandidate: NoteAccountSession?
    var hasAccountCache: Bool { repository.owner != nil }
    private var api: NoteAccountAPI?
    private var session: NoteAccountSession?
    private var lastSynced: NoteDocument?
    private var generation = 0
    private var debounce: Task<Void, Never>?
    private var poll: Timer?
    private var auth: ASWebAuthenticationSession?
    private var handoff: DesktopHandoff?
    private var baseFile: URL? { session.map { NoteRepository.directory.appendingPathComponent("account-base-" + $0.user.id + ".json") } }
    private func persistBase(_ document: NoteDocument) throws { if let url = baseFile { try NoteFile(url: url).save(document) } }
    func resume() {
        guard session == nil else { return }
        guard let saved = NoteSessionVault.read() else {
            status = "Device-only notes · connect Account to open cloud notes"; return
        }
        email = saved.user.email
        resumeCandidate = saved
        let cache = NoteRepository.directory.appendingPathComponent("account-" + saved.user.id + ".json")
        if UUID(uuidString: saved.user.id) != nil, FileManager.default.fileExists(atPath: cache.path) {
            do {
                let document = try NoteFile(url: cache).load()
                try repository.connect(owner: saved.user.id, document: document, events: [])
                email = saved.user.email; status = "Account cache · checking connection…"
            } catch { status = "Account cache could not open. Original files are kept." }
        }
        Task { await connect(saved) }
    }
    func retryConnection() async { if let value = resumeCandidate { await connect(value) } }
    func signIn(email: String, password: String) async {
        guard !busy else { return }; busy = true; status = "Connecting…"
        do { let api = try await NoteAccountAPI.connect(); self.api = api; let value = try await api.signIn(email.trimmingCharacters(in: .whitespacesAndNewlines), password); busy = false; await connect(value) }
        catch { busy = false; status = error.localizedDescription }
    }
    func connect(_ input: NoteAccountSession) async {
        guard !busy else { return }; busy = true; generation += 1; let ticket = generation
        status = "Loading your account…"
        do {
            let api = try await NoteAccountAPI.connect(); var value = input.normalizedExpiry()
            if value.isExpired { value = try await api.refreshed(value) }
            try await api.verify(value)
            guard let snapshot = try await api.read(value) else { throw NoteAccountError.message("Open Campus Rhythm on the web and finish account setup first.") }
            let plan = try NotePlan(fields: snapshot.plan), remote = try plan.notebook()
            guard ticket == generation else { return }
            try NoteSessionVault.save(value)
            self.api = api; session = value; resumeCandidate = value
            let baseURL = NoteRepository.directory.appendingPathComponent("account-base-" + value.user.id + ".json")
            let cacheURL = NoteRepository.directory.appendingPathComponent("account-" + value.user.id + ".json")
            let base = FileManager.default.fileExists(atPath: baseURL.path) ? try NoteFile(url: baseURL).load() : nil
            let cached = FileManager.default.fileExists(atPath: cacheURL.path) ? try NoteFile(url: cacheURL).load() : nil
            let dirtyCache = NoteSyncRules.hasUnsentCache(base: base, cached: cached, remote: remote)
            let opened = dirtyCache ? cached! : remote
            try repository.connect(owner: value.user.id, document: opened, events: plan.events)
            planTasks = NoteRecommendationBuilder.parseTasks(from: plan.fields)
            Task { await NoteNotifications.reconcile(tasks: planTasks) }
            lastSynced = dirtyCache ? base : remote
            if !dirtyCache { try persistBase(remote) }
            connected = true; email = value.user.email; conflict = dirtyCache && base != remote
            status = conflict ? "Conflict · this Mac and your account both changed" : dirtyCache ? "Changes waiting to sync" : "Synced · " + (value.user.email ?? "Campus Rhythm")
            repository.onLocalEdit = { [weak self] in self?.schedule() }
            poll?.invalidate(); poll = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
            busy = false; if dirtyCache && !conflict { schedule() }
        } catch { if ticket == generation { busy = false; status = (hasAccountCache ? "Account cache · not synced. " : "Device-only notes · ") + error.localizedDescription } }
    }
    private func schedule() {
        guard connected else { return }; if !conflict { status = "Changes waiting to sync" }
        debounce?.cancel(); debounce = Task { try? await Task.sleep(nanoseconds: 800_000_000); guard !Task.isCancelled else { return }; await sync() }
    }
    func sync(forceLocal: Bool = false, useAccount: Bool = false) async {
        guard connected, !busy, (!conflict || forceLocal || useAccount), var value = session, let api else { return }
        busy = true; let ticket = generation; let owner = value.user.id
        defer { if ticket == generation { busy = false } }
        do {
            if value.isExpired {
                value = try await api.refreshed(value)
                guard ticket == generation else { return }; try NoteSessionVault.save(value); session = value
            }
            guard let snapshot = try await api.read(value) else { throw NoteAccountError.message("Your account plan is unavailable. Local edits were kept.") }
            var plan = try NotePlan(fields: snapshot.plan); let remote = try plan.notebook()
            guard ticket == generation, repository.owner == owner else { return }
            let local = repository.document
            if useAccount {
                try NoteFile(url: NoteRepository.directory.appendingPathComponent("conflict-mac-backup-" + owner + ".json")).save(local)
                try repository.acceptCloud(remote, events: plan.events); lastSynced = remote; try persistBase(remote); conflict = false
            } else if local == remote {
                // A prior save may have succeeded before its response was lost.
                lastSynced = remote; try persistBase(remote); repository.events = plan.events; conflict = false
            } else if local != lastSynced || forceLocal {
                guard !NoteSyncRules.conflicts(local: local, remote: remote, base: lastSynced) || forceLocal else { conflict = true; status = "Conflict · choose which note to keep in Account"; return }
                if forceLocal { try NoteFile(url: NoteRepository.directory.appendingPathComponent("conflict-account-backup-" + owner + ".json")).save(remote) }
                try plan.setNotebook(local); _ = try await api.save(plan, revision: snapshot.revision, session: value)
                guard ticket == generation, repository.owner == owner else { return }
                lastSynced = local; try persistBase(local); repository.events = plan.events; conflict = false
            } else {
                try repository.acceptCloud(remote, events: plan.events); lastSynced = remote; try persistBase(remote)
            }
            planTasks = NoteRecommendationBuilder.parseTasks(from: plan.fields)
            Task { await NoteNotifications.reconcile(tasks: planTasks) }
            status = repository.document == lastSynced ? "Synced · " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short) : "Changes waiting to sync"
            if repository.document != lastSynced { schedule() }
        } catch { if ticket == generation { status = error.localizedDescription } }
    }
    func importLocal() {
        guard connected, !busy, !conflict else { return }
        do {
            let local = try repository.localDocument()
            repository.change { doc in
                if doc == .cloudEmpty { doc = local; return }
                let existing = Set(doc.categories.flatMap(\.items).map(\.id))
                for group in local.categories {
                    let additions = group.items.filter { !existing.contains($0.id) }
                    if let i = doc.categories.firstIndex(where: { $0.id == group.id || $0.name.lowercased() == group.name.lowercased() }) { doc.categories[i].items.append(contentsOf: additions) }
                    else if !additions.isEmpty { var next = group; next.items = additions; doc.categories.append(next) }
                }
            }
        } catch { status = error.localizedDescription }
    }
    var localImportCount: Int { (try? repository.localDocument().categories.flatMap(\.items).count) ?? 0 }
    func signOut() {
        guard !busy else { return }
        do { try repository.retainCurrentLocally(); try NoteSessionVault.clear() } catch { status = "Sign-out paused. " + error.localizedDescription; return }
        generation += 1; debounce?.cancel(); poll?.invalidate(); auth?.cancel(); handoff = nil; session = nil; resumeCandidate = nil; api = nil; lastSynced = nil; connected = false; conflict = false; email = nil
        planTasks = []
        repository.disconnect(); status = "Offline · notes kept on this Mac"; busy = false
        Task { await NoteNotifications.reconcile(tasks: []) }
    }
    func setRemindersEnabled(_ on: Bool) async {
        NoteNotifications.enabled = on
        if on { _ = await NoteNotifications.requestAccessIfNeeded() }
        await NoteNotifications.reconcile(tasks: planTasks)
    }
    func browserSignIn() {
        guard !busy else { return }
        let challenge = DesktopHandoff(); handoff = challenge
        var url = URLComponents(string: "https://campus-rhythm-one.vercel.app/desktop-connect")!
        url.queryItems = [URLQueryItem(name: "key", value: challenge.publicKey), URLQueryItem(name: "state", value: challenge.state)]
        let flow = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "rhythmnote") { [weak self] url, _ in
            Task { @MainActor in
                guard let self, self.handoff === challenge else { return }
                if let url {
                    self.busy = false
                    await self.handleCallback(url)
                    if self.status == "Complete sign-in in the browser" { self.status = "Could not verify this sign-in. Start Connect in browser again." }
                }
                else { self.status = "Browser connection cancelled. Local notes are unchanged."; self.busy = false }
            }
        }
        flow.presentationContextProvider = self; flow.prefersEphemeralWebBrowserSession = false; auth = flow; status = "Complete sign-in in the browser"; busy = true
        if !flow.start() { busy = false; status = "Could not open browser sign-in. You can use email and password instead." }
    }
    func handleCallback(_ url: URL) async {
        guard let challenge = handoff else { return }
        do {
            let bytes = try challenge.open(url)
            handoff = nil; busy = false
            let value = try JSONDecoder().decode(NoteAccountSession.self, from: bytes)
            await connect(value)
        } catch { busy = false; status = "Could not verify the browser connection. Start sign-in again." }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow() }
}
