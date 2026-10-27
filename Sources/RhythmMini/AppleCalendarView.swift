import AppKit
import EventKit
import SwiftUI
import NoteCore

@MainActor final class AppleCalendarConnection: ObservableObject {
    static let shared = AppleCalendarConnection()
    let store = EKEventStore()
    @Published var allowed = false
    @Published var message = ""
    @Published var events: [EKEvent] = []
    @Published var calendars: [EKCalendar] = []
    @Published var readableCalendars: [EKCalendar] = []
    func selected(_ id: String) -> Bool {
        guard let saved = UserDefaults.standard.stringArray(forKey: "noteAppleCalendarIDs") else { return true }
        return saved.contains(id)
    }
    func select(_ id: String, value: Bool, day: String) {
        var ids = Set(readableCalendars.filter { selected($0.calendarIdentifier) }.map(\.calendarIdentifier))
        if value { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: "noteAppleCalendarIDs")
        refresh(day: day)
    }
    func refresh(day: String) {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) { allowed = status == .fullAccess } else { allowed = status == .authorized }
        guard allowed else { events = []; calendars = []; return }
        readableCalendars = store.calendars(for: .event)
        calendars = readableCalendars.filter(\.allowsContentModifications)
        guard let interval = CalendarDuplicate.dayInterval(day) else { return }
        let chosen = readableCalendars.filter { selected($0.calendarIdentifier) }
        events = chosen.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: chosen)).sorted { $0.startDate < $1.startDate }
    }
    static func stableEventKey(_ event: EKEvent) -> String {
        let id = event.eventIdentifier ?? "\(event.calendar.calendarIdentifier):\(event.title ?? ""):\(event.startDate.timeIntervalSince1970)"
        return event.calendar.calendarIdentifier + ":" + id
    }
    static func isCalendarTodo(_ event: EKEvent) -> Bool {
        let title = event.title ?? ""
        if CalendarDeadline.isClassSession(title) || CalendarDeadline.isNoise(title) { return false }
        if CalendarDeadline.isAssignment(title) { return true }
        return event.isAllDay
    }
    static func dueMinute(for event: EKEvent) -> Int? {
        let blob = [event.title, event.notes, event.location, event.url?.absoluteString].compactMap { $0 }.joined(separator: "\n")
        let written = TaskDueText.clockMinute(in: blob)
        if !event.isAllDay {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
            if let hour = parts.hour, let minute = parts.minute, hour >= 0, minute >= 0 {
                let clock = hour * 60 + minute
                if clock > 0 { return clock }
            }
        }
        return written
    }
    func syncImportedPending(into workspace: Workspace) {
        let enabled = UserDefaults.standard.object(forKey: "noteSyncAppleCalendarToPending") as? Bool ?? true
        guard enabled, allowed else { return }
        workspace.syncAppleCalendarPending(keys: futureAllDayTodos(from: NoteDay.key()))
    }
    func futureAllDayTodos(from day: String, horizonDays: Int = 400) -> [(key: String, title: String, dueDay: String, dueMinute: Int?)] {
        guard allowed, let start = NoteDay.date(day), let end = Calendar.current.date(byAdding: .day, value: horizonDays, to: start) else { return [] }
        let chosen = readableCalendars.filter { selected($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        let found = store.events(matching: predicate)
        var rows: [(key: String, title: String, dueDay: String, dueMinute: Int?)] = []
        for event in found where Self.isCalendarTodo(event) {
            let dueDay = NoteDay.key(event.startDate)
            guard dueDay >= day else { continue }
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            rows.append((key: Self.stableEventKey(event), title: title, dueDay: dueDay, dueMinute: Self.dueMinute(for: event)))
        }
        return rows
    }
    func connect(day: String) async {
        do {
            let granted: Bool
            if #available(macOS 14, *) { granted = try await store.requestFullAccessToEvents() }
            else { granted = try await store.requestAccess(to: .event) }
            message = granted ? "" : "Calendar access is off. Enable it in System Settings → Privacy & Security → Calendars."
            refresh(day: day)
        } catch { message = error.localizedDescription }
    }
    func save(title: String, location: String, start: Date, end: Date, allDay: Bool, calendarID: String, day: String) -> Bool {
        guard allowed, (allDay ? Calendar.current.startOfDay(for: end) >= Calendar.current.startOfDay(for: start) : end > start), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            message = "Enter a title, an end after the start, and a writable calendar."; return false
        }
        let event = EKEvent(eventStore: store)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines); event.location = location
        event.startDate = allDay ? Calendar.current.startOfDay(for: start) : start
        event.endDate = allDay ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))! : end
        event.isAllDay = allDay; event.calendar = calendar
        do { try store.save(event, span: .thisEvent, commit: true); message = "Saved to Apple Calendar."; refresh(day: day); return true }
        catch { message = error.localizedDescription; return false }
    }
}

