import AppKit
import SwiftUI

struct NoteAppearanceView: View {
    @ObservedObject var controller: AppController
    var close: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Appearance").font(controller.font(size: 14, weight: .semibold)); Spacer(); Button(action: close) { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Close appearance") }
                HStack(spacing: 12) {
                    Button { controller.adjustText(-0.1) } label: { Text("A").font(.system(size: 12)).frame(width: 32, height: 30) }.disabled(controller.textScale <= 0.85).accessibilityLabel("Decrease note text size")
                    Text("Text size · \(Int((controller.textScale * 100).rounded()))%").frame(maxWidth: .infinity)
                    Button { controller.adjustText(0.1) } label: { Text("A").font(.system(size: 20)).frame(width: 32, height: 30) }.disabled(controller.textScale >= 1.5).accessibilityLabel("Increase note text size")
                }
                Button("Reset text size") { controller.textScale = 1 }.font(.caption)
                Text("Mode").font(controller.font(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(NoteTheme.allCases) { theme in
                        Button { controller.theme = theme; controller.resetColors() } label: {
                            VStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 10).fill(theme == .dark ? Color(white: 0.09) : .white)
                                    .overlay(Text("Aa").font(controller.font(size: 15)).foregroundStyle(theme == .dark ? .white : .black)).frame(height: 48)
                                Text(theme.title).font(controller.font(size: 11))
                            }.padding(6).frame(maxWidth: .infinity)
                                .background(controller.theme == theme ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                        }.accessibilityLabel(theme.title + " mode").accessibilityAddTraits(controller.theme == theme ? .isSelected : [])
                    }
                }
                Text("Edges").font(controller.font(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(NoteEdgeStyle.allCases) { edge in
                        Button { controller.edgeStyle = edge } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: edge.corner * 0.55).strokeBorder(controller.ink.opacity(controller.edgeStyle == edge ? 0.8 : 0.25), lineWidth: 1).frame(width: 48, height: 32)
                                Text(edge.title).font(controller.font(size: 8)).lineLimit(1).minimumScaleFactor(0.8)
                            }.padding(.vertical, 8).frame(maxWidth: .infinity).background(controller.edgeStyle == edge ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }.accessibilityLabel(edge.title + " edges").accessibilityAddTraits(controller.edgeStyle == edge ? .isSelected : [])
                    }
                }
                HStack(spacing: 4) {
                    ForEach(NoteGlassFinish.allCases) { finish in
                        Button { controller.glassFinish = finish } label: {
                            Text(finish.title).font(controller.font(size: 11)).frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(controller.glassFinish == finish ? Color.primary.opacity(0.09) : .clear, in: Capsule())
                        }.accessibilityAddTraits(controller.glassFinish == finish ? .isSelected : [])
                    }
                }.padding(3).background(.primary.opacity(0.035), in: Capsule())
                HStack { Text("Paper opacity"); Spacer(); Text("\(Int((controller.backgroundOpacity * 100).rounded()))%") }.font(controller.font(size: 11))
                Slider(value: $controller.backgroundOpacity, in: 0.15...1).accessibilityLabel("Paper opacity")
                HStack { Text("More glass"); Spacer(); Text("More solid") }.font(controller.font(size: 9)).foregroundStyle(.secondary)
                Divider()
                ColorPicker("Paper color", selection: Binding(get: { Color(nsColor: controller.paper) }, set: { controller.paperHex = $0.noteHex }), supportsOpacity: false).font(controller.font(size: 11))
                HStack(spacing: 8) {
                    ForEach(["#F7F5F0", "#111318", "#EDE7F6", "#E4F0E8", "#F7E8DF"], id: \.self) { color in
                        Button { controller.paperHex = color } label: { Circle().fill(Color(noteHex: color)).overlay(Circle().strokeBorder(.gray.opacity(0.3))).frame(width: 27, height: 27) }.accessibilityLabel("Paper " + color)
                    }
                }
                Divider()
                ColorPicker("Text color", selection: Binding(get: { controller.ink }, set: { controller.inkHex = $0.noteHex }), supportsOpacity: false).font(controller.font(size: 11))
                HStack(spacing: 8) {
                    ForEach(NoteDesign.inks, id: \.1) { name, color in
                        Button { controller.inkHex = color } label: {
                            Circle().fill(Color(noteHex: color)).overlay(Circle().strokeBorder(.gray.opacity(0.4))).frame(width: 27, height: 27)
                        }.help(name + " text").accessibilityLabel("Text " + name)
                    }
                }
                Button("Reset colors for this mode") { controller.resetColors() }.font(controller.font(size: 10)).foregroundStyle(.secondary)
                Text("Right-click a task to change its text color or add a highlight.").font(controller.font(size: 10)).foregroundStyle(.secondary)
            }.padding(18)
        }.frame(width: 300, height: 540).buttonStyle(.plain).foregroundStyle(.primary).environment(\.colorScheme, controller.theme.scheme)
    }
}
struct NoteAccountView: View {
    @ObservedObject var account = AccountConnection.shared
    @ObservedObject var controller: AppController
    var close: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var confirmImport = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("Campus Rhythm account").font(controller.font(size: 14, weight: .semibold)); Spacer(); Button(action: close) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Close account") }
            Text(account.status).font(controller.font(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            if account.connected {
                if let email = account.email { Text(email).font(controller.font(size: 12)) }
                Text("Daily notes sync with Notes on the web. Events shows your account’s calendar for the selected day.").font(controller.font(size: 11)).foregroundStyle(.secondary)
                HStack { Button("Sync now") { Task { await account.sync() } }; Button("Open web notes") { NSWorkspace.shared.open(URL(string: "https://campus-rhythm-one.vercel.app/notes")!) } }.disabled(account.busy)
                Button("Manage Canvas deadline updates…") { NSWorkspace.shared.open(URL(string: "https://campus-rhythm-one.vercel.app/source-updates")!) }
                Text("Connect and review Canvas changes on the web. Confirmed tasks appear in these notes after account sync; automatic checks require that web app to stay open.").font(controller.font(size: 10)).foregroundStyle(.secondary)
                if account.localImportCount > 0 {
                    Button("Import \(account.localImportCount) local notes…") { confirmImport = true }.disabled(account.busy || account.conflict)
                }
                if account.conflict {
                    Text("Both versions are kept. Choosing a version saves a local backup of the other.").font(controller.font(size: 10)).foregroundStyle(.secondary)
                    Button("Keep this Mac’s version") { Task { await account.sync(forceLocal: true) } }
                    Button("Use account version") { Task { await account.sync(useAccount: true) } }
                }
                Divider()
                Button("Sign out · keep notes on this Mac") { account.signOut() }.disabled(account.busy)
                Text("Sign-out keeps a device-only copy of these notes and stops cloud sync. Your previous local notes are backed up. Apple Calendar remains a separate local connection.").font(controller.font(size: 10)).foregroundStyle(.secondary)
            } else {
                if account.hasAccountCache {
                    Text("Showing saved account notes for " + (account.email ?? "your account") + ". Edits stay in this account’s cache until reconnected.").font(controller.font(size: 11))
                    Button("Retry account connection") { Task { await account.retryConnection() } }.disabled(account.busy)
                    Button("Sign out · keep cached notes offline") { account.signOut() }.disabled(account.busy)
                    Divider()
                }
                Text("Connect the same account you use on the web. Your local notes stay separate until you choose Import.").font(controller.font(size: 11)).foregroundStyle(.secondary)
                Button("Connect in browser · Google or email") { account.browserSignIn() }.disabled(account.busy)
                Divider()
                Text("Or use your account’s email and password").font(controller.font(size: 10)).foregroundStyle(.secondary)
                TextField("Email", text: $email).textFieldStyle(.roundedBorder).accessibilityLabel("Account email")
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder).accessibilityLabel("Account password")
                Button("Sign in") { let secret = password; password = ""; Task { await account.signIn(email: email, password: secret) } }.disabled(account.busy || email.isEmpty || password.isEmpty)
            }
            if account.busy { ProgressView().controlSize(.small) }
        }.padding(20).frame(width: 330).font(controller.font(size: 11)).foregroundStyle(controller.ink).environment(\.colorScheme, controller.theme.scheme)
            .confirmationDialog("Import this Mac’s notes into this account?", isPresented: $confirmImport) { Button("Import notes") { account.importLocal() }; Button("Cancel", role: .cancel) {} } message: { Text("Categories, dates, completion history, text colors and highlights will be added. Existing IDs are not duplicated. The local original remains on this Mac.") }
    }
}
