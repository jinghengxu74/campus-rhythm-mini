import Foundation
import Combine
import RhythmCore

@MainActor final class Workspace: ObservableObject {
    enum Mode: String { case local = "Local workspace", sample = "Sample workspace", account = "Account workspace" }
    @Published var plan = PlanDocument.empty()
    @Published var mode: Mode = .local
    @Published var busy = false
    @Published var status = "Saved on this Mac"
    @Published var error = ""
    @Published var email = ""
    @Published var undo: CompletionReceipt?
    @Published var accountReady = false
    @Published var focusedID: String?
    @Published var focusEnd: Date?
    var active = true
    private var session: AccountSession?
    private var api: CloudAPI?
    private var epoch = UUID()
    private var pendingAdd: (signature: String, id: String)?
    private var localReadFailure = false
    private var timer: Timer?
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("local-plan-v1.json") }
    var canEdit: Bool { !busy && (mode != .account || accountReady) && (mode != .local || !localReadFailure) }
    var open: [MiniTask] { plan.openTasks() }
    var completed: [MiniTask] { plan.tasks.filter(\.done).sorted { $0.completedAt > $1.completedAt } }
    var next: MiniTask? {
        if let id = plan.fields["pinnedTaskId"]?.string, let task = open.first(where: { $0.id == id }) { return task }
        return open.first
    }
    var restWindow: String? {
        guard plan.fields["goals"]?.object["health"]?.bool == true else { return nil }
        let prefs = plan.fields["prefs"]?.object ?? [:]
        guard let bed = prefs["bed"]?.number, let wake = prefs["wake"]?.number else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        let resting = bed > wake ? minute >= bed || minute < wake : minute >= bed && minute < wake
        return resting ? String(format: "%02d:%02d–%02d:%02d", Int(bed) / 60, Int(bed) % 60, Int(wake) / 60, Int(wake) % 60) : nil
    }
    init(sample: Bool = false, directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CampusRhythmMini", isDirectory: true)
        if sample { mode = .sample; plan = .sample(); status = "Fictional examples · not your account" }
        else {
            loadLocal()
            if let stored = SessionVault.read() {
                mode = .account; plan = .empty(); session = stored; email = stored.user.email ?? ""; status = "Restoring account…"
                Task { await refresh() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, self.active, !self.busy else { return }; if self.mode == .account { await self.refresh() }; self.objectWillChange.send() }
        }
    }
    private func loadLocal() {
        mode = .local; plan = .empty(); localReadFailure = false
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let stored = try JSONDecoder().decode(PlanDocument.self, from: Data(contentsOf: file))
                guard stored.isValid else { throw MiniError.message("Invalid local plan") }
                plan = stored
            } catch { localReadFailure = true; self.error = "The local plan could not be read. Editing is paused and the original file has been kept." }
        }
        status = "Saved on this Mac"
    }
    private func persist(_ next: PlanDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
    }
    func sample() {
        guard !busy, mode != .account else { return }
        epoch = UUID(); pendingAdd = nil; mode = .sample; plan = .sample(); undo = nil; error = ""; focusedID = nil; focusEnd = nil
        status = "Fictional examples · not your account"
    }
    func local() {
        guard !busy, mode != .account else { return }
        epoch = UUID(); pendingAdd = nil; undo = nil; focusedID = nil; focusEnd = nil; error = ""; loadLocal()
    }
    func signIn(email: String, password: String) async -> Bool {
        guard !busy else { return false }
        let ticket = UUID(); epoch = ticket; pendingAdd = nil; busy = true; error = ""
        defer { if epoch == ticket { busy = false } }
        do {
            let client = try await CloudAPI.connect()
            let account = try await client.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            guard ticket == epoch else { return false }
            // Store rotated tokens before any later request; a failed plan read
            // must not strand a previously saved refresh token.
            try SessionVault.save(account)
            session = account; api = client; self.email = account.user.email ?? email
            mode = .account; plan = .empty(); undo = nil; focusedID = nil; focusEnd = nil; accountReady = false
            let snapshot = try await client.read(account)
            guard ticket == epoch else { return false }
            plan = snapshot.plan; accountReady = true; status = "Up to date with your account"; return true
        } catch { if ticket == epoch { self.error = error.localizedDescription; status = mode == .account ? "Account not ready · retry refresh" : "Local plan unchanged" }; return false }
    }
    private func currentConnection() async throws -> (CloudAPI, AccountSession) {
        let ticket = epoch
        let client: CloudAPI
        if let api { client = api } else { client = try await CloudAPI.connect() }
        guard ticket == epoch, var account = session else { throw MiniError.message("Sign in to connect your account.") }
        if (account.expires_at ?? 0) < Date().timeIntervalSince1970 + 90 {
            account = try await client.refresh(account)
            guard ticket == epoch else { throw CancellationError() }
            try SessionVault.save(account); session = account
        }
        guard ticket == epoch else { throw CancellationError() }
        api = client; return (client, account)
    }
    func refresh() async {
        guard mode == .account, !busy else { return }
        let ticket = epoch; busy = true
        defer { if ticket == epoch { busy = false } }
        do {
            let (client, account) = try await currentConnection()
            let snapshot = try await client.read(account)
            guard ticket == epoch else { return }
            plan = snapshot.plan; accountReady = true; error = ""; status = "Up to date with your account"
        } catch { if ticket == epoch { self.error = error.localizedDescription; status = "Could not refresh · changes paused"; accountReady = false } }
    }
    func disconnect() {
        guard !busy else { return }
        do { try SessionVault.clear() } catch { self.error = error.localizedDescription; return }
        epoch = UUID(); pendingAdd = nil; session = nil; api = nil; email = ""; accountReady = false; undo = nil; error = ""; focusedID = nil; focusEnd = nil; loadLocal()
    }
    enum Change { case complete(String), reopen(String, CompletionReceipt?), add(String, String, Int, String) }
    func change(_ action: Change) async -> Bool {
        guard canEdit else { return false }
        let ticket = epoch; busy = true; error = ""
        defer { if ticket == epoch { busy = false } }
        do {
            var next = plan
            var connection: (CloudAPI, AccountSession, Int)?
            if mode == .account {
                let (client, account) = try await currentConnection()
                let snapshot = try await client.read(account)
                guard ticket == epoch else { return false }
                next = snapshot.plan; connection = (client, account, snapshot.revision)
            }
            var receipt: CompletionReceipt?
            switch action {
            case .complete(let id):
                let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let value = next.complete(id, at: format.string(from: Date())) else { throw MiniError.message("This task changed elsewhere. Refresh to review its current status.") }
                receipt = value
            case .reopen(let id, let previous): guard next.reopen(id, receipt: previous) else { throw MiniError.message("This completion changed elsewhere. Refresh to review it.") }
            case .add(let title, let date, let minutes, let category):
                let signature = try String(decoding: JSONEncoder().encode([title, date, String(minutes), category]), as: UTF8.self)
                let id = pendingAdd?.signature == signature ? pendingAdd!.id : UUID().uuidString
                pendingAdd = (signature, id)
                if !next.tasks.contains(where: { $0.id == id }) {
                    let count = next.tasks.count; next.add(title: title, date: date, minutes: minutes, category: category, id: id)
                    guard next.tasks.count == count + 1 else { throw MiniError.message("Check the task title, date and duration.") }
                }
            }
            if let (client, account, revision) = connection { _ = try await client.save(next, revision: revision, session: account) }
            else if mode == .local { try persist(next) }
            guard ticket == epoch else { return false }
            plan = next
            switch action { case .complete(let id): undo = receipt; if focusedID == id { focusedID = nil; focusEnd = nil }
            case .reopen: undo = nil
            case .add: pendingAdd = nil }
            status = mode == .account ? "Saved to your account" : mode == .sample ? "Sample only · not saved to your account" : "Saved on this Mac"
            return true
        } catch { if ticket == epoch { self.error = error.localizedDescription; status = "Change not confirmed · please review" }; return false }
    }
    func startFocus(_ task: MiniTask) { focusedID = task.id; focusEnd = Date().addingTimeInterval(Double(min(25, max(1, task.duration))) * 60) }
    func stopFocus() { focusedID = nil; focusEnd = nil }
}