struct AppleCalendarView: View {
    let day: String
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    @ObservedObject private var connection = AppleCalendarConnection.shared
    @State private var creating = false
    @AppStorage("noteSelectingAppleCalendars") private var selectingCalendars = false
    @AppStorage("noteHiddenApplePlaceholders") private var hiddenJSON = "[]"
    @AppStorage("noteSyncAppleCalendarToPending") private var syncToPending = true
    @AppStorage("noteShowAppleCalendarTodos") private var showCalendarTodos = true
    @AppStorage("noteSyncAppleAllDayEvents") private var syncAllAllDay = true
    private var hidden: Set<String> { Set((try? JSONDecoder().decode([String].self, from: Data(hiddenJSON.utf8))) ?? []) }
    private func key(_ event: EKEvent) -> String { AppleCalendarConnection.stableEventKey(event) + ":" + day }
    private func dragPayload(_ event: EKEvent) -> NoteCalendarDragPayload {
        NoteCalendarDragPayload(key: AppleCalendarConnection.stableEventKey(event), title: event.title ?? "Untitled event", dueDay: NoteDay.key(event.startDate), dueMinute: AppleCalendarConnection.dueMinute(for: event))
    }
    private func syncPendingIfNeeded() {
        connection.syncImportedPending(into: workspace)
    }
    private func hide(_ event: EKEvent) {
        var values = hidden; values.insert(key(event))
        if let data = try? JSONEncoder().encode(Array(values)), let text = String(data: data, encoding: .utf8) { hiddenJSON = text }
    }
    private func duplicate(_ event: EKEvent) -> Bool {
        event.isAllDay && connection.events.contains { other in
            !other.isAllDay && CalendarDuplicate.overlaps(start: event.startDate, end: event.endDate, otherStart: other.startDate, otherEnd: other.endDate) && CalendarDuplicate.isExamPlaceholder(event.title ?? "", matching: other.title ?? "")
        }
    }
    private var visibleEvents: [EKEvent] { connection.events.filter { !hidden.contains(key($0)) } }
    private func isDeadline(_ event: EKEvent) -> Bool { AppleCalendarConnection.isCalendarTodo(event) }
    private var todayEvents: some View {
        let due = showCalendarTodos ? visibleEvents.filter(isDeadline) : []
        let schedule = visibleEvents.filter { showCalendarTodos ? !isDeadline($0) : true }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(controller.font(size: 13, weight: .semibold))
                Spacer()
                Button {
                    connection.refresh(day: day)
                    syncPendingIfNeeded()
                } label: { Image(systemName: "arrow.clockwise") }.help("Refresh Apple Calendar")
                Button("Add") { creating = true }.disabled(connection.calendars.isEmpty).font(controller.font(size: 11))
            }
            Text("Drag an event onto To-do, Pending, or Completed above.").font(controller.font(size: 10)).foregroundStyle(.secondary)
            if !due.isEmpty {
                Text("Due today").font(controller.font(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(due.enumerated()), id: \.offset) { _, event in eventRow(event) }
            }
            if !schedule.isEmpty {
                if !due.isEmpty { Text("Schedule").font(controller.font(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
                ForEach(Array(schedule.enumerated()), id: \.offset) { _, event in eventRow(event) }
            }
            if visibleEvents.isEmpty { Text("Nothing on Apple Calendar for this day.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func eventRow(_ event: EKEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 2)
            RoundedRectangle(cornerRadius: 2).fill(controller.ink.opacity(0.35)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled event").font(controller.font(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if event.isAllDay { Text("All day").font(controller.font(size: 10)).foregroundStyle(.secondary) }
                else { HStack { Text(event.startDate, style: .time); Text("–"); Text(event.endDate, style: .time) }.font(controller.font(size: 10)).foregroundStyle(.secondary) }
                Text(event.calendar.title + (event.location.flatMap { $0.isEmpty ? nil : " · " + $0 } ?? "")).font(controller.font(size: 10)).foregroundStyle(.secondary)
                if duplicate(event) {
                    Text("Possible placeholder for this day’s timed midterm.").font(controller.font(size: 10)).foregroundStyle(.secondary)
                    Button("Hide placeholder here") { hide(event) }.font(controller.font(size: 10))
                }
                if workspace.document.item(withCalendarKey: AppleCalendarConnection.stableEventKey(event)) != nil {
                    Text("In your note").font(controller.font(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10).background(controller.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .onDrag { workspace.beginCalendarDrag(dragPayload(event)) }
    }
    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Apple to-dos here", isOn: $showCalendarTodos)
            Toggle("Auto-add future all-day to-dos to Pending", isOn: $syncToPending)
                .onChange(of: syncToPending) { _ in syncPendingIfNeeded() }
            Toggle("Treat every all-day event as a to-do", isOn: $syncAllAllDay)
                .onChange(of: syncAllAllDay) { _ in syncPendingIfNeeded() }
            DisclosureGroup("Calendars · \(connection.readableCalendars.filter { connection.selected($0.calendarIdentifier) }.count) shown", isExpanded: $selectingCalendars) {
                Text("Uncheck hides it here only. It does not unsubscribe in Apple Calendar.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("All") { UserDefaults.standard.removeObject(forKey: "noteAppleCalendarIDs"); connection.refresh(day: day) }
                    Button("None") { UserDefaults.standard.set([String](), forKey: "noteAppleCalendarIDs"); connection.refresh(day: day) }
                }
                ForEach(connection.readableCalendars, id: \.calendarIdentifier) { calendar in
                    Toggle(calendar.title, isOn: Binding(get: { connection.selected(calendar.calendarIdentifier) }, set: { connection.select(calendar.calendarIdentifier, value: $0, day: day) }))
                }
                if connection.events.contains(where: { hidden.contains(key($0)) }) {
                    Button("Show hidden placeholders") { hiddenJSON = "[]" }
                }
            }.font(controller.font(size: 11))
            if connection.calendars.isEmpty { Text("No writable calendar is available.").font(.caption) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !connection.allowed {
                Text("Today’s Apple Calendar stays on this Mac.").font(.caption).foregroundStyle(.secondary)
                Button("Connect Apple Calendar") { Task { await connection.connect(day: day) } }
            } else { todayEvents; calendarSettings }
            if !connection.message.isEmpty { Text(connection.message).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { connection.refresh(day: day); syncPendingIfNeeded() }
        .onChange(of: day) { value in connection.refresh(day: value) }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in connection.refresh(day: day); syncPendingIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in connection.refresh(day: day); syncPendingIfNeeded() }
        .sheet(isPresented: $creating) { AppleEventEditor(day: day, connection: connection) }
    }
}

private struct AppleEventEditor: View {
    let day: String
    @ObservedObject var connection: AppleCalendarConnection
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var location = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var allDay = false
    @State private var calendarID = ""
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Apple Calendar event").font(.headline)
            TextField("Title", text: $title)
            TextField("Location (optional)", text: $location)
            Toggle("All day", isOn: $allDay)
            DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            DatePicker(allDay ? "Last day (inclusive)" : "Ends", selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            Picker("Calendar", selection: $calendarID) {
                ForEach(connection.calendars, id: \.calendarIdentifier) { calendar in Text(calendar.title + " · " + calendar.source.title).tag(calendar.calendarIdentifier) }
            }
            Text("Saved to the selected Apple calendar. Its provider handles syncing to your other devices.").font(.caption).foregroundStyle(.secondary)
            Text(connection.message).font(.caption)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save event") {
                saving = true
                if connection.save(title: title, location: location, start: start, end: end, allDay: allDay, calendarID: calendarID, day: day) { dismiss() }
                saving = false
            }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!allDay && end <= start)) }
        }.padding(20).frame(width: 390).foregroundStyle(.primary)
            .onAppear {
                let date = NoteDay.date(day) ?? Date()
                start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                end = start.addingTimeInterval(3600)
                calendarID = connection.store.defaultCalendarForNewEvents?.calendarIdentifier ?? connection.calendars.first?.calendarIdentifier ?? ""
                connection.message = ""
            }
    }
}
