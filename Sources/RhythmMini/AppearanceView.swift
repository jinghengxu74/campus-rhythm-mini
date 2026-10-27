import AppKit
import SwiftUI

private struct NoteColorChip: View {
    let hex: String
    var selected: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(noteHex: hex))
            .frame(width: 20, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(selected ? Color.primary.opacity(0.85) : Color.primary.opacity(0.18), lineWidth: selected ? 1.5 : 0.5))
    }
}

struct NoteAppearanceView: View {
    @ObservedObject var controller: AppController
    var close: () -> Void
    private let paperPresets = ["#FAFAFC", "#0C0D10", "#EEF4FF", "#1A2847", "#E8E8ED", "#EDE7F6"]
    private let inkPresets = ["#25282D", "#FFFFFF", "#4E91E5", "#A17BE8", "#42A98D"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Appearance").font(controller.font(size: 14, weight: .semibold))
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Close appearance")
                }
                HStack(spacing: 10) {
                    Button { controller.adjustText(-0.05) } label: { Text("A").font(.system(size: 11)).frame(width: 28, height: 26) }
                        .disabled(controller.textScale <= 0.7).accessibilityLabel("Decrease task text size")
                    Text("Task text · \(Int((controller.textScale * 100).rounded()))%").font(controller.font(size: 10)).frame(maxWidth: .infinity)
                    Button { controller.adjustText(0.05) } label: { Text("A").font(.system(size: 17)).frame(width: 28, height: 26) }
                        .disabled(controller.textScale >= 1.5).accessibilityLabel("Increase task text size")
                }
                Button("Reset text size") { controller.textScale = 1 }.font(controller.font(size: 9)).foregroundStyle(.secondary)

                Text("Desk skins").font(controller.font(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(NoteDeskSkin.presets) { skin in
                            Button {
                                controller.theme = skin.theme
                                controller.paperHex = skin.paper
                                controller.inkHex = skin.ink
                                controller.glassFinish = skin.finish
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(noteHex: skin.paper))
                                        .overlay(Text("Aa").font(controller.font(size: 9)).foregroundStyle(Color(noteHex: skin.ink)).padding(.leading, 5), alignment: .leading)
                                        .frame(width: 72, height: 22)
                                    Text(skin.title).font(controller.font(size: 8)).lineLimit(1)
                                }
                                .padding(5)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .accessibilityLabel(skin.title + " desk skin")
                        }
                    }
                }

                Text("Mode").font(controller.font(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(NoteTheme.allCases) { theme in
                        Button { controller.theme = theme; controller.resetColors() } label: {
                            Text(theme.title).font(controller.font(size: 10))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(controller.theme == theme ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityAddTraits(controller.theme == theme ? .isSelected : [])
                    }
                }

                Text("Edges").font(controller.font(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(NoteEdgeStyle.allCases) { edge in
                        Button { controller.edgeStyle = edge } label: {
                            Text(edge.title.components(separatedBy: " ").first ?? edge.title)
                                .font(controller.font(size: 8)).lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(controller.edgeStyle == edge ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityLabel(edge.title)
                        .accessibilityAddTraits(controller.edgeStyle == edge ? .isSelected : [])
                    }
                }

                Text("Window material").font(controller.font(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(NoteGlassFinish.allCases) { finish in
                        Button { controller.glassFinish = finish } label: {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(.white.opacity(finish == .glass ? 0.55 : 0.2), lineWidth: 0.5)
                                    )
                                    .frame(width: 28, height: 20)
                                    .opacity(finish == .glass ? 0.55 : 1)
                                Text(finish.title).font(controller.font(size: 10))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(controller.glassFinish == finish ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityAddTraits(controller.glassFinish == finish ? .isSelected : [])
                    }
                }
                Text(finishHint(controller.glassFinish)).font(controller.font(size: 9)).foregroundStyle(.tertiary)

                HStack {
                    Text("Opacity").font(controller.font(size: 10))
                    Spacer()
                    Text(NotePaperOpacity.isSolid(slider: controller.backgroundOpacity) ? "Solid" : "\(Int((controller.backgroundOpacity * 100).rounded()))%")
                        .font(controller.font(size: 10))
                }
                Slider(value: $controller.backgroundOpacity, in: NotePaperOpacity.sliderMin...1).accessibilityLabel("Window opacity")
                HStack {
                    Text("See-through").font(controller.font(size: 9)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Solid paper").font(controller.font(size: 9)).foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ColorPicker("Paper", selection: Binding(get: { Color(nsColor: controller.paper) }, set: { controller.paperHex = $0.noteHex }), supportsOpacity: false)
                        .font(controller.font(size: 10))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(paperPresets, id: \.self) { color in
                                Button { controller.paperHex = color } label: {
                                    NoteColorChip(hex: color, selected: controller.paperHex == color)
                                }.accessibilityLabel("Paper " + color)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ColorPicker("Text", selection: Binding(get: { controller.ink }, set: { controller.inkHex = $0.noteHex }), supportsOpacity: false)
                        .font(controller.font(size: 10))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(inkPresets, id: \.self) { color in
                                Button { controller.inkHex = color } label: {
                                    NoteColorChip(hex: color, selected: controller.inkHex == color)
                                }.accessibilityLabel("Text " + color)
                            }
                        }
                    }
                }

                Button("Reset colors for this mode") { controller.resetColors() }.font(controller.font(size: 9)).foregroundStyle(.secondary)
                Text("Right-click a task for its own text color or highlight.").font(controller.font(size: 9)).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 280, height: 460)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
        .environment(\.colorScheme, controller.theme.scheme)
    }

    private func finishHint(_ finish: NoteGlassFinish) -> String {
        finish == .glass
            ? "Glass · Apple Liquid Glass (clear, more see-through)."
            : "Frosted · denser blur and stronger paper tint."
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
