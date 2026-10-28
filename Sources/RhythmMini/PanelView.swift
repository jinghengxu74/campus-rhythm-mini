import AppKit
import EventKit
import SwiftUI
import NoteCore

struct MiniPanelView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    @AppStorage("noteShowOnlineEvents") private var showOnlineEvents = true
    @AppStorage("noteShowAppleEvents") private var showAppleEvents = true
    @AppStorage("noteShowApplePendingTodos") private var showApplePendingTodos = true
    @State private var input = ""
    @State private var newCategory = false
    @State private var showAppearance = false
    @State private var showAccount = false
    @State private var showTrash = false
    @State private var hoveredWeekBar: (page: Int, bar: Int)?
    @State private var completedListScrollTarget: String?
    @State private var completedChartViewportWidth: CGFloat = 0
    @State private var completedChartScrollX: CGFloat = 0
    @State private var completedChartDidAnchorToday = false
    @State private var showDate = false
    @State private var hoveringDate = false
    @ObservedObject private var account = AccountConnection.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var hoveredCategory: UUID?
    @State private var categoryPendingDelete: NoteCategory?
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dateLabel: String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d, EEE"; return f.string(from: NoteDay.date(workspace.selectedDay) ?? Date()) }
    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Rhythm Note \(version) · build \(build)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            statusTabs
            updateNotice
            if workspace.tab == .pending {
                Toggle("Show Apple to-dos", isOn: $showApplePendingTodos)
                    .font(controller.font(size: 12))
                    .help("Show or hide Apple Calendar to-dos in Pending. Hiding does not delete them.")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }
            if workspace.tab != .events && workspace.statusFilter == .completed {
                completedChartSection
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        if workspace.tab == .events { eventsList }
                        else if workspace.statusFilter == .completed { completedList }
                        else { ForEach(workspace.categoriesVisible(in: workspace.tab)) { categoryView($0) } }
                        if workspace.filteredCount == 0 && workspace.tab.usesTaskList && workspace.statusFilter != .completed {
                            Text(emptyMessage).font(controller.font(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
                        }
                        if !workspace.error.isEmpty {
                            Text(workspace.error).font(controller.font(size: 11)).foregroundStyle(.red).padding(.top, 5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, workspace.statusFilter == .completed ? 10 : 15)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .clipped()
                .onChange(of: completedListScrollTarget) { target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    completedListScrollTarget = nil
                }
            }
            if workspace.tab == .todo || workspace.tab == .pending { composer }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: workspace.tab)
        .buttonStyle(.plain).font(controller.font(size: 12)).foregroundStyle(controller.ink).tint(controller.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(foldUpGesture)
        .overlay(alignment: .top) { NoteResizeArea(controller: controller, edges: .top).frame(height: 5).padding(.horizontal, 14) }
        .overlay(alignment: .bottom) { NoteResizeArea(controller: controller, edges: .bottom).frame(height: 5).padding(.horizontal, 14) }
        .overlay(alignment: .leading) { NoteResizeArea(controller: controller, edges: .left).frame(width: 5).padding(.vertical, 14) }
        .overlay(alignment: .trailing) { NoteResizeArea(controller: controller, edges: .right).frame(width: 5).padding(.vertical, 14) }
        .overlay(alignment: .topLeading) { NoteResizeArea(controller: controller, edges: [.top, .left]).frame(width: 8, height: 8) }
        .overlay(alignment: .topTrailing) { NoteResizeArea(controller: controller, edges: [.top, .right]).frame(width: 8, height: 8) }
        .overlay(alignment: .bottomLeading) { NoteResizeArea(controller: controller, edges: [.bottom, .left]).frame(width: 8, height: 8) }
        .overlay(alignment: .bottomTrailing) { NoteResizeArea(controller: controller, edges: [.bottom, .right]).frame(width: 8, height: 8) }
        .environment(\.colorScheme, controller.theme.scheme)
        .popover(isPresented: $showAppearance, arrowEdge: .top) { NoteAppearanceView(controller: controller) { showAppearance = false } }
        .popover(isPresented: $showAccount, arrowEdge: .top) { NoteAccountView(controller: controller) { showAccount = false } }
        .sheet(isPresented: $showTrash) { NoteTrashView(workspace: workspace, controller: controller) { showTrash = false } }
        .confirmationDialog(
            "Delete “\(categoryPendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { categoryPendingDelete != nil }, set: { if !$0 { categoryPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete category", role: .destructive) {
                if let id = categoryPendingDelete?.id { workspace.deleteCategory(id) }
                categoryPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { categoryPendingDelete = nil }
        } message: {
            if let group = categoryPendingDelete {
                if group.items.isEmpty {
                    Text("This category has no tasks.")
                } else {
                    Text("All \(group.items.count) task(s) in every list will move to Recently deleted.")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNoteAccount)) { notice in if notice.object == nil || notice.object as? AppController === controller { showAccount = true } }
        .onAppear {
            refreshAppleDeadlines()
            Task { await updates.check() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refreshAppleDeadlines() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshAppleDeadlines() }
        .onChange(of: workspace.selectedDay) { _ in controller.dateChanged() }
        .onChange(of: inputFocused) { controller.editing = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .captureNoteTask)) { _ in newCategory = false; inputFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .addNoteCategory)) { notice in if notice.object == nil || notice.object as? AppController === controller { newCategory = true; input = ""; inputFocused = true } }
        .onExitCommand { if newCategory || !input.isEmpty { newCategory = false; input = ""; inputFocused = false } else { controller.minimizeToMenuBar() } }
    }

    @ViewBuilder private var updateNotice: some View {
        if let release = updates.availableRelease {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(controller.ink.opacity(0.65))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rhythm Note \(release.tagName) is available").font(controller.font(size: 11, weight: .semibold))
                    Text("Download the latest Mac build on GitHub.").font(controller.font(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("View") { updates.openAvailableRelease() }.font(controller.font(size: 10, weight: .semibold))
                Button { updates.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                    .accessibilityLabel("Dismiss update notice")
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .padding(.horizontal, 12).padding(.top, 8)
        } else if let message = updates.statusMessage {
            HStack {
                Text(message).font(controller.font(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { updates.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                    .accessibilityLabel("Dismiss update status")
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
            Menu {
                Button(appVersionLabel) {}.disabled(true)
                Button("Check for updates…") {
                    Task { await updates.check(force: true) }
                }
                Divider()
                Button("Minimize to menu bar") { controller.minimizeToMenuBar() }
                Button("Fold into circle") { controller.collapse() }
                Button("Undo last change") { workspace.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!workspace.canUndo)
                Button(workspace.trash.isEmpty ? "Recently deleted" : "Recently deleted (\(workspace.trash.count))") { showTrash = true }
                Divider()
                Button("Appearance…") { showAppearance = true }
                Menu("Typeface") {
                    ForEach(NoteTypeface.allCases) { face in
                        Button { controller.typeface = face } label: {
                            if face == controller.typeface { Label(face.title, systemImage: "checkmark") }
                            else { Text(face.title + (face.available ? "" : " — not installed")) }
                        }.disabled(!face.available)
                    }
                }
                Menu("Open note window") {
                    ForEach(controller.openDays, id: \.self) { day in Button(day) { controller.newWindow(day: day) } }
                }
                Button("Open next day in new window") { controller.newWindow(day: NoteDay.offset(workspace.selectedDay, by: 1)) }
                Button(account.connected ? "Account · " + (account.email ?? "Connected") : "Connect account…") { showAccount = true }
                Button("Canvas updates…") { NSWorkspace.shared.open(URL(string: "https://campus-rhythm-one.vercel.app/source-updates")!) }
                Button("Reset note size") { controller.resetSize() }
                Button("Close this note window") { controller.closeNoteWindow() }
            } label: { Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 18, height: 22) }
                .menuStyle(.borderlessButton).fixedSize().help("Note options").accessibilityLabel("Note options")
            NoteDragArea().overlay { Image(systemName: "line.3.horizontal").font(.system(size: 8)).foregroundStyle(.tertiary).allowsHitTesting(false) }.frame(width: 12, height: 25).help("Drag to move this note")
            }.frame(width: 87, alignment: .leading)
            HStack(spacing: 2) {
                Button { workspace.shiftDay(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 10, weight: .medium)).frame(width: 26, height: 28).contentShape(Rectangle()) }.accessibilityLabel("Previous day").opacity(hoveringDate ? 0.9 : 0.4)
                Button { showDate = true } label: { Text(dateLabel).font(controller.font(size: 10)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 26) }.overlay { NoteDragArea(onClick: { showDate = true }) }.accessibilityLabel("Choose date: " + workspace.selectedDay)
                    .popover(isPresented: $showDate) {
                        VStack(spacing: 12) {
                            DatePicker("Date", selection: Binding(get: { NoteDay.date(workspace.selectedDay) ?? Date() }, set: { workspace.selectedDay = NoteDay.key($0) }), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                            Button("Today") { workspace.selectedDay = NoteDay.key(); showDate = false }
                            Button("Open this day in a new window") { controller.newWindow(day: workspace.selectedDay); showDate = false }
                            Button("Open next day in a new window") { controller.newWindow(day: NoteDay.offset(workspace.selectedDay, by: 1)); showDate = false }
                        }.padding(16).frame(width: 270).font(controller.font(size: 11)).environment(\.colorScheme, controller.theme.scheme)
                    }
                Button { workspace.shiftDay(1) } label: { Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).frame(width: 26, height: 28).contentShape(Rectangle()) }.accessibilityLabel("Next day").opacity(hoveringDate ? 0.9 : 0.4)
            }.frame(maxWidth: .infinity).onHover { hoveringDate = $0 }
            HStack(spacing: 8) {
            Button { controller.togglePin() } label: {
                Image(systemName: controller.pinned ? "pin.circle.fill" : "pin.circle").font(.system(size: 14))
                    .foregroundStyle(controller.ink.opacity(controller.pinned ? 0.85 : 0.5)).frame(width: 20, height: 22)
            }.help(controller.pinned ? "Unpin · note can fold when you click away" : "Pin · stay open and on top")
                .accessibilityLabel(controller.pinned ? "Unpin note" : "Pin note")
            Button { controller.collapse() } label: {
                Image(systemName: "smallcircle.filled.circle").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(controller.ink.opacity(0.58))
                    .frame(width: 24, height: 26).contentShape(Rectangle())
            }.help("Fold into a draggable circle").accessibilityLabel("Fold into circle")
            }.frame(width: 87, alignment: .trailing)
        }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            .background(NoteDragArea())
    }

    private var statusTabs: some View {
        NoteLiquidSegmentBar(workspace: workspace, tabs: NoteTab.allCases.filter { $0 != .forYou }, selection: $workspace.tab, font: controller.font, ink: controller.ink, reduceMotion: reduceMotion)
            .padding(.horizontal, 12).padding(.bottom, 2)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("", text: $input).textFieldStyle(.plain)
                .overlay(alignment: .leading) {
                    if input.isEmpty {
                        Text(newCategory ? "Name a category…" : workspace.tab == .pending ? "Keep an idea…" : "Add a task…")
                            .foregroundStyle(controller.ink.opacity(0.62))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .font(controller.font(size: 12)).focused($inputFocused).onSubmit(submit)
                .accessibilityLabel(newCategory ? "New category name" : "New task")
            if newCategory {
                Button { newCategory = false; input = "" } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 22, height: 24) }.help("Cancel category")
            } else {
                Menu {
                    ForEach(workspace.categories) { group in
                        Button { workspace.selectedCategory = group.id } label: {
                            if group.id == workspace.selectedCategory { Label(group.name, systemImage: "checkmark") } else { Text(group.name) }
                        }
                    }
                    Divider(); Button("New category…") { newCategory = true; input = ""; inputFocused = true }
                    if workspace.categories.count > 1 {
                        Divider()
                        ForEach(workspace.categories) { group in
                            Button("Delete “\(group.name)”") { categoryPendingDelete = group }
                        }
                    }
                } label: { Text(workspace.selectedName).font(controller.font(size: 10, weight: .medium)).lineLimit(1).frame(maxWidth: 64) }
                    .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary).help("Choose or create a category")
            }
            Button(action: submit) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium)).frame(width: 18, height: 24)
            }
            .help(newCategory ? "Add category" : "Add task")
            .accessibilityLabel(newCategory ? "Add category" : "Add task")
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(.horizontal, 12).padding(.vertical, 7)
            .background(controller.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(inputFocused ? 0.12 : 0.025), lineWidth: 0.5))
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }

    private func categoryView(_ group: NoteCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { workspace.toggleCategory(group.id) } label: {
                    Image(systemName: group.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 10, height: 22)
                }.accessibilityLabel((group.collapsed ? "Expand " : "Collapse ") + group.name)
                if renaming == group.id {
                    TextField("Category name", text: $renameText).textFieldStyle(.plain).font(controller.font(size: 12, weight: .semibold))
                        .onSubmit { workspace.renameCategory(group.id, renameText); renaming = nil; controller.editing = false }
                        .onAppear { controller.editing = true }
                } else {
                    Text(group.name).font(controller.font(size: 12, weight: .semibold)).foregroundStyle(controller.ink.opacity(0.82))
                        .onTapGesture { workspace.toggleCategory(group.id) }
                        .onDrag { workspace.dragProvider(NoteDrag(kind: .category, id: group.id)) }
                }
                if group.collapsed { Text("\(workspace.items(in: group).count)").font(controller.font(size: 9)).foregroundStyle(.secondary) }
                Spacer()
                NoteDragHandle(workspace: workspace, source: NoteDrag(kind: .category, id: group.id), name: group.name)
                Button { workspace.selectedCategory = group.id; newCategory = false; inputFocused = true } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(width: 22, height: 22)
                }.opacity(hoveredCategory == group.id ? 1 : 0.45).help("Add to " + group.name).accessibilityLabel("Add to " + group.name)
            }.contextMenu {
                Button("Rename category…") { renameText = group.name; renaming = group.id }
                Button("Add a task") { workspace.selectedCategory = group.id; inputFocused = true }
                if workspace.categories.count > 1 {
                    Divider()
                    if group.items.isEmpty {
                        Button("Delete empty category") { workspace.deleteCategory(group.id) }
                    } else {
                        Button("Delete category", role: .destructive) { categoryPendingDelete = group }
                    }
                }
                Divider()
                if let first = workspace.categories.first, first.id != group.id { Button("Move category to top") { workspace.reorderCategory(group.id, relativeTo: first.id) } }
            }.modifier(NoteOrderZone(workspace: workspace, zone: .header(group.id)))
            if !group.collapsed {
                ForEach(workspace.items(in: group)) { item in
                    NoteRow(item: item, categoryID: group.id, workspace: workspace, controller: controller).padding(.leading, 7)
                        .modifier(NoteOrderZone(workspace: workspace, zone: .row(category: group.id, task: item.id)))
                }
            }
            Color.clear.frame(height: 5).modifier(NoteOrderZone(workspace: workspace, zone: .tail(group.id)))
        }.onHover { hoveredCategory = $0 ? group.id : nil }
    }
    private var eventsList: some View {
        VStack(alignment: .leading, spacing: 13) {
            if showAppleEvents { AppleCalendarView(day: workspace.selectedDay, workspace: workspace, controller: controller) }
            if showOnlineEvents {
            Divider()
            HStack {
                Text("Calendar").font(controller.font(size: 12, weight: .semibold))
                Spacer()
                if account.busy { ProgressView().controlSize(.small) }
                else if account.connected { Button { Task { await account.sync() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh events") }
            }
            if !account.connected {
                Text("Connect your Campus Rhythm account to see this day’s events.").font(controller.font(size: 11)).foregroundStyle(.secondary)
                Button("Connect account") { showAccount = true }.font(controller.font(size: 11))
            } else {
                ForEach(workspace.events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(controller.ink.opacity(0.35)).frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(controller.font(size: 12, weight: .medium))
                            if event.allDay { Text("All day").font(controller.font(size: 10)).foregroundStyle(.secondary) }
                            else { HStack(spacing: 3) { Text(event.start, style: .time); Text("–"); Text(event.end, style: .time) }.font(controller.font(size: 10)).foregroundStyle(.secondary) }
                            if !event.location.isEmpty { Text(event.location).font(controller.font(size: 10)).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(10).background(controller.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                if workspace.events.isEmpty { Text("No calendar events for this day.").font(controller.font(size: 11)).foregroundStyle(.secondary) }
                Text(account.status).font(controller.font(size: 9)).foregroundStyle(.secondary)
                Button("Open calendar") { NSWorkspace.shared.open(URL(string: "https://campus-rhythm-one.vercel.app/calendar")!) }.font(controller.font(size: 11))
            }
            }
            Divider()
            Toggle("Apple Calendar", isOn: $showAppleEvents)
            Toggle("Campus Rhythm online", isOn: $showOnlineEvents)
        }
    }
    private var completedList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(workspace.completedDays) { day in
                completedDay(day)
            }
        }
    }
    private let weekBarMaxHeight: CGFloat = 44
    private var completedChartScale: CGFloat { CGFloat(min(1.5, max(1, controller.textScale))) }

    private var completedChartSection: some View {
        weekCompleted
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(controller.ink.opacity(0.08)).frame(height: 1)
            }
    }

    /// Trackpad horizontal scroll: 56 daily bars, right edge = today, snapped one day at a time.
    private var weekCompleted: some View {
        GeometryReader { geo in
            let viewportWidth = max(geo.size.width, 1)
            let dayWidth = viewportWidth / 7
            let maxScrollX = dayWidth * CGFloat(CompletedChartWindow.maximumStartIndex)
            let visibleEndOffset = CompletedChartWindow.endOffset(scrollX: completedChartScrollX, dayWidth: dayWidth)
            let visibleDays = completedChartDays(endOffset: visibleEndOffset)
            let visibleCounts = completedCounts(for: visibleDays)
            let peak = max(visibleCounts.max() ?? 1, 1)
            let days = completedChartRange()
            let counts = completedCounts(for: days)
            let weekdayFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.dateFormat = "EEE"
                return formatter
            }()
            VStack(alignment: .leading, spacing: 6) {
                Text(completedChartTitle(total: visibleCounts.reduce(0, +), days: visibleDays, endOffset: visibleEndOffset))
                    .font(controller.font(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: .leading) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            let barHovered = weekBarHovered(pageEndOffset: 0, index: index)
                            VStack(spacing: 3) {
                                Text(counts[index] == 0 ? "" : "\(counts[index])")
                                    .font(controller.font(size: 9, weight: barHovered ? .semibold : .regular))
                                    .foregroundStyle(controller.ink.opacity(barHovered ? 1 : 0.5))
                                weekStackedBar(day: day, total: counts[index], peak: peak, index: index, pageEndOffset: 0)
                                Text(weekdayFormatter.string(from: day))
                                    .font(controller.font(size: 9, weight: barHovered ? .semibold : .regular))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 3)
                            .frame(width: dayWidth)
                            .overlay(alignment: index >= 4 ? .topTrailing : .topLeading) {
                                if barHovered {
                                    weekGlassTip(day)
                                        .fixedSize(horizontal: true, vertical: true)
                                        .offset(x: index >= 4 ? -4 : 14, y: -28)
                                }
                            }
                            .zIndex(barHovered ? 2 : 0)
                            .modifier(NoteOrderZone(workspace: workspace, zone: .completedChart(completedDayID(for: day))))
                            .onHover { hovering in
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) {
                                    if hovering {
                                        hoveredWeekBar = (0, index)
                                    } else if weekBarHovered(pageEndOffset: 0, index: index) {
                                        hoveredWeekBar = nil
                                    }
                                }
                            }
                            .onTapGesture { jumpToCompletedDay(day) }
                            .help("Jump to done list for this day")
                        }
                    }
                    .offset(x: -completedChartScrollX)
                }
                .frame(width: viewportWidth, height: 78 * completedChartScale, alignment: .leading)
                .clipped()
                .padding(.top, 2)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .onAppear { syncCompletedChartScroll(for: viewportWidth) }
            .onChange(of: geo.size.width) { width in
                syncCompletedChartScroll(for: max(width, 1))
            }
            .background {
                NoteChartHorizontalWheelCapture(
                    onScroll: { delta in
                        guard maxScrollX > 0 else { return }
                        completedChartScrollX = min(maxScrollX, max(0, completedChartScrollX - delta))
                    },
                    onScrollEnd: {
                        guard dayWidth > 1 else { return }
                        let day = round(completedChartScrollX / dayWidth)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88)) {
                            completedChartScrollX = min(maxScrollX, max(0, day * dayWidth))
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 128 * completedChartScale)
        .accessibilityLabel("Completed tasks chart")
        .accessibilityHint("Two-finger swipe horizontally to browse one day at a time. The title totals the seven visible days. Tap a day bar to jump to that day in the list below.")
    }

    private func syncCompletedChartScroll(for pageWidth: CGFloat) {
        guard pageWidth > 1 else { return }
        let previous = completedChartViewportWidth
        completedChartViewportWidth = pageWidth
        let maxScrollX = pageWidth * 7
        if !completedChartDidAnchorToday {
            completedChartScrollX = maxScrollX
            completedChartDidAnchorToday = true
        } else if previous > 1 {
            completedChartScrollX = min(maxScrollX, max(0, completedChartScrollX / (previous * 7) * maxScrollX))
        }
    }

    private func completedChartRange() -> [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        return (0..<CompletedChartWindow.totalDayCount).compactMap {
            calendar.date(byAdding: .day, value: $0 - (CompletedChartWindow.totalDayCount - 1), to: today)
        }
    }

    private func weekBarHovered(pageEndOffset: Int, index: Int) -> Bool {
        hoveredWeekBar?.page == pageEndOffset && hoveredWeekBar?.bar == index
    }

    /// Seven consecutive days ending on `today + endOffset`.
    private func completedChartDays(endOffset: Int) -> [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.date(byAdding: .day, value: endOffset, to: calendar.startOfDay(for: Date())) ?? Date()
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: end) }
    }

    private func completedCounts(for days: [Date]) -> [Int] {
        let calendar = Calendar.autoupdatingCurrent
        return days.map { day in
            workspace.completedDays.first { $0.day.map { calendar.isDate($0, inSameDayAs: day) } ?? false }?.entries.count ?? 0
        }
    }

    private func completedChartTitle(total: Int, days: [Date], endOffset: Int) -> String {
        let count = total == 1 ? "1 task" : "\(total) tasks"
        guard let first = days.first, let last = days.last else { return "Completed \(count)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        let range = "\(formatter.string(from: first)) – \(formatter.string(from: last))"
        if endOffset == 0 {
            return "Completed \(count) in the last 7 days"
        }
        return "Completed \(count) · \(range)"
    }

    private func weekStackedBar(day: Date, total: Int, peak: Int, index: Int, pageEndOffset: Int) -> some View {
        let stacks = categoryStacks(on: day)
        let barHeight = total == 0 ? 3 : max(4, weekBarMaxHeight * CGFloat(total) / CGFloat(peak))
        let hovered = weekBarHovered(pageEndOffset: pageEndOffset, index: index)
        return Group {
            if total == 0 {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(controller.ink.opacity(0.1))
                    .frame(height: 3)
            } else if hovered {
                VStack(spacing: 1) {
                    ForEach(stacks.reversed(), id: \.0) { name, count in
                        weekCategoryColor(name)
                            .frame(height: max(2, barHeight * CGFloat(count) / CGFloat(total)))
                    }
                }
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(controller.ink.opacity(0.72))
                    .frame(height: barHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: hovered)
        .scaleEffect(hovered ? 1.1 : 1, anchor: .bottom)
    }

    private func weekCategoryColor(_ name: String) -> Color {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "work": return Color(red: 0.94, green: 0.52, blue: 0.24)
        case "personal": return Color(red: 0.32, green: 0.76, blue: 0.58)
        case "study": return Color(red: 0.38, green: 0.56, blue: 0.96)
        default:
            let slot = abs(name.hashValue) % 5
            let hues: [Double] = [0.12, 0.58, 0.78, 0.32, 0.88]
            return Color(hue: hues[slot], saturation: 0.52, brightness: 0.88)
        }
    }

    private func weekGlassTip(_ day: Date) -> some View {
        let rows = categoryStacks(on: day)
        return VStack(alignment: .leading, spacing: 3) {
            if rows.isEmpty {
                Text("Nothing").font(controller.font(size: 10))
            } else {
                ForEach(rows, id: \.0) { name, count in
                    HStack(spacing: 5) {
                        Circle().fill(weekCategoryColor(name)).frame(width: 6, height: 6)
                        Text("\(count) \(name)").font(controller.font(size: 10, weight: .medium)).foregroundStyle(controller.ink)
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
        .allowsHitTesting(false)
    }

    private func categoryStacks(on day: Date) -> [(String, Int)] {
        let tallies = Dictionary(uniqueKeysWithValues: categoryCounts(on: day))
        var ordered: [(String, Int)] = []
        for category in workspace.categories {
            if let count = tallies[category.name], count > 0 { ordered.append((category.name, count)) }
        }
        for (name, count) in categoryCounts(on: day) where !workspace.categories.contains(where: { $0.name == name }) {
            ordered.append((name, count))
        }
        return ordered
    }

    private func categoryCounts(on day: Date) -> [(String, Int)] {
        let calendar = Calendar.autoupdatingCurrent
        let entries = workspace.completedDays.first { $0.day.map { calendar.isDate($0, inSameDayAs: day) } ?? false }?.entries ?? []
        return Dictionary(grouping: entries, by: \.categoryName).map { ($0.key, $0.value.count) }.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
    private func jumpToCompletedDay(_ date: Date) {
        let id = completedDayID(for: date)
        let found = workspace.completedDays.contains(where: { $0.id == id })
        // #region agent log
        AgentDebugLog.emit(hypothesisId: "D", location: "PanelView:jumpToCompletedDay", message: found ? "scroll target set" : "no completed section for day", data: [
            "dayID": id,
            "completedDayCount": String(workspace.completedDays.count),
        ])
        // #endregion
        if found { completedListScrollTarget = id }
    }

    private func completedDay(_ day: CompletedDay) -> some View {
        let dayID = day.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(completedDayLabel(day.day)).font(controller.font(size: 11, weight: .semibold))
                Spacer()
                Text("\(day.entries.count) done").font(controller.font(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 3)
            .modifier(NoteOrderZone(workspace: workspace, zone: .completedHeader(dayID)))
            ForEach(day.entries) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    NoteRow(item: entry.item, categoryID: entry.categoryID, workspace: workspace, controller: controller, allowsReordering: true)
                        .modifier(NoteOrderZone(workspace: workspace, zone: .completedRow(dayID: dayID, task: entry.id)))
                    HStack(spacing: 3) {
                        Text(entry.categoryName)
                        if let date = entry.item.completedAt {
                            Text("·")
                            Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        }
                    }
                    .font(controller.font(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 33)
                    .padding(.bottom, 5)
                }
            }
            Color.clear.frame(height: 4)
                .modifier(NoteOrderZone(workspace: workspace, zone: .completedTail(dayID)))
        }
        .id(dayID)
    }
    private func completedDayID(for day: Date) -> String {
        String(Calendar.autoupdatingCurrent.startOfDay(for: day).timeIntervalSince1970)
    }
    private func completedDayLabel(_ date: Date?) -> String {
        guard let date else { return "Earlier · date not recorded" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US"); formatter.dateFormat = "EEE, MMM d, yyyy"
        let label = formatter.string(from: date)
        if Calendar.autoupdatingCurrent.isDateInToday(date) { return "Today · " + label }
        if Calendar.autoupdatingCurrent.isDateInYesterday(date) { return "Yesterday · " + label }
        return label
    }
    private var emptyMessage: String {
        if workspace.tab == .pending, !showApplePendingTodos, pendingHasAppleImports, !pendingHasOwnIdeas {
            return "Apple Calendar to-dos are hidden. Your own ideas stay here."
        }
        switch workspace.statusFilter {
        case .todo: return "A little space for what’s next."
        case .pending: return "Ideas without a date. Move one to a day when you’re ready."
        case .completed: return "Completed tasks will appear here."
        case .cancelled: return "Cancelled tasks will appear here."
        }
    }
    private var pendingHasAppleImports: Bool {
        workspace.document.categories.flatMap(\.items).contains { $0.status == .pending && $0.calendarEventKey != nil }
    }
    private var pendingHasOwnIdeas: Bool {
        workspace.document.categories.flatMap(\.items).contains { $0.status == .pending && $0.calendarEventKey == nil }
    }
    private func refreshAppleDeadlines() {
        let connection = AppleCalendarConnection.shared
        connection.refresh(day: workspace.selectedDay)
        connection.syncImportedPending(into: workspace)
    }
    private var foldUpGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard !controller.pinned, !controller.editing, !inputFocused else { return }
                if value.translation.height < -44 && abs(value.translation.width) < 72 {
                    controller.collapse()
                }
            }
    }
    private func submit() {
        if newCategory {
            if workspace.addCategory(input) { input = ""; newCategory = false }
        } else if workspace.add(input) {
            input = ""
        }
        inputFocused = true
    }
}

private struct NoteRow: View {
    let item: NoteItem
    let categoryID: UUID
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    var allowsReordering = true
    var allowsSwipeDelete = true
    @State private var editing = false
    @State private var value = ""
    @State private var swipeOffset: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var checked: Bool { item.done || item.isChecked }
    var body: some View {
        NoteSwipeDeleteRow(offset: $swipeOffset, enabled: allowsSwipeDelete, reduceMotion: reduceMotion, onDelete: { workspace.delete(item.id) }) {
            rowBody
        }
    }
    private var rowBody: some View {
        HStack(alignment: .top, spacing: 9) {
            Button { workspace.toggle(item.id) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(checked ? 0 : 0.32), lineWidth: 1)
                    if checked { RoundedRectangle(cornerRadius: 3).fill(controller.ink); Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(controller.theme == .dark ? .black : .white) }
                    if item.status == .cancelled { Image(systemName: "minus").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) }
                }.frame(width: 13, height: 13).offset(y: -3).frame(width: 24, height: 24).contentShape(Rectangle())
            }.accessibilityLabel((item.done ? "Reopen " : item.isChecked ? "Uncheck " : "Check off ") + item.title)
                .accessibilityValue(item.done ? "Completed" : item.isChecked ? "Checked, awaiting Mark complete" : "Not checked")
            if editing {
                TextField("Task", text: $value, axis: .vertical).textFieldStyle(.plain).font(controller.taskFont()).focused($focused)
                    .onSubmit { finishEdit() }.onChange(of: focused) { if !$0 { finishEdit() } }
                    .onExitCommand { editing = false; controller.editing = false }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    if allowsReordering {
                        taskText.onDrag { workspace.dragProvider(NoteDrag(kind: .task, id: item.id)) }
                    } else {
                        taskText
                    }
                    if item.isChecked && item.status.isOpen {
                        Button { workspace.markComplete(item.id) } label: {
                            Label("Mark complete", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color(white: 0.13))
                                .font(controller.font(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(.white.opacity(0.8), in: Capsule())
                                .overlay(Capsule().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                                .contentShape(Capsule())
                        }.help("Save to today’s done list").accessibilityLabel("Mark complete: " + item.title)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if allowsReordering { NoteDragHandle(workspace: workspace, source: NoteDrag(kind: .task, id: item.id), name: item.title) }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Rename task…") { edit() }
            Menu("Move to") { ForEach(workspace.categories) { category in Button(category.name) { workspace.move(item.id, to: category.id) } } }
            if allowsReordering, let group = workspace.categories.first(where: { $0.id == categoryID }), let first = workspace.items(in: group).first, first.id != item.id {
                Button("Move task to top") { workspace.reorderItem(item.id, to: categoryID, relativeTo: first.id) }
            }
            Divider()
            if item.isChecked && item.status.isOpen { Button("Mark complete") { workspace.markComplete(item.id) } }
            ForEach([NoteStatus.todo, .pending]) { status in if status != item.status { Button("Move to " + status.title) { workspace.setStatus(item.id, status) } } }
            Menu("Move to day") {
                Button("Today") { workspace.schedule(item.id, on: NoteDay.key()) }
                Button("Tomorrow") { workspace.schedule(item.id, on: NoteDay.offset(NoteDay.key(), by: 1)) }
                Button("Selected day · " + workspace.selectedDay) { workspace.schedule(item.id, on: workspace.selectedDay) }
            }.disabled(!item.status.isOpen)
            Menu("Highlight") {
                Button("None") { workspace.setHighlight(item.id, nil) }
                ForEach(NoteDesign.highlights, id: \.0) { color in Button(color.0) { workspace.setHighlight(item.id, color.1) } }
            }
            Menu("Text color") {
                Button("Default") { workspace.setTextColor(item.id, nil) }
                ForEach(NoteDesign.inks, id: \.0) { color in Button(color.0) { workspace.setTextColor(item.id, color.1) } }
            }
            Divider(); Button("Delete task") { workspace.delete(item.id) }
        }
    }
    private var taskText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(controller.taskFont()).lineSpacing(3)
                .foregroundStyle((item.textColor.map { Color(noteHex: $0) } ?? controller.ink).opacity(checked ? 0.46 : 0.95))
                .padding(.horizontal, item.highlight == nil ? 0 : 4).padding(.vertical, item.highlight == nil ? 0 : 2)
                .background(item.highlight.map { Color(noteHex: $0).opacity(controller.theme == .dark ? 0.3 : 0.4) } ?? .clear, in: RoundedRectangle(cornerRadius: 4))
                .strikethrough(checked).fixedSize(horizontal: false, vertical: true)
            if let due = TaskDueText.badgeLabel(day: item.dueDay, monthOnly: item.dueMonthOnly, dueMinute: item.dueMinute) {
                Text(due)
                    .font(controller.font(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(controller.ink.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
        .onTapGesture(count: 2) { edit() }.help("Double-click or right-click to rename this task")
    }
    private func edit() { value = item.title; editing = true; focused = true; controller.editing = true }
    private func finishEdit() { workspace.renameItem(item.id, value); editing = false; controller.editing = false }
}

private struct NoteSwipeDeleteRow<Content: View>: View {
    @Binding var offset: CGFloat
    let enabled: Bool
    let reduceMotion: Bool
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content
    private let reveal: CGFloat = 76
    var body: some View {
        ZStack(alignment: .trailing) {
            if enabled {
                Button(action: {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) { offset = 0 }
                    onDelete()
                }) {
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: reveal)
                        .frame(maxHeight: .infinity)
                        .background(Color(red: 0.92, green: 0.27, blue: 0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(offset < -10 ? 1 : 0)
            }
            content()
                .background(Color.clear)
                .offset(x: enabled ? min(0, offset) : 0)
                .gesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard enabled, abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { offset = value.translation.width }
            }
            .onEnded { value in
                guard enabled else { return }
                let open = value.translation.width < -reveal * 0.45 || value.predictedEndTranslation.width < -reveal
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                    offset = open ? -reveal : 0
                }
                if open && value.translation.width < -reveal * 0.9 { onDelete(); offset = 0 }
            }
    }
}

private struct NoteTrashView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recently deleted").font(controller.font(size: 14, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Close")
            }
            Text("Swipe left on a task to delete. Restore anything removed by mistake.").font(controller.font(size: 10)).foregroundStyle(.secondary)
            if workspace.trash.isEmpty {
                Text("Nothing here.").font(controller.font(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(workspace.trash) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.item.title).font(controller.taskFont()).lineLimit(3)
                                HStack(spacing: 6) {
                                    Text(entry.categoryName).font(controller.font(size: 10)).foregroundStyle(.secondary)
                                    Text("·").foregroundStyle(.secondary)
                                    Text(entry.deletedAt, style: .relative).font(controller.font(size: 10)).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 10) {
                                    Button("Restore") { workspace.restoreTrash(entry.id) }
                                    Button("Delete forever") { workspace.purgeTrash(entry.id) }.foregroundStyle(.red)
                                }.font(controller.font(size: 10, weight: .medium))
                            }
                            .padding(10)
                            .background(controller.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                Button("Empty recently deleted") { workspace.emptyTrash() }
                    .font(controller.font(size: 10))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(18)
        .frame(width: 320, height: min(420, CGFloat(120 + workspace.trash.count * 92)))
        .font(controller.font(size: 11))
        .foregroundStyle(controller.ink)
        .environment(\.colorScheme, controller.theme.scheme)
    }
}

private final class DragSurface: NSView {
    private var startPointer: NSPoint?
    private var startOrigin: NSPoint?
    var onClick: (() -> Void)?
    private var dragged = false
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { startPointer = window?.convertPoint(toScreen: event.locationInWindow); startOrigin = window?.frame.origin; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard let startPointer, let startOrigin else { return }
        guard let pointer = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        guard dragged || hypot(pointer.x - startPointer.x, pointer.y - startPointer.y) > 3 else { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + pointer.x - startPointer.x, y: startOrigin.y + pointer.y - startPointer.y))
    }
    override func mouseUp(with event: NSEvent) { let clicked = !dragged; startPointer = nil; startOrigin = nil; dragged = false; if clicked { onClick?() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
private struct NoteDragArea: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragSurface { let view = DragSurface(); view.onClick = onClick; return view }
    func updateNSView(_ nsView: DragSurface, context: Context) { nsView.onClick = onClick }
}
private final class ResizeSurface: NSView {
    var controller: AppController?
    var edges: NoteResizeEdges = [.bottom, .right]
    private var startPointer: NSPoint?
    private var startFrame: NSRect?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { startPointer = window?.convertPoint(toScreen: event.locationInWindow); startFrame = window?.frame }
    override func mouseDragged(with event: NSEvent) {
        guard let startPointer, let startFrame else { return }
        guard let pointer = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        controller?.resize(from: startFrame, translation: CGSize(width: pointer.x - startPointer.x, height: pointer.y - startPointer.y), edges: edges)
    }
    override func mouseUp(with event: NSEvent) { startPointer = nil; startFrame = nil; controller?.finishResize() }
    override func resetCursorRects() {
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        addCursorRect(bounds, cursor: horizontal && vertical ? .crosshair : horizontal ? .resizeLeftRight : .resizeUpDown)
    }
}
private struct NoteResizeArea: NSViewRepresentable {
    let controller: AppController
    let edges: NoteResizeEdges
    func makeNSView(context: Context) -> ResizeSurface { let view = ResizeSurface(); view.controller = controller; view.edges = edges; return view }
    func updateNSView(_ nsView: ResizeSurface, context: Context) { nsView.controller = controller; nsView.edges = edges }
}

extension Notification.Name {
    static let captureNoteTask = Notification.Name("mini.captureNoteTask")
    static let showNoteAccount = Notification.Name("mini.showNoteAccount")
    static let addNoteCategory = Notification.Name("mini.addNoteCategory")
}
