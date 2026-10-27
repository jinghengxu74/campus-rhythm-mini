import AppKit
import Foundation
import NoteCore

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var availableRelease: LatestNoteRelease?
    @Published private(set) var statusMessage: String?

    private let endpoint = URL(string: "https://api.github.com/repos/jinghengxu74/campus-rhythm-mini/releases/latest")!
    private let lastCheckKey = "noteLastUpdateCheck"
    private let interval: TimeInterval = 24 * 60 * 60
    private var checking = false

    private init() {}

    func check(force: Bool = false) async {
        guard !checking else { return }
        if !force, let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < interval { return }
        checking = true
        if force { statusMessage = "Checking for updates…" }
        defer { checking = false }

        do {
            var request = URLRequest(url: endpoint)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Rhythm-Note-macOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateCheckError.invalidResponse
            }
            let release = try JSONDecoder().decode(LatestNoteRelease.self, from: data)
            guard release.htmlURL.scheme == "https", release.htmlURL.host == "github.com",
                  let currentText = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  let current = NoteReleaseVersion(currentText) else {
                throw UpdateCheckError.invalidResponse
            }

            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if release.isNewer(than: current) {
                availableRelease = release
                statusMessage = nil
            } else {
                availableRelease = nil
                if force { statusMessage = "You’re up to date." }
            }
        } catch {
            if force { statusMessage = "Couldn’t check for updates. Check your connection and try again." }
        }
    }

    func openAvailableRelease() {
        guard let url = availableRelease?.htmlURL, url.scheme == "https", url.host == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }

    func dismiss() {
        availableRelease = nil
        statusMessage = nil
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
}
