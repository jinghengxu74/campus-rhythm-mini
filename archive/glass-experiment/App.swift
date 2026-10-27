import AppKit
import SwiftUI
import NoteCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppController: NSObject, ObservableObject, NSApplicationDelegate, NSWindowDelegate {
    @Published var pinned = UserDefaults.standard.bool(forKey: "notePinned")
    @Published var typeface = NoteTypeface(rawValue: UserDefaults.standard.string(forKey: "noteTypeface") ?? "system") ?? .system {
        didSet { UserDefaults.standard.set(typeface.rawValue, forKey: "noteTypeface") }
    }
    @Published var frostedGlass = UserDefaults.standard.bool(forKey: "noteFrostedGlass") {
        didSet {
            UserDefaults.standard.set(frostedGlass, forKey: "noteFrostedGlass")
            if #available(macOS 26.0, *), let glass = panel?.contentView as? NSGlassEffectView { glass.style = frostedGlass ? .regular : .clear }
        }
    }
    var editing = false
    private var enabled = true
    private var resizing = false
    private var panel: FloatingPanel!
    private var bubble: NSPanel!
    private var item: NSStatusItem!
    private var workspace: Workspace!
    private var timer: Timer?
    private var hoverAt: Date?
    private var observer: NSObjectProtocol?
    private var dateTimer: Timer?
    private var revealUntil = Date.distantPast
    private var targetAlpha: CGFloat = 1
    private let frameName = "RhythmNoteWindowV2"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        workspace = Workspace()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = workspace.preferredHeight
        panel = FloatingPanel(contentRect: NSRect(x: screen.maxX - 384, y: screen.maxY - height - 18, width: 360, height: height), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.title = "Rhythm Note"; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 300, height: 260)
        panel.maxSize = NSSize(width: 760, height: 1100)
        panel.contentView = makeNoteGlass(MiniPanelView(workspace: workspace, controller: self), corner: NoteDesign.corner, frosted: frostedGlass)
        _ = panel.setFrameUsingName(frameName)
        _ = panel.setFrameAutosaveName(frameName)
        panel.delegate = self
        fitOnScreen()

        bubble = NSPanel(contentRect: NSRect(x: screen.maxX - 54, y: screen.maxY - 50, width: 32, height: 32), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble.title = "Rhythm Note circle"; bubble.isReleasedWhenClosed = false; bubble.backgroundColor = .clear; bubble.isOpaque = false
        bubble.hasShadow = true; bubble.level = .floating; bubble.hidesOnDeactivate = false
        bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        bubble.contentView = makeNoteGlass(NoteCircle(workspace: workspace, controller: self), corner: 16)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Rhythm Note")
            button.toolTip = "Rhythm Note · click to open or minimize · right-click for options"
            button.target = self; button.action = #selector(statusClicked); button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Editing tasks never changes a manually chosen window size.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.fitOnScreen(); self?.placeBubble() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.hover() } }
        dateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.objectWillChange.send() } }
        switch UserDefaults.standard.string(forKey: "notePresentation") {
        case "menu": minimizeToMenuBar()
        case "circle": collapse()
        case "off": enabled = false
        default: expand()
        }
    }
    private func remember(_ mode: String) { UserDefaults.standard.set(mode, forKey: "notePresentation") }
    func expand(activate: Bool = true) {
        enabled = true; bubble.orderOut(nil); reveal(); hoverAt = nil
        fitOnScreen()
        if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        remember("note")
    }
    func minimizeToMenuBar() {
        editing = false; hoverAt = nil
        panel.orderOut(nil); bubble.orderOut(nil); remember("menu")
    }
    func collapse() {
        editing = false; panel.orderOut(nil); placeBubble()
        if enabled { bubble.orderFrontRegardless() }; remember("circle")
    }
    private func placeBubble() {
        guard let bubble else { return }
        bubble.setFrameOrigin(NSPoint(x: panel.frame.maxX - 32, y: panel.frame.maxY - 32))
    }
    func togglePin() {
        pinned.toggle(); UserDefaults.standard.set(pinned, forKey: "notePinned")
        reveal()
    }
    private func reveal() {
        panel.ignoresMouseEvents = false; panel.alphaValue = 1; targetAlpha = 1
        revealUntil = Date().addingTimeInterval(2)
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
        var frame = panel.frame
        frame.size.width = min(max(frame.width, 300), visible.width - 16)
        frame.size.height = min(max(frame.height, 260), visible.height - 16)
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }
    var currentFrame: NSRect { panel.frame }
    func resize(from start: NSRect, translation: CGSize) {
        resizing = true; reveal()
        let width = min(max(start.width + translation.width, panel.minSize.width), panel.maxSize.width)
        let height = min(max(start.height + translation.height, panel.minSize.height), panel.maxSize.height)
        panel.setFrame(NSRect(x: start.minX, y: start.maxY - height, width: width, height: height), display: true)
    }
    func finishResize() {
        resizing = false; fitOnScreen(); panel.saveFrame(usingName: frameName); reveal()
    }
    func resetSize() {
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - workspace.preferredHeight, width: 360, height: workspace.preferredHeight), display: true)
        fitOnScreen(); panel.saveFrame(usingName: frameName)
    }
    func windowDidMove(_ notification: Notification) { revealUntil = Date().addingTimeInterval(2); panel.saveFrame(usingName: frameName) }
    func windowWillStartLiveResize(_ notification: Notification) { resizing = true; reveal() }
    func windowDidEndLiveResize(_ notification: Notification) { finishResize() }
    func windowDidResize(_ notification: Notification) { panel.saveFrame(usingName: frameName) }
    private func hover() {
        guard enabled else { return }
        let point = NSEvent.mouseLocation
        if bubble.isVisible && bubble.frame.insetBy(dx: -5, dy: -5).contains(point) {
            if hoverAt == nil { hoverAt = Date() }
            if Date().timeIntervalSince(hoverAt!) > 0.35 { expand(activate: false) }
        } else { hoverAt = nil }
        guard panel.isVisible else { return }
        let inside = panel.frame.insetBy(dx: -5, dy: -5).contains(point)
        let visible = pinned || inside || resizing || Date() < revealUntil || (editing && panel.isKeyWindow)
        let alpha: CGFloat = visible ? 1 : 0.22
        if targetAlpha != alpha {
            targetAlpha = alpha
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { panel.alphaValue = alpha }
            else { NSAnimationContext.runAnimationGroup { context in context.duration = 0.18; panel.animator().alphaValue = alpha } }
        }
        panel.ignoresMouseEvents = !visible
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
        add(menu, "Keep visible", #selector(pin)).state = pinned ? .on : .off
        add(menu, "Reset note size", #selector(reset))
        add(menu, "Frosted glass", #selector(frosted)).state = frostedGlass ? .on : .off
        let fonts = NSMenu()
        for (index, face) in NoteTypeface.allCases.enumerated() {
            let row = add(fonts, face.title + (face.available ? "" : " — not installed"), #selector(typefaceClicked(_:)))
            row.tag = index; row.state = typeface == face ? .on : .off; row.isEnabled = face.available
        }
        let fontMenu = add(menu, "Task typeface", nil); fontMenu.submenu = fonts
        menu.addItem(.separator())
        let filters = NSMenu()
        for (index, status) in NoteStatus.allCases.enumerated() {
            let row = add(filters, status.title, #selector(filterClicked(_:))); row.tag = index
            row.state = workspace.statusFilter == status ? .on : .off
        }
        let filter = add(menu, "Show tasks", nil); filter.submenu = filters
        add(menu, "New category…", #selector(newCategory))
        add(menu, "Undo last change", #selector(undo)).isEnabled = workspace.canUndo
        menu.addItem(.separator())
        add(menu, enabled ? "Turn off" : "Turn on", #selector(onOff))
        let quit = add(menu, "Quit", #selector(quit)); quit.keyEquivalent = "q"
        return menu
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector?) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: ""); row.target = self; menu.addItem(row); return row
    }
    @objc private func toggle() { if panel.isVisible || bubble.isVisible { minimizeToMenuBar() } else { expand() } }
    @objc private func circle() { enabled = true; collapse() }
    @objc private func pin() { togglePin() }
    @objc private func reset() { resetSize() }
    @objc private func frosted() { frostedGlass.toggle() }
    @objc private func typefaceClicked(_ sender: NSMenuItem) {
        guard NoteTypeface.allCases.indices.contains(sender.tag), NoteTypeface.allCases[sender.tag].available else { return }
        typeface = NoteTypeface.allCases[sender.tag]
    }
    @objc private func filterClicked(_ sender: NSMenuItem) {
        guard NoteStatus.allCases.indices.contains(sender.tag) else { return }
        workspace.statusFilter = NoteStatus.allCases[sender.tag]; expand()
    }
    @objc private func undo() { workspace.undo() }
    @objc private func newCategory() { expand(); NotificationCenter.default.post(name: .addNoteCategory, object: nil) }
    @objc private func onOff() {
        enabled.toggle()
        if enabled { expand() } else { editing = false; panel.orderOut(nil); bubble.orderOut(nil); remember("off") }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { expand(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); dateTimer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}

struct NoteCircle: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    var body: some View {
        Button { controller.expand() } label: {
            Text("\(workspace.openCount)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.primary.opacity(0.78))
                .frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(.plain).help("Open your note").accessibilityLabel("Open note, \(workspace.openCount) unfinished tasks")
    }
}
@main enum Main {
    @MainActor static func main() { let app = NSApplication.shared; let delegate = AppController(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() } }
}
