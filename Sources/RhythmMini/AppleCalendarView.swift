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
    @ObservedObject var controller: AppController
    @ObservedObject private var connection = AppleCalendarConnection.shared
    @State private var creating = false
    @AppStorage("noteSelectingAppleCalendars") private var selectingCalendars = false
    @AppStorage("noteHiddenApplePlaceholders") private var hiddenJSON = "[]"
    private var hidden: Set<String> { Set((try? JSONDecoder().decode([String].self, from: Data(hiddenJSON.utf8))) ?? []) }
    private func key(_ event: EKEvent) -> String { event.calendar.calendarIdentifier + ":" + (event.eventIdentifier ?? event.title ?? "") + ":" + day }
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
    private func isDeadline(_ event: EKEvent) -> Bool {
        let title = (event.title ?? "").lowercased()
        return title.hasPrefix("due") || title.contains(" due ") || title.contains("deadline") || title.contains("canvas by")
    }
    private var todayEvents: some View {
        let due = visibleEvents.filter(isDeadline)
        let schedule = visibleEvents.filter { !isDeadline($0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(controller.font(size: 13, weight: .semibold))
                Spacer()
                Button { connection.refresh(day: day) } label: { Image(systemName: "arrow.clockwise") }.help("Refresh Apple Calendar")
                Button("Add") { creating = true }.disabled(connection.calendars.isEmpty).font(controller.font(size: 11))
            }
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
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10).background(controller.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .onAppear { connection.refresh(day: day) }
        .onChange(of: day) { value in connection.refresh(day: value) }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in connection.refresh(day: day) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in connection.refresh(day: day) }
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
