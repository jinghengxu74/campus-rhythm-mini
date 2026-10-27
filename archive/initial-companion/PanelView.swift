import SwiftUI
import AppKit
import RhythmCore

private let ink = Color(red: 0.15, green: 0.15, blue: 0.18)
private let muted = Color(red: 0.43, green: 0.43, blue: 0.48)
private let purple = Color(red: 0.48, green: 0.36, blue: 0.68)
private let cream = Color(red: 0.985, green: 0.978, blue: 0.960)

struct MiniPanelView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    @State private var tab = "Next"
    @State private var composer = false
    @State private var settings = false
    @State private var title = ""
    @State private var due = Date()
    @State private var duration = 25
    @State private var category = "School"
    @State private var email = ""
    @State private var password = ""
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
            Rectangle().fill(ink.opacity(0.055)).frame(height: 1)
            if settings { settingsContent }
            else {
                VStack(alignment: .leading, spacing: 18) {
                    dayHeader
                    tabs
                    if !workspace.error.isEmpty { errorBanner }
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            if tab == "Next" {
                                if workspace.open.isEmpty { emptyState }
                                else { nextCard; upcomingList }
                            } else if tab == "All" { allList }
                            else { doneList }
                        }.padding(.bottom, 8)
                    }
                    if let receipt = workspace.undo {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.30, green: 0.49, blue: 0.39))
                            Text("A little lighter.").font(.system(size: 12))
                            Spacer()
                            Button("Undo") { Task { _ = await workspace.change(.reopen(receipt.taskID, receipt)) } }
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(purple).disabled(!workspace.canEdit)
                        }.padding(11).background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if composer { composerView }
                    else {
                        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { composer = true }; titleFocused = true } label: {
                            HStack(spacing: 9) { Image(systemName: "plus.circle.fill").font(.system(size: 17)); Text("Capture a task").font(.system(size: 13, weight: .medium)); Spacer(); Text("↵").foregroundStyle(muted) }
                                .foregroundStyle(ink.opacity(0.8)).padding(14).background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.065)))
                        }.disabled(!workspace.canEdit)
                    }
                }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 15)
            }
            footer
        }
        .foregroundStyle(ink).font(.system(size: 13)).buttonStyle(.plain)
        .frame(width: 384, height: controller.panelHeight)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .onExitCommand { controller.hidePanel() }
    }

    private var background: some View {
        ZStack {
            VisualEffect().ignoresSafeArea()
            cream.opacity(0.91)
            VStack { HStack { Spacer(); Circle().fill(Color(red: 0.83, green: 0.77, blue: 0.95).opacity(0.29)).frame(width: 200, height: 200).blur(radius: 50).offset(x: 55, y: -65) }; Spacer()
                HStack { Circle().fill(Color(red: 0.72, green: 0.85, blue: 0.78).opacity(0.22)).frame(width: 170, height: 150).blur(radius: 45).offset(x: -70, y: 45); Spacer() }
            }.allowsHitTesting(false)
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            BrandMark().frame(width: 35, height: 35)
            VStack(alignment: .leading, spacing: 3) {
                Text("Campus Rhythm").font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("A little space to focus").font(.system(size: 10)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            iconButton(controller.pinned ? "pin.fill" : "pin", label: controller.pinned ? "Unpin window" : "Keep window on top") { controller.togglePin() }
                .foregroundStyle(controller.pinned ? purple : muted)
            iconButton("slider.horizontal.3", label: "Companion settings") { settings.toggle() }
            iconButton("xmark", label: "Hide panel") { controller.hidePanel() }
        }
    }
    private var dayHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tab == "Done" ? "Small wins." : "Make room for today.").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.65)
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(workspace.open.count)").font(.system(size: 22, weight: .light, design: .rounded))
                Text("TO DO").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(muted)
            }.frame(width: 43, height: 47).background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 13))
        }
    }
    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(["Next", "All", "Done"], id: \.self) { item in
                Button { tab = item } label: {
                    Text(item).font(.system(size: 11, weight: tab == item ? .semibold : .medium))
                        .foregroundStyle(tab == item ? ink : muted).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(tab == item ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .shadow(color: .black.opacity(tab == item ? 0.055 : 0), radius: 3, y: 1)
                }.accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }.padding(4).background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }
    @ViewBuilder private var nextCard: some View {
        if let rest = workspace.restWindow {
            VStack(alignment: .leading, spacing: 13) {
                HStack { sectionLabel("A LITTLE ROOM TO REST"); Spacer(); Image(systemName: "moon.stars").foregroundStyle(purple) }
                Text("You've made enough room.\nKeep some for yourself.").font(.system(size: 19, weight: .medium, design: .rounded)).lineSpacing(3)
                Text("Your saved rest window · \(rest)").font(.system(size: 11)).foregroundStyle(muted)
                Text("Your tasks are here when you're ready.").font(.system(size: 11)).foregroundStyle(purple)
            }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(lavenderCard)
        } else if let next = workspace.next {
            VStack(alignment: .leading, spacing: 14) {
                HStack { sectionLabel("YOUR NEXT SMALL STEP"); Spacer(); Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(purple.opacity(0.8)) }
                Text(controller.privateTitles ? "Your next small step" : next.title).font(.system(size: 21, weight: .medium, design: .rounded)).tracking(-0.4).lineSpacing(3).fixedSize(horizontal: false, vertical: true).lineLimit(3)
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text("\(next.duration) min left"); Text("·"); Text(next.dueLabel)
                }.font(.system(size: 11)).foregroundStyle(purple.opacity(0.95))
                HStack(spacing: 9) {
                    Button { workspace.startFocus(next) } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill").font(.system(size: 9)); Text("Focus a little").font(.system(size: 12, weight: .semibold)) }
                            .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ink, in: RoundedRectangle(cornerRadius: 11))
                    }.disabled(!workspace.canEdit)
                    Button { Task { _ = await workspace.change(.complete(next.id)) } } label: {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .medium)).frame(width: 42, height: 39).background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 11))
                    }.help("Mark next task Done").accessibilityLabel(controller.privateTitles ? "Complete next task" : "Complete " + next.title).disabled(!workspace.canEdit)
                }
                if workspace.focusedID == next.id, let end = workspace.focusEnd { focusView(end) }
            }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(lavenderCard)
        }
    }
    private var lavenderCard: some View {
        RoundedRectangle(cornerRadius: 19).fill(LinearGradient(colors: [Color(red: 0.94, green: 0.91, blue: 0.985), Color(red: 0.965, green: 0.944, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.8)))
    }
    private func focusView(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                Image(systemName: "circle.dotted")
                Text(context.date < end ? "Focus · " : "Session finished · ")
                if context.date < end { Text(end, style: .timer).monospacedDigit() }
                Spacer()
                Button("End") { workspace.stopFocus() }.fontWeight(.semibold)
            }.font(.system(size: 11)).foregroundStyle(purple)
        }.help("Timer only. Work is recorded when you explicitly mark it Done.")
    }
    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { sectionLabel(workspace.restWindow == nil ? "AFTER THAT" : "WHEN YOU'RE READY"); Spacer(); Text("\(workspace.open.count) open").font(.system(size: 10)).foregroundStyle(muted) }
            ForEach(Array(workspace.open.filter { workspace.restWindow != nil || $0.id != workspace.next?.id }.prefix(3))) { row in taskRow(row) }
            if workspace.open.count > 4 { Button("See the whole list →") { tab = "All" }.font(.system(size: 11)).foregroundStyle(purple).padding(.top, 3) }
        }
    }
    private var allList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if workspace.open.isEmpty { emptyState }
            ForEach(["School", "Personal", "Exercise"], id: \.self) { group in
                let tasks = workspace.open.filter { $0.category == group }
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 9) { sectionLabel(group.uppercased()); ForEach(tasks) { taskRow($0) } }
                }
            }
        }
    }
    private var doneList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.completed.isEmpty {
                Image(systemName: "checkmark.seal").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(purple).padding(.top, 30)
                Text("Little wins will live here.").font(.system(size: 18, weight: .medium, design: .rounded))
                Text("Finished tasks stay in your history.\nYou can reopen them whenever you need.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
            }
            ForEach(workspace.completed) { taskRow($0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func taskRow(_ task: MiniTask) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button { Task { _ = await workspace.change(task.done ? .reopen(task.id, nil) : .complete(task.id)) } } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .ultraLight)).foregroundStyle(task.done ? purple.opacity(0.55) : ink.opacity(0.38)).frame(width: 25, height: 29)
            }.accessibilityLabel((task.done ? "Reopen " : "Complete ") + (controller.privateTitles ? "task" : task.title)).disabled(!workspace.canEdit)
            VStack(alignment: .leading, spacing: 5) {
                Text(controller.privateTitles ? "Private task" : task.title).font(.system(size: 12, weight: .medium)).lineLimit(2).lineSpacing(2).strikethrough(task.done).foregroundStyle(task.done ? muted : ink)
                HStack(spacing: 5) { Circle().fill(categoryColor(task.category)).frame(width: 4, height: 4); Text(task.done ? "Completed" : "\(task.dueLabel) · \(task.duration) min") }.font(.system(size: 10)).foregroundStyle(muted)
            }.padding(.top, 3)
            Spacer(minLength: 0)
        }.padding(.vertical, 7)
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "leaf").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(purple.opacity(0.8)).padding(.top, 18)
            Text("A little less\non your mind.").font(.system(size: 27, weight: .medium, design: .rounded)).tracking(-0.7).lineSpacing(3)
            Text("Capture one thing you'd like to do.\nWe'll keep it close, without the noise.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
            if workspace.mode != .account { Button("Or take a look around →") { workspace.sample() }.font(.system(size: 11, weight: .medium)).foregroundStyle(purple) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)
    }
    private var composerView: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                TextField("One small thing…", text: $title).textFieldStyle(.plain).font(.system(size: 13)).focused($titleFocused).onSubmit(add)
                Button { composer = false; title = "" } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(muted) }.help("Cancel new task")
            }
            HStack(spacing: 8) {
                DatePicker("Due", selection: $due, displayedComponents: .date).labelsHidden().datePickerStyle(.compact).font(.system(size: 10)).frame(maxWidth: 130)
                Picker("Effort", selection: $duration) { ForEach([10, 15, 25, 40, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) } }.labelsHidden().frame(width: 78)
                Spacer(minLength: 0)
                Button(action: add) { Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).foregroundStyle(.white).background(ink, in: Circle()) }.accessibilityLabel("Add task").disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workspace.canEdit)
            }
            Picker("Category", selection: $category) { ForEach(["School", "Personal", "Exercise"], id: \.self) { Text($0) } }.pickerStyle(.segmented).font(.system(size: 10))
            Text("Due at 23:59 on the selected day · your Mac's time zone").font(.system(size: 9)).foregroundStyle(muted)
        }.padding(13).background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
    private func add() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let value = title; let date = f.string(from: due); let minutes = duration; let group = category
        Task { if await workspace.change(.add(value, date, minutes, group)) { title = ""; composer = false } }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(workspace.mode == .sample ? Color.orange.opacity(0.6) : workspace.error.isEmpty ? Color(red: 0.39, green: 0.58, blue: 0.46) : Color.orange).frame(width: 5, height: 5)
            Button { settings.toggle() } label: { Text(workspace.mode.rawValue).font(.system(size: 9, weight: .medium)).foregroundStyle(muted) }
            if workspace.busy { ProgressView().controlSize(.mini).scaleEffect(0.7) }
            Spacer()
            Button { NSWorkspace.shared.open(URL(string: "https://campus-rhythm-one.vercel.app/today")!) } label: { HStack(spacing: 4) { Text("Open planner"); Image(systemName: "arrow.up.right") }.font(.system(size: 9)).foregroundStyle(muted) }
        }.padding(.horizontal, 22).padding(.vertical, 13).background(Color.white.opacity(0.36)).help(workspace.status)
    }
    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color(red: 0.68, green: 0.32, blue: 0.23))
            VStack(alignment: .leading, spacing: 5) {
                Text(workspace.error).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                if workspace.mode == .account { Button("Refresh account") { Task { await workspace.refresh() } }.foregroundStyle(purple).font(.system(size: 10, weight: .semibold)).disabled(workspace.busy) }
            }
        }.padding(10).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Make it yours.").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.5); Spacer(); Button("Back") { settings = false }.foregroundStyle(purple) }
                Text("A quiet companion, on your terms.").font(.system(size: 12)).foregroundStyle(muted)
                VStack(spacing: 15) {
                    Toggle("Keep on top", isOn: Binding(get: { controller.pinned }, set: { controller.setPinned($0) }))
                    Toggle("Reveal from the right edge", isOn: Binding(get: { controller.edgeReveal }, set: { controller.setEdgeReveal($0) }))
                    Toggle("Hide task titles", isOn: $controller.privateTitles)
                }.toggleStyle(.switch).controlSize(.small)
                Text(controller.shortcutReady ? "Show or hide from anywhere · ⌃⌥R" : "Global shortcut unavailable; use the menu bar icon.").font(.system(size: 11)).foregroundStyle(muted)
                Button { controller.setEnabled(false) } label: { Label("Turn off companion", systemImage: "power").foregroundStyle(purple) }
                Divider().opacity(0.5)
                sectionLabel("YOUR WORKSPACE")
                if workspace.mode == .account {
                    Text(workspace.email).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                    Text(workspace.status).font(.system(size: 11)).foregroundStyle(muted)
                    Button("Refresh plan") { Task { await workspace.refresh() } }.foregroundStyle(purple).disabled(workspace.busy)
                    Button("Disconnect this Mac") { workspace.disconnect() }.foregroundStyle(muted).disabled(workspace.busy)
                } else {
                    Text("Connect your existing Campus Rhythm plan, or keep a separate local list on this Mac.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3)
                    TextField("Account email", text: $email).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                    Button {
                        let address = email; let value = password
                        Task { if await workspace.signIn(email: address, password: value) { password = ""; settings = false } }
                    } label: { Text(workspace.busy ? "Connecting…" : "Connect account").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(12).foregroundStyle(.white).background(ink, in: RoundedRectangle(cornerRadius: 10)) }
                        .disabled(workspace.busy || email.isEmpty || password.isEmpty)
                    Text("Email sign-in in this first build. Browser/Google sessions are not shared. Local tasks are kept separate; nothing is merged automatically.").font(.system(size: 10)).foregroundStyle(muted).lineSpacing(3)
                    Button(workspace.mode == .sample ? "Return to my local list" : "Try a separate sample") { if workspace.mode == .sample { workspace.local() } else { workspace.sample() }; settings = false }.foregroundStyle(purple).disabled(workspace.busy)
                }
                if !workspace.error.isEmpty { errorBanner }
                Text("Account tokens use macOS Keychain. This companion does not request Health access or send tasks to an AI provider.").font(.system(size: 10)).foregroundStyle(muted).lineSpacing(3)
                Button("Quit companion") { NSApp.terminate(nil) }.font(.system(size: 11)).foregroundStyle(muted)
            }.padding(22)
        }
    }
    private func sectionLabel(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(muted) }
    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 27) }.help(label).accessibilityLabel(label)
    }
    private func categoryColor(_ category: String) -> Color { category == "School" ? .blue.opacity(0.65) : category == "Exercise" ? .green.opacity(0.65) : purple.opacity(0.7) }
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 3) {
            Capsule().fill(Color(red: 0.59, green: 0.49, blue: 0.75)).frame(width: 4, height: 20)
            Capsule().fill(Color(red: 0.42, green: 0.43, blue: 0.57)).frame(width: 4, height: 25)
            Capsule().fill(Color(red: 0.58, green: 0.70, blue: 0.61)).frame(width: 4, height: 17)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.86, green: 0.83, blue: 0.79).opacity(0.6)))
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView { let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; return v }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
