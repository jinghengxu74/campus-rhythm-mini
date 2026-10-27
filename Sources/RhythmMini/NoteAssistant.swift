import AVFoundation
import EventKit
import Speech
import SwiftUI
import NoteCore

struct NoteAITurn: Identifiable, Equatable {
    let id = UUID()
    let mine: Bool
    let text: String
}

struct NoteAssistantView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var account: AccountConnection
    @ObservedObject var controller: AppController
    var close: () -> Void
    @State private var turns: [NoteAITurn] = []
    @State private var draft = ""
    @State private var listening = false
    @State private var followUp = false
    @StateObject private var speech = RhythmSpeech()
    private var calendar: AppleCalendarConnection { .shared }
    private var light: Bool { controller.theme == .light }
    private var edge: Color { light ? Color.black.opacity(0.16) : Color.white.opacity(0.34) }
    private var card: Color { light ? Color.white.opacity(0.82) : Color.black.opacity(0.28) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                Text("Rhythm").font(controller.font(size: 15, weight: .semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(card, in: Circle())
                        .overlay(Circle().strokeBorder(edge, lineWidth: 0.7))
                }
                .buttonStyle(.plain).accessibilityLabel("Close Rhythm")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(turns) { turn in
                        Text(turn.text)
                            .font(controller.font(size: 12))
                            .foregroundStyle(controller.ink)
                            .lineSpacing(3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: turn.mine ? .trailing : .leading)
                            .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(edge, lineWidth: 0.7))
                    }
                }
            }.frame(minHeight: 160, maxHeight: 280)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(choices) { choice in
                        Button(choice.title) { run(choice) }
                            .font(controller.font(size: 11, weight: .medium))
                            .foregroundStyle(controller.ink)
                            .buttonStyle(.plain)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(width: 148, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(edge, lineWidth: 0.7))
                    }
                }
            }
            HStack(spacing: 8) {
                Button { toggleSpeech() } label: {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(controller.ink)
                        .frame(width: 28, height: 28)
                        .background(card, in: Circle())
                        .overlay(Circle().strokeBorder(edge, lineWidth: 0.7))
                }.buttonStyle(.plain).accessibilityLabel(listening ? "Stop listening" : "Speak")
                TextField("Or speak…", text: $draft, prompt: Text("Or pick a card").foregroundColor(controller.ink.opacity(0.45)))
                    .textFieldStyle(.plain).font(controller.font(size: 13)).foregroundStyle(controller.ink).onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(controller.ink)
                        .frame(width: 28, height: 28)
                        .background(card, in: Circle())
                        .overlay(Circle().strokeBorder(edge, lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(card, in: Capsule())
            .overlay(Capsule().strokeBorder(edge, lineWidth: 0.7))
        }
        .padding(16)
        .foregroundStyle(controller.ink)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(light ? Color.white.opacity(0.55) : Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(edge, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
        .padding(10)
        .environment(\.colorScheme, controller.theme.scheme)
        .onAppear { if turns.isEmpty { greet() } }
        .onDisappear { speech.stop() }
        .onChange(of: speech.heard) { value in
            listening = false
            let heard = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty else { return }
            draft = heard
            send()
        }
    }

    private struct RhythmCard: Identifiable { let id: String; let title: String }
    private var dueEvents: [EKEvent] { calendar.events.filter { ($0.title ?? "").lowercased().hasPrefix("due") } }
    private var nextClass: EKEvent? { calendar.events.first { !($0.title ?? "").lowercased().hasPrefix("due") } }
    private var choices: [RhythmCard] {
        if followUp {
            return [
                RhythmCard(id: "undo", title: "Undo that"),
                RhythmCard(id: "todo", title: "Open To-do"),
                RhythmCard(id: "events", title: "Open Events")
            ]
        }
        var cards = [RhythmCard(id: "next", title: "What should I do next")]
        if !dueEvents.isEmpty { cards.insert(RhythmCard(id: "pending", title: "Park \(dueEvents.count) due in Pending"), at: 0) }
        if let title = nextClass?.title { cards.append(RhythmCard(id: "class", title: "Add \(title.prefix(28))")) }
        if cards.count < 3 { cards.append(RhythmCard(id: "week", title: "Move 7-day Pending")) }
        return Array(cards.prefix(3))
    }
    private func run(_ card: RhythmCard) {
        turns.append(NoteAITurn(mine: true, text: card.title))
        switch card.id {
        case "pending": addDue(to: .pending); followUp = true
        case "next": sayNext()
        case "class": addNextClass(); followUp = true
        case "week": moveWeek(); followUp = true
        case "undo": workspace.undo(); turns.append(NoteAITurn(mine: false, text: "Undone. Your previous note is back.")); followUp = false
        case "todo": workspace.tab = .todo; close()
        case "events": workspace.tab = .events; close()
        default: break
        }
    }
    private func toggleSpeech() {
        if listening { speech.stop(); listening = false; return }
        listening = true
        speech.start()
    }

    private func greet() {
        calendar.refresh(day: NoteDay.key())
        let overdue = account.planTasks.filter { !$0.done && $0.dueDate < NoteDay.key() }
        let dues = calendar.events.filter { ($0.title ?? "").lowercased().hasPrefix("due") }.count
        let nextClass = calendar.events.first { !($0.title ?? "").lowercased().hasPrefix("due") }?.title
        var line = "Hi. Tap a card. I won’t add anything until you do."
        if dues > 0 { line = "Hi. \(dues) deadline\(dues == 1 ? "" : "s") on today’s calendar. Tap a card to continue." }
        else if nextClass != nil { line = "Hi. Your next class is on the calendar. Tap a card if you want it on the list." }
        else if !overdue.isEmpty { line = "Hi. You still have an open deadline. Tap a card. I won’t add it until you do." }
        turns = [NoteAITurn(mine: false, text: line)]
    }
    private func sayNext() {
        calendar.refresh(day: NoteDay.key())
        if let due = calendar.events.first(where: { ($0.title ?? "").lowercased().hasPrefix("due") }) {
            turns.append(NoteAITurn(mine: false, text: "Next deadline: \(due.title ?? "Untitled"). It stays on your calendar until you park it in Pending."))
        } else if let task = workspace.categories.flatMap({ workspace.items(in: $0) }).first {
            turns.append(NoteAITurn(mine: false, text: "Your next sticky to-do is \(task.title)."))
        } else {
            turns.append(NoteAITurn(mine: false, text: "Nothing urgent. Your schedule is the next thing to look at."))
        }
    }
    private func addNextClass() {
        calendar.refresh(day: NoteDay.key())
        guard let event = calendar.events.first(where: { !($0.title ?? "").lowercased().hasPrefix("due") }), let title = event.title else {
            turns.append(NoteAITurn(mine: false, text: "No class on Apple Calendar for this day.")); return
        }
        let added = workspace.add(title)
        turns.append(NoteAITurn(mine: false, text: added ? "Added \(title) to To-do." : "\(title) is already on your list."))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        turns.append(NoteAITurn(mine: true, text: text))
        let lower = text.lowercased()
        if lower.contains("pending") { addDue(to: .pending) }
        else if lower.contains("to-do") || lower.contains("todo") || lower.contains("7") { moveWeek() }
        else if lower.contains("calendar") || lower.contains("today") { addCalendar() }
        else { turns.append(NoteAITurn(mine: false, text: "I can add overdue deadlines to Pending, move Pending items due within 7 days onto To-do, or make a to-do from today’s Apple Calendar. Tell me which.")) }
    }

    private func addDue(to status: NoteStatus) {
        let today = NoteDay.key()
        let picks = account.planTasks.filter { !$0.done && ($0.dueDate < today || $0.dueDate <= NoteDay.offset(today, by: 7)) }.prefix(8)
        guard !picks.isEmpty else { turns.append(NoteAITurn(mine: false, text: "No dated plan tasks to add. Confirm Canvas items on the web first.")); return }
        var added = 0
        for task in picks {
            if workspace.add("\(task.title) · Due \(task.dueDate)") { added += 1 }
        }
        turns.append(NoteAITurn(mine: false, text: added == 0 ? "Those titles are already in your note." : "Added \(added) to \(status == .pending ? "Pending" : "To-do"). Pending stays undated until you move it."))
    }

    private func moveWeek() {
        let count = workspace.promotePending(withinDays: 7)
        turns.append(NoteAITurn(mine: false, text: count == 0 ? "No Pending item has a date inside the next 7 days." : "Moved \(count) Pending item\(count == 1 ? "" : "s") onto today’s To-do."))
    }

    private func addCalendar() {
        calendar.refresh(day: NoteDay.key())
        guard calendar.allowed else { turns.append(NoteAITurn(mine: false, text: "Apple Calendar isn’t connected yet. Open Events and connect it.")); return }
        var added = 0
        for event in calendar.events.prefix(6) {
            let title = event.title ?? "Calendar event"
            if workspace.add(title) { added += 1 }
        }
        turns.append(NoteAITurn(mine: false, text: added == 0 ? "Today’s calendar is already on your list, or it’s empty." : "Added \(added) of today’s Apple Calendar events to To-do."))
    }
}

@MainActor final class RhythmSpeech: ObservableObject {
    @Published var heard = ""
    private let engine = AVAudioEngine()
    private static func recognizer() -> SFSpeechRecognizer? {
        let locales = Locale.preferredLanguages.map { Locale(identifier: $0) } + [Locale.current, Locale(identifier: "zh-CN"), Locale(identifier: "zh-Hans"), Locale(identifier: "en-US")]
        return locales.compactMap { SFSpeechRecognizer(locale: $0) }.first { $0.isAvailable }
    }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    func start() {
        heard = ""
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized, let recognizer = Self.recognizer() else { return }
                self.request = SFSpeechAudioBufferRecognitionRequest()
                self.request?.shouldReportPartialResults = true
                let input = self.engine.inputNode
                let format = input.outputFormat(forBus: 0)
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.request?.append(buffer) }
                self.engine.prepare()
                do { try self.engine.start() } catch { return }
                self.task = recognizer.recognitionTask(with: self.request!) { [weak self] result, error in
                    guard let result else { return }
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        if result.isFinal || error != nil { self?.stop(text) }
                        else if !text.isEmpty { self?.heard = text }
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    self.stop()
                }
            }
        }
    }
    func stop(_ text: String? = nil) {
        engine.stop(); engine.inputNode.removeTap(onBus: 0); request?.endAudio(); task?.cancel(); request = nil; task = nil
        if let text, !text.isEmpty { heard = text }
    }
}
