import AppKit
import SwiftUI
import NoteCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppController: NSObject, ObservableObject, NSApplicationDelegate, NSWindowDelegate {
    @Published var pinned = UserDefaults.standard.bool(forKey: "notePinned")
    @Published var textScale = UserDefaults.standard.object(forKey: "noteTextScale") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(textScale, forKey: "noteTextScale") }
    }
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font { typeface.font(size: size * min(1.5, max(0.7, textScale)), weight: weight) }
    func taskFont(weight: Font.Weight = .regular) -> Font { font(size: 11, weight: weight) }
    var backdropOpacity: Double { Double(NotePaperOpacity.backdrop(finish: glassFinish, slider: backgroundOpacity)) }
    func adjustText(_ delta: Double) {
        let next = min(1.5, max(0.7, textScale + delta))
        textScale = (next * 20).rounded() / 20
    }
    @Published var typeface = NoteTypeface(rawValue: UserDefaults.standard.string(forKey: "notePaperTypeface") ?? "monospaced") ?? .monospaced {
        didSet { UserDefaults.standard.set(typeface.rawValue, forKey: "notePaperTypeface"); saveAppearance() }
    }
    @Published var backgroundOpacity = UserDefaults.standard.object(forKey: "noteGlassPaperOpacityV1") as? Double ?? 0.65 {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "noteGlassPaperOpacityV1"); applyAppearance() }
    }
    @Published var circleOpacity = UserDefaults.standard.object(forKey: "noteCircleOpacityV1") as? Double ?? 0.55 {
        didSet { UserDefaults.standard.set(circleOpacity, forKey: "noteCircleOpacityV1"); applyAppearance() }
    }
    @Published var glassFinish = NoteGlassFinish(rawValue: UserDefaults.standard.string(forKey: "noteGlassFinishV1") ?? "glass") ?? .glass {
        didSet {
            UserDefaults.standard.set(glassFinish.rawValue, forKey: "noteGlassFinishV1")
            applyAppearance()
            refreshGlassMaterial()
        }
    }
    @Published var theme = NoteTheme(rawValue: UserDefaults.standard.string(forKey: "noteThemeV1") ?? "light") ?? .light {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "noteThemeV1"); applyAppearance() }
    }
    @Published var edgeStyle = NoteEdgeStyle(rawValue: UserDefaults.standard.string(forKey: "noteEdgeV1") ?? "rounded") ?? .rounded {
        didSet { UserDefaults.standard.set(edgeStyle.rawValue, forKey: "noteEdgeV1"); applyAppearance() }
    }
    @Published var paperHex = UserDefaults.standard.string(forKey: "notePaperColorV1") ?? "" {
        didSet { UserDefaults.standard.set(paperHex, forKey: "notePaperColorV1"); applyAppearance() }
    }
    @Published var inkHex = UserDefaults.standard.string(forKey: "noteInkColorV1") ?? "" {
        didSet { UserDefaults.standard.set(inkHex, forKey: "noteInkColorV1"); saveAppearance() }
    }
    var ink: Color { inkHex.isEmpty ? theme.ink : Color(noteHex: inkHex) }
    var paper: NSColor { NSColor(noteHex: paperHex) ?? theme.paper }
    let account = AccountConnection.shared
    private weak var root: AppController?
    private var children: [AppController] = []
    private var loadingAppearance = false
    var openDays: [String] { let owner = root ?? self; return Array(Set(([owner] + owner.children).compactMap { $0.workspace?.selectedDay })).sorted() }
    var editing = false
    private var enabled = true
    private var panel: FloatingPanel!
    private var bubble: NSPanel!
    private var item: NSStatusItem!
    private(set) var workspace: Workspace!
    private var observer: NSObjectProtocol?
    private var menuObserver: NSObjectProtocol?
    private var undoMonitor: Any?
    private var dateTimer: Timer?
    private var observedToday = NoteDay.key()
    private var autoFoldWorkItem: DispatchWorkItem?
    private var frameName: String { "RhythmNoteWindowV3-" + (workspace?.selectedDay ?? "today") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let today = NoteDay.key()
        let previousToday = UserDefaults.standard.string(forKey: "noteObservedTodayV1") ?? today
        let days = Array(Set((UserDefaults.standard.stringArray(forKey: "noteOpenDaysV1") ?? []).filter(NoteDay.isValid).map { NoteDay.rollover($0, from: previousToday, to: today) })).sorted()
        let crossedMidnight = previousToday != today
        UserDefaults.standard.set(today, forKey: "noteObservedTodayV1")
        setupWindow(day: days.first ?? NoteDay.key(), primary: true)
        observedToday = today
        if crossedMidnight {
            let carried = workspace.openTodoCount(on: previousToday)
            // #region agent log
            AgentDebugLog.emit(hypothesisId: "E", location: "App:launch", message: "day rollover on launch", data: [
                "previousToday": previousToday,
                "today": today,
                "carried": String(carried),
            ])
            // #endregion
            if carried > 0 {
                Task { await NoteNotifications.notifyCarriedTodos(from: previousToday, count: carried) }
            }
        }
        for day in days.dropFirst() { newWindow(day: day) }
        account.resume()
        NoteNotifications.configure()
        NoteNotificationRouter.shared.openDay = { [weak self] day in self?.openDayForReview(day) }
    }
    private func setupWindow(day: String, primary: Bool) {
        workspace = Workspace(day: day)
        loadAppearance()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = workspace.preferredHeight
        panel = FloatingPanel(contentRect: NSRect(x: screen.maxX - 384, y: screen.maxY - height - 18, width: 380, height: height), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.title = "Rhythm Note · " + day; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = pinned ? .floating : .normal; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 340, height: 300)
        panel.maxSize = NSSize(width: 760, height: 1100)
        panel.contentView = makeNoteSurface(MiniPanelView(workspace: workspace, controller: self))
        if !panel.setFrameUsingName(frameName), primary { _ = panel.setFrameUsingName("RhythmNoteWindowV2") }
        _ = panel.setFrameAutosaveName(frameName)
        panel.delegate = self
        fitOnScreen()

        let circleSide: CGFloat = 44
        bubble = NSPanel(contentRect: NSRect(x: screen.maxX - circleSide - 14, y: screen.maxY - circleSide - 10, width: circleSide, height: circleSide), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble.title = "Campus Rhythm To-Do Notes"; bubble.isReleasedWhenClosed = false; bubble.backgroundColor = .clear; bubble.isOpaque = false
        bubble.hasShadow = true; bubble.level = .floating; bubble.hidesOnDeactivate = false
        bubble.isMovableByWindowBackground = true
        bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        bubble.contentView = makeNoteSurface(NoteCircle(workspace: workspace, controller: self), circle: true)
        bubble.contentView?.wantsLayer = true
        bubble.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        if let position = UserDefaults.standard.string(forKey: "noteCircleOrigin") {
            bubble.setFrameOrigin(NSPointFromString(position)); fitCircleOnScreen()
        } else { placeBubble() }

        applyAppearance()
        if primary {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Rhythm Note")
            button.toolTip = "Campus Rhythm To-Do Notes · click to open or minimize · right-click for options"
            button.target = self; button.action = #selector(statusClicked); button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        }
        // Editing tasks never changes a manually chosen window size.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.fitOnScreen(); self?.fitCircleOnScreen() }
        }
        // SwiftUI creates native menus outside the view tree. Style those as well.
        if primary { menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated {
                guard let self else { return }; let active = ([self] + self.children).first { $0.panel === NSApp.keyWindow } ?? self; active.styleMenu(menu)
            }
        }
        }
        dateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let today = NoteDay.key()
                if today != self.observedToday && !self.editing {
                    let yesterday = self.observedToday
                    let carried = self.workspace.openTodoCount(on: yesterday)
                    self.workspace.selectedDay = NoteDay.rollover(self.workspace.selectedDay, from: yesterday, to: today)
                    self.observedToday = today
                    UserDefaults.standard.set(today, forKey: "noteObservedTodayV1")
                    if carried > 0 {
                        Task { await NoteNotifications.notifyCarriedTodos(from: yesterday, count: carried) }
                    }
                }
                self.objectWillChange.send()
            }
        }
        if primary, undoMonitor == nil {
            undoMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "z" else { return event }
                if let text = NSApp.keyWindow?.firstResponder as? NSTextView, !text.string.isEmpty {
                    return event
                }
                guard self.workspace?.canUndo == true else { return event }
                self.workspace?.undo()
                return nil
            }
        }
        switch primary ? UserDefaults.standard.string(forKey: "notePresentation") : "note" {
        case "menu": minimizeToMenuBar()
        case "circle": bubble.orderFrontRegardless()
        case "off": enabled = false
        default: expand()
        }
    }
    private func saveAppearance() {
        guard !loadingAppearance, let workspace else { return }
        UserDefaults.standard.set(["theme": theme.rawValue, "edge": edgeStyle.rawValue, "finish": glassFinish.rawValue, "paper": paperHex, "ink": inkHex, "opacity": backgroundOpacity, "font": typeface.rawValue, "pinned": pinned], forKey: "noteAppearance-" + workspace.selectedDay)
    }
    private func loadAppearance() {
        guard let workspace, let value = UserDefaults.standard.dictionary(forKey: "noteAppearance-" + workspace.selectedDay) else { return }
        loadingAppearance = true
        theme = NoteTheme(rawValue: value["theme"] as? String ?? "light") ?? .light
        edgeStyle = NoteEdgeStyle(rawValue: value["edge"] as? String ?? "rounded") ?? .rounded
        glassFinish = NoteGlassFinish(rawValue: value["finish"] as? String ?? "frosted") ?? .frosted
        paperHex = value["paper"] as? String ?? ""; inkHex = value["ink"] as? String ?? ""
        backgroundOpacity = value["opacity"] as? Double ?? 0.65
        typeface = NoteTypeface(rawValue: value["font"] as? String ?? "monospaced") ?? .monospaced
        pinned = value["pinned"] as? Bool ?? pinned
        loadingAppearance = false; panel?.level = pinned ? .floating : .normal
        applyAppearance()
    }
    private func applyAppearance() {
        guard !loadingAppearance else { return }; saveAppearance()
        panel?.appearance = theme.appearance; bubble?.appearance = theme.appearance
        (panel?.contentView as? NoteSurfaceView)?.configure(theme: theme, edge: edgeStyle, paper: paper, opacity: backgroundOpacity, finish: glassFinish)
        (bubble?.contentView as? NoteSurfaceView)?.configure(theme: theme, edge: .rounded, paper: paper, opacity: circleOpacity, finish: .glass)
        refreshGlassMaterial()
        panel?.hasShadow = edgeStyle != .minimal
    }
    private func refreshGlassMaterial() {
        (panel?.contentView as? NoteSurfaceView)?.refreshMaterial()
        (bubble?.contentView as? NoteSurfaceView)?.refreshMaterial()
    }
    func newWindow(day: String) {
        let owner = root ?? self
        if let existing = ([owner] + owner.children).first(where: { $0.workspace?.selectedDay == day }) { existing.expand(); return }
        let child = AppController(); child.root = owner; owner.children.append(child)
        child.setupWindow(day: day, primary: false)
        let frame = currentFrame
        let visible = NSScreen.main?.visibleFrame ?? frame
        let proposed = frame.maxX + child.panel.frame.width + 18 <= visible.maxX ? frame.maxX + 18 : max(visible.minX + 8, frame.minX - child.panel.frame.width - 18)
        child.panel.setFrameOrigin(NSPoint(x: proposed, y: frame.maxY - child.panel.frame.height))
        child.fitOnScreen(); owner.saveOpenDays(); for note in [owner] + owner.children { note.objectWillChange.send() }
    }
    func closeNoteWindow() {
        if root == nil { minimizeToMenuBar(); return }
        dateTimer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) }
        panel.orderOut(nil); bubble.orderOut(nil); panel.contentView = nil; bubble.contentView = nil
        let owner = root!; owner.children.removeAll { $0 === self }; owner.saveOpenDays(); owner.objectWillChange.send()
    }
    func saveOpenDays() {
        let owner = root ?? self
        UserDefaults.standard.set(([owner] + owner.children).compactMap { $0.workspace?.selectedDay }, forKey: "noteOpenDaysV1")
    }
    func dateChanged() { panel?.title = "Rhythm Note · " + workspace.selectedDay; loadAppearance(); saveOpenDays() }
    func resetColors() { paperHex = ""; inkHex = "" }
    func application(_ application: NSApplication, open urls: [URL]) { for url in urls { Task { await account.handleCallback(url) } } }
    private func remember(_ mode: String) { if root == nil { UserDefaults.standard.set(mode, forKey: "notePresentation") }; saveOpenDays() }
    func expand(activate: Bool = true) {
        enabled = true
        cancelAutoFold()
        let fromCircle = bubble.isVisible
        let bubbleFrame = bubble.frame
        bubble.orderOut(nil)
        reveal()
        if fromCircle {
            let anchor = topRightAnchor(of: bubbleFrame)
            var target = panel.frame
            target = frame(anchoredTopRight: anchor, size: target.size)
            target = clampedFrame(target)
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
        } else {
            fitOnScreen()
        }
        if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        remember("note")
    }
    func minimizeToMenuBar() {
        workspace.cancelDrag()
        editing = false
        panel.orderOut(nil); bubble.orderOut(nil); remember("menu")
    }
    func collapse() {
        workspace.cancelDrag()
        editing = false
        cancelAutoFold()
        guard panel.isVisible else { return }
        let start = panel.frame
        let side = bubble.frame.width > 1 ? bubble.frame.width : 44
        let anchor = topRightAnchor(of: start)
        let target = frame(anchoredTopRight: anchor, size: NSSize(width: side, height: side))
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.setFrame(start, display: false)
        bubble.setFrame(target, display: false)
        finishCircleMove()
        if enabled { bubble.orderFrontRegardless() }
        remember("circle")
    }

    func foldUnlessPinned() {
        guard !pinned, panel.isVisible, !bubble.isVisible else { return }
        collapse()
    }

    func openDayForReview(_ day: String) {
        let owner = root ?? self
        if owner.workspace.selectedDay == day {
            owner.expand(activate: true)
            owner.workspace.tab = .todo
            return
        }
        if let existing = ([owner] + owner.children).first(where: { $0.workspace?.selectedDay == day }) {
            existing.expand(activate: true)
            existing.workspace.tab = .todo
            return
        }
        owner.newWindow(day: day)
        owner.children.last?.workspace.tab = .todo
    }
    private func placeBubble() {
        guard let bubble else { return }
        let side = bubble.frame.width > 1 ? bubble.frame.width : 44
        let anchor = topRightAnchor(of: panel.frame)
        bubble.setFrame(frame(anchoredTopRight: anchor, size: NSSize(width: side, height: side)), display: false)
        finishCircleMove()
    }
    private func topRightAnchor(of frame: NSRect) -> NSPoint { NSPoint(x: frame.maxX, y: frame.maxY) }
    private func frame(anchoredTopRight anchor: NSPoint, size: NSSize) -> NSRect {
        NSRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height)
    }
    func togglePin() {
        pinned.toggle(); UserDefaults.standard.set(pinned, forKey: "notePinned")
        panel.level = pinned ? .floating : .normal
        saveAppearance(); reveal()
        if pinned { cancelAutoFold() } else { scheduleAutoFold() }
    }
    private func reveal() {
        panel.ignoresMouseEvents = false; panel.alphaValue = 1
    }
    private func visibleScreen() -> NSRect? {
        let frame = panel.frame
        return NSScreen.screens.max { a, b in
            let aa = a.visibleFrame.intersection(frame), bb = b.visibleFrame.intersection(frame)
            return (aa.isNull ? 0 : aa.width * aa.height) < (bb.isNull ? 0 : bb.width * bb.height)
        }.flatMap { screen in screen.visibleFrame.intersects(frame) ? screen.visibleFrame : nil } ?? NSScreen.main?.visibleFrame
    }
    private func fitOnScreen() {
        guard let visible = visibleScreen() else { return }
        let frame = clampedFrame(panel.frame, visible: visible)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }
    private func clampedFrame(_ frame: NSRect, visible: NSRect? = nil) -> NSRect {
        let visible = visible ?? visibleScreen() ?? frame
        var frame = frame
        frame.size.width = min(max(frame.width, 300), visible.width - 16)
        frame.size.height = min(max(frame.height, 260), visible.height - 16)
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        return frame
    }
    var currentFrame: NSRect { panel.frame }
    func resize(from start: NSRect, translation: CGSize, edges: NoteResizeEdges) {
        reveal()
        panel.setFrame(NoteWindowGeometry.resized(start, by: translation, edges: edges, minimum: panel.minSize, maximum: panel.maxSize), display: true)
    }
    func finishResize() {
        fitOnScreen(); panel.saveFrame(usingName: frameName); reveal()
    }
    func resetSize() {
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - workspace.preferredHeight, width: 360, height: workspace.preferredHeight), display: true)
        fitOnScreen(); panel.saveFrame(usingName: frameName)
    }
    func windowDidBecomeKey(_ notification: Notification) {
        cancelAutoFold()
        refreshGlassMaterial()
    }
    func windowDidResignKey(_ notification: Notification) {
        refreshGlassMaterial()
        DispatchQueue.main.async { [weak self] in self?.refreshGlassMaterial() }
        scheduleAutoFold()
    }

    private func cancelAutoFold() {
        autoFoldWorkItem?.cancel()
        autoFoldWorkItem = nil
    }

    private func scheduleAutoFold() {
        cancelAutoFold()
        let blocked = pinned || !panel.isVisible || bubble.isVisible || editing
        // #region agent log
        AgentDebugLog.emit(hypothesisId: "C", location: "App:scheduleAutoFold", message: blocked ? "auto-fold skipped" : "auto-fold scheduled", data: [
            "pinned": String(pinned),
            "editing": String(editing),
            "panelVisible": String(panel.isVisible),
        ])
        // #endregion
        guard !pinned, panel.isVisible, !bubble.isVisible, !editing else { return }
        let work = DispatchWorkItem { [weak self] in
            // #region agent log
            AgentDebugLog.emit(hypothesisId: "C", location: "App:autoFoldFire", message: "collapse animated")
            // #endregion
            self?.collapse()
        }
        autoFoldWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
    }
    func windowDidMove(_ notification: Notification) { panel.saveFrame(usingName: frameName) }
    func windowWillStartLiveResize(_ notification: Notification) { reveal() }
    func windowDidEndLiveResize(_ notification: Notification) { finishResize() }
    func windowDidResize(_ notification: Notification) { panel.saveFrame(usingName: frameName) }
    private func fitCircleOnScreen() {
        guard let bubble else { return }
        let visible = NSScreen.screens.first { $0.visibleFrame.intersects(bubble.frame) }?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visible else { return }
        let frame = bubble.frame
        bubble.setFrameOrigin(NSPoint(x: min(max(frame.minX, visible.minX + 4), visible.maxX - frame.width - 4),
                                      y: min(max(frame.minY, visible.minY + 4), visible.maxY - frame.height - 4)))
    }
    func finishCircleMove() {
        fitCircleOnScreen()
        UserDefaults.standard.set(NSStringFromPoint(bubble.frame.origin), forKey: "noteCircleOrigin")
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = item.button {
            menu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else if panel.isVisible || bubble.isVisible { minimizeToMenuBar() } else { expand() }
    }
    private func menu() -> NSMenu {
        let menu = NSMenu()
        add(menu, "Rhythm Note", nil).isEnabled = false; menu.addItem(.separator())
        add(menu, panel.isVisible || bubble.isVisible ? "Minimize to menu bar" : "Open note", #selector(toggle))
        add(menu, "Fold into circle", #selector(circle))
        add(menu, "Keep on top", #selector(pin)).state = pinned ? .on : .off
        let notes = NSMenu()
        let owner = root ?? self
        for note in [owner] + owner.children {
            let row = add(notes, note.workspace.selectedDay, #selector(openExisting(_:))); row.representedObject = note
        }
        add(menu, "Open notes", nil).submenu = notes
        add(menu, "Open next day in new window", #selector(nextWindow))
        add(menu, NoteNotifications.enabled ? "Turn off deadline reminders" : "Turn on deadline reminders", #selector(toggleReminders))
        add(menu, "Account…", #selector(accountClicked))
        add(menu, "Reset note size", #selector(reset))
        let fonts = NSMenu()
        for (index, face) in NoteTypeface.allCases.enumerated() {
            let row = add(fonts, face.title + (face.available ? "" : " — not installed"), #selector(typefaceClicked(_:)))
            row.tag = index; row.state = typeface == face ? .on : .off; row.isEnabled = face.available
        }
        let fontMenu = add(menu, "Typeface", nil); fontMenu.submenu = fonts
        menu.addItem(.separator())
        let filters = NSMenu()
        for (index, status) in NoteStatus.visibleCases.enumerated() {
            let row = add(filters, status.title, #selector(filterClicked(_:))); row.tag = index
            row.state = workspace.statusFilter == status ? .on : .off
        }
        let filter = add(menu, "Show tasks", nil); filter.submenu = filters
        add(menu, "New category…", #selector(newCategory))
        let undoItem = add(menu, "Undo last change", #selector(undo))
        undoItem.keyEquivalent = "z"
        undoItem.keyEquivalentModifierMask = .command
        undoItem.isEnabled = workspace.canUndo
        menu.addItem(.separator())
        add(menu, enabled ? "Turn off" : "Turn on", #selector(onOff))
        let quit = add(menu, "Quit", #selector(quit)); quit.keyEquivalent = "q"
        styleMenu(menu)
        return menu
    }
    private func styleMenu(_ menu: NSMenu) {
        menu.font = typeface.nativeFont(size: 13)
        for row in menu.items {
            if let submenu = row.submenu { styleMenu(submenu) }
        }
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector?) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: ""); row.target = self; menu.addItem(row); return row
    }
    @objc private func toggle() { if panel.isVisible || bubble.isVisible { minimizeToMenuBar() } else { expand() } }
    @objc private func circle() { enabled = true; collapse() }
    @objc private func pin() { togglePin() }
    @objc private func reset() { resetSize() }
    @objc private func openExisting(_ sender: NSMenuItem) { (sender.representedObject as? AppController)?.expand() }
    @objc private func nextWindow() { newWindow(day: NoteDay.offset(workspace.selectedDay, by: 1)) }
    @objc private func accountClicked() { expand(); NotificationCenter.default.post(name: .showNoteAccount, object: self) }
    @objc private func toggleReminders() { Task { await account.setRemindersEnabled(!NoteNotifications.enabled) } }
    @objc private func typefaceClicked(_ sender: NSMenuItem) {
        guard NoteTypeface.allCases.indices.contains(sender.tag), NoteTypeface.allCases[sender.tag].available else { return }
        typeface = NoteTypeface.allCases[sender.tag]
    }
    @objc private func filterClicked(_ sender: NSMenuItem) {
        guard NoteStatus.visibleCases.indices.contains(sender.tag) else { return }
        workspace.statusFilter = NoteStatus.visibleCases[sender.tag]; expand()
    }
    @objc private func undo() { workspace.undo() }
    @objc private func newCategory() { expand(); NotificationCenter.default.post(name: .addNoteCategory, object: self) }
    @objc private func onOff() {
        enabled.toggle()
        if enabled { expand() } else { editing = false; panel.orderOut(nil); bubble.orderOut(nil); remember("off") }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { expand(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { dateTimer?.invalidate(); if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }; if let observer { NotificationCenter.default.removeObserver(observer) } }
}

struct NoteCircle: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    var body: some View {
        ZStack {
            NoteLiquidGlassOrb(theme: controller.theme, paper: Color(nsColor: controller.paper), strength: controller.circleOpacity)
            Text("\(workspace.openCount)")
                .font(controller.font(size: 12, weight: .semibold))
                .foregroundStyle(controller.ink)
                .shadow(color: controller.theme == .dark ? .black.opacity(0.35) : .white.opacity(0.4), radius: 0.5, y: controller.theme == .dark ? 0.5 : -0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle())
        .overlay { CircleInteraction(controller: controller) }
        .help(workspace.selectedDay + " · " + String(workspace.openCount) + " to do · Click to open · Drag to move")
        .environment(\.colorScheme, controller.theme.scheme)
    }
}
private struct CircleInteraction: NSViewRepresentable {
    let controller: AppController
    func makeNSView(context: Context) -> CircleInteractionView {
        let view = CircleInteractionView()
        view.controller = controller
        return view
    }
    func updateNSView(_ view: CircleInteractionView, context: Context) {
        view.controller = controller
    }
}
private final class CircleInteractionView: NSView {
    weak var controller: AppController?
    private var startPointer: NSPoint?
    private var startOrigin: NSPoint?
    private var dragged = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        startPointer = window?.convertPoint(toScreen: event.locationInWindow)
        startOrigin = window?.frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let startPointer, let startOrigin, let pointer = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        let dx = pointer.x - startPointer.x, dy = pointer.y - startPointer.y
        if hypot(dx, dy) > 3 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        let wasDrag = dragged
        startPointer = nil; startOrigin = nil; dragged = false
        if wasDrag { controller?.finishCircleMove() } else { controller?.expand() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { controller?.expand() } else { super.keyDown(with: event) }
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Open note for " + (controller?.workspace?.selectedDay ?? "today") + "; drag to move circle" }
    override func accessibilityPerformPress() -> Bool { controller?.expand(); return true }
}
@main enum Main {
    @MainActor static func main() { let app = NSApplication.shared; let delegate = AppController(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() } }
}
