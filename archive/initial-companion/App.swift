import AppKit
import SwiftUI
import Carbon

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppController: NSObject, ObservableObject, NSApplicationDelegate, NSWindowDelegate {
    @Published var enabled = UserDefaults.standard.object(forKey: "companionEnabled") as? Bool ?? true
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinned")
    @Published var edgeReveal = UserDefaults.standard.object(forKey: "edgeReveal") as? Bool ?? true
    @Published var privateTitles = UserDefaults.standard.bool(forKey: "privateTitles") {
        didSet { UserDefaults.standard.set(privateTitles, forKey: "privateTitles") }
    }
    @Published var shortcutReady = false
    @Published var panelHeight: CGFloat = 660
    private var panel: FloatingPanel!
    private var handle: NSPanel!
    private var item: NSStatusItem!
    private var workspace: Workspace!
    private var hoverTimer: Timer?
    private var entered: Date?
    private var left: Date?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        workspace = Workspace(sample: ProcessInfo.processInfo.arguments.contains("--sample"))
        workspace.active = enabled
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panelHeight = min(660, screen.height - 32)
        panel = FloatingPanel(contentRect: NSRect(x: screen.maxX - 410, y: screen.midY - panelHeight / 2, width: 384, height: panelHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Campus Rhythm Mini"; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.delegate = self
        panel.level = pinned ? .floating : .normal
        panel.contentView = NSHostingView(rootView: MiniPanelView(workspace: workspace, controller: self).environment(\.colorScheme, .light))
        panel.contentView?.wantsLayer = true; panel.contentView?.layer?.cornerRadius = 25
        panel.contentView?.layer?.masksToBounds = true

        handle = NSPanel(contentRect: NSRect(x: screen.maxX - 20, y: screen.midY - 33, width: 16, height: 66), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        handle.title = "Campus Rhythm edge handle"; handle.isReleasedWhenClosed = false
        handle.isOpaque = false; handle.backgroundColor = .clear; handle.hasShadow = true; handle.level = .floating
        handle.hidesOnDeactivate = false; handle.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        handle.contentView = NSHostingView(rootView: Button { [weak self] in self?.showPanel(activate: true, docked: true) } label: {
            ZStack { Capsule().fill(.ultraThinMaterial); VStack(spacing: 4) { ForEach(0..<3) { _ in Circle().fill(Color(red: 0.48, green: 0.36, blue: 0.68).opacity(0.7)).frame(width: 3, height: 3) } } }.frame(width: 12, height: 58)
        }.buttonStyle(.plain).help("Reveal Campus Rhythm").accessibilityLabel("Reveal Campus Rhythm").environment(\.colorScheme, .light))

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                NSColor.labelColor.setFill()
                for (x, h) in [(3.0, 11.0), (8.0, 16.0), (13.0, 9.0)] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: (18 - h) / 2, width: 3, height: h), xRadius: 1.5, yRadius: 1.5).fill()
                }
                return true
            }
            image.isTemplate = true; button.image = image; button.toolTip = "Campus Rhythm · click to show/hide, right-click for options"
            button.target = self; button.action = #selector(statusClicked); button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        registerShortcut()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkHover() } }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.fitOnScreen() }
        }
        if enabled { showPanel(activate: true) }
    }

    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "companionEnabled")
        workspace.active = value
        if value { showPanel(activate: true) } else { panel.orderOut(nil); handle.orderOut(nil) }
        entered = nil; left = nil; item.button?.appearsDisabled = !value
    }
    func setPinned(_ value: Bool) {
        pinned = value; UserDefaults.standard.set(value, forKey: "pinned")
        panel.level = value ? .floating : .normal
        if value && enabled { panel.orderFrontRegardless() }
    }
    func togglePin() { setPinned(!pinned) }
    func setEdgeReveal(_ value: Bool) {
        edgeReveal = value; UserDefaults.standard.set(value, forKey: "edgeReveal")
        if value && enabled && !panel.isVisible { positionHandle(); handle.orderFrontRegardless() } else { handle.orderOut(nil) }
    }
    func showPanel(activate: Bool, docked: Bool = false) {
        if !enabled { enabled = true; workspace.active = true; UserDefaults.standard.set(true, forKey: "companionEnabled"); item.button?.appearsDisabled = false }
        entered = nil; left = nil
        if docked, let frame = handle.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 22, y: min(max(frame.minY + 16, handle.frame.midY - panelHeight / 2), frame.maxY - panelHeight - 16)))
        }
        fitOnScreen(); handle.orderOut(nil)
        if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
    }
    func hidePanel() {
        panel.orderOut(nil); entered = nil; left = nil
        if enabled && edgeReveal { positionHandle(); handle.orderFrontRegardless() }
    }
    private func toggleVisibility() { if enabled && panel.isVisible { hidePanel() } else { showPanel(activate: true) } }
    private func positionHandle() {
        let frame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        handle.setFrameOrigin(NSPoint(x: frame.maxX - 19, y: frame.midY - 33))
    }
    private func fitOnScreen() {
        guard let frame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        panelHeight = min(660, frame.height - 32)
        let x = min(max(frame.minX + 12, panel.frame.minX), frame.maxX - 396)
        let y = min(max(frame.minY + 12, panel.frame.minY), frame.maxY - panelHeight - 12)
        panel.setFrame(NSRect(x: x, y: y, width: 384, height: panelHeight), display: true)
        positionHandle()
    }
    private func checkHover() {
        guard enabled, edgeReveal else { return }
        let point = NSEvent.mouseLocation
        if handle.isVisible && handle.frame.insetBy(dx: -6, dy: -5).contains(point) {
            if entered == nil { entered = Date() }
            if Date().timeIntervalSince(entered!) > 0.30 { showPanel(activate: false, docked: true) }
        } else { entered = nil }
        if panel.isVisible && !pinned && !panel.isKeyWindow && !panel.frame.insetBy(dx: -12, dy: -12).contains(point) {
            if left == nil { left = Date() }
            if Date().timeIntervalSince(left!) > 1.1 { hidePanel() }
        } else { left = nil }
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = item.button {
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        }
        else { toggleVisibility() }
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Campus Rhythm Mini", action: nil, keyEquivalent: ""); menu.addItem(title)
        menu.addItem(.separator())
        add(menu, enabled && panel.isVisible ? "Hide panel" : "Show panel", #selector(menuToggle))
        let pin = add(menu, "Keep on top", #selector(menuPin)); pin.state = pinned ? .on : .off
        let edge = add(menu, "Reveal from right edge", #selector(menuEdge)); edge.state = edgeReveal ? .on : .off
        add(menu, "Dock panel to right edge", #selector(menuDock))
        menu.addItem(.separator())
        add(menu, "Open Campus Rhythm", #selector(menuPlanner))
        let enabledItem = add(menu, "Companion enabled", #selector(menuEnabled)); enabledItem.state = enabled ? .on : .off
        menu.addItem(NSMenuItem(title: shortcutReady ? "Shortcut · ⌃⌥R" : "Shortcut unavailable", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let quit = add(menu, "Quit Campus Rhythm Mini", #selector(menuQuit)); quit.keyEquivalent = "q"
        return menu
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: ""); value.target = self; menu.addItem(value); return value
    }
    @objc private func menuToggle() { toggleVisibility() }
    @objc private func menuPin() { togglePin() }
    @objc private func menuEdge() { setEdgeReveal(!edgeReveal) }
    @objc private func menuEnabled() { setEnabled(!enabled) }
    @objc private func menuDock() { showPanel(activate: true, docked: true) }
    @objc private func menuPlanner() { NSWorkspace.shared.open(URL(string: "https://campus-rhythm-one.vercel.app/today")!) }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    private func registerShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<AppController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in controller.toggleVisibility() }
            return noErr
        }, 1, &eventType, pointer, &handler)
        guard result == noErr else { return }
        let id = EventHotKeyID(signature: OSType(0x43524D49), id: 1)
        shortcutReady = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setEnabled(true); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        hoverTimer?.invalidate(); if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

@main enum Main {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppController(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
