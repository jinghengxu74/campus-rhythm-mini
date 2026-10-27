import AppKit
import SwiftUI
import NoteCore

struct MiniPanelView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    @State private var input = ""
    @State private var newCategory = false
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var hoveredCategory: UUID?
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dateLabel: String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE, d MMM"; return f.string(from: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            statusTabs
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(workspace.categories) { categoryView($0) }
                    if workspace.filteredCount == 0 {
                        Text(emptyMessage).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
                    }
                    if !workspace.error.isEmpty {
                        Text(workspace.error).font(.system(size: 11)).foregroundStyle(.red).padding(.top, 5)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 16)
            }
            composer
        }
        .buttonStyle(.plain).foregroundStyle(.primary).tint(NoteDesign.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: NoteDesign.corner, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            NoteResizeArea(controller: controller).frame(width: 22, height: 22).padding(3)
                .help("Drag to resize").accessibilityLabel("Resize note")
        }
        .onChange(of: inputFocused) { controller.editing = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .captureNoteTask)) { _ in newCategory = false; inputFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .addNoteCategory)) { _ in newCategory = true; input = ""; inputFocused = true }
        .onExitCommand { if newCategory || !input.isEmpty { newCategory = false; input = ""; inputFocused = false } else { controller.minimizeToMenuBar() } }
    }

    private var header: some View {
        HStack(spacing: 9) {
            RhythmMark()
            NoteDragArea().overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Rhythm").font(.system(size: 12, weight: .semibold)).tracking(-0.1)
                    Text(dateLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                }.allowsHitTesting(false)
            }.frame(maxWidth: .infinity).frame(height: 32).help("Drag here to move the note")
            Menu {
                Button("Minimize to menu bar") { controller.minimizeToMenuBar() }
                Button("Fold into circle") { controller.collapse() }
                Divider()
                Menu("Task typeface") {
                    ForEach(NoteTypeface.allCases) { face in
                        Button { controller.typeface = face } label: {
                            if face == controller.typeface { Label(face.title, systemImage: "checkmark") }
                            else { Text(face.title + (face.available ? "" : " — not installed")) }
                        }.disabled(!face.available)
                    }
                }
                Toggle("Frosted glass", isOn: $controller.frostedGlass)
                Button("Reset note size") { controller.resetSize() }
            } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).frame(width: 16, height: 26) }
                .menuStyle(.borderlessButton).fixedSize().help("Note options").accessibilityLabel("Note options")
            Button { controller.minimizeToMenuBar() } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .medium)).frame(width: 22, height: 26)
            }.foregroundStyle(.secondary).help("Minimize to menu bar").accessibilityLabel("Minimize to menu bar")
            Button { controller.togglePin() } label: {
                Image(systemName: controller.pinned ? "pin.fill" : "pin").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(controller.pinned ? NoteDesign.accent : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(controller.pinned ? NoteDesign.accent.opacity(0.13) : Color.clear, in: Circle())
            }.help(controller.pinned ? "Unpin · fade when not in use" : "Pin · keep visible")
                .accessibilityLabel(controller.pinned ? "Unpin note" : "Pin note")
        }.padding(.leading, 18).padding(.trailing, 13).padding(.top, 12).padding(.bottom, 10)
    }

    private var statusTabs: some View {
        HStack(spacing: 2) {
            ForEach(NoteStatus.allCases) { status in
                Button { workspace.statusFilter = status } label: {
                    Text(status.title).font(.system(size: 10.5, weight: workspace.statusFilter == status ? .semibold : .medium))
                        .foregroundStyle(workspace.statusFilter == status ? NoteDesign.accent : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(workspace.statusFilter == status ? NoteDesign.accent.opacity(0.12) : Color.clear, in: Capsule())
                }.accessibilityLabel("Show " + status.title).accessibilityAddTraits(workspace.statusFilter == status ? .isSelected : [])
            }
        }.padding(.horizontal, 16).padding(.bottom, 10)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: workspace.statusFilter)
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5).padding(.horizontal, 20) }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Image(systemName: newCategory ? "folder.badge.plus" : "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            TextField(newCategory ? "Name a category…" : "Add a task…", text: $input).textFieldStyle(.plain)
                .font(.system(size: 12)).focused($inputFocused).onSubmit(submit)
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
                } label: { Text(workspace.selectedName).font(.system(size: 10, weight: .medium)).lineLimit(1).frame(maxWidth: 64) }
                    .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary).help("Choose or create a category")
            }
            Button(action: submit) {
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold)).frame(width: 23, height: 23)
                    .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : .white)
                    .background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary.opacity(0.045) : NoteDesign.accent, in: Circle())
            }.help(newCategory ? "Add category" : "Add task").accessibilityLabel(newCategory ? "Add category" : "Add task")
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .background(.primary.opacity(0.035), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(inputFocused ? 0.14 : 0.065), lineWidth: 0.5))
            .padding(.horizontal, 15).padding(.bottom, 15).padding(.top, 5)
    }

    private func categoryView(_ group: NoteCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { workspace.toggleCategory(group.id) } label: {
                    Image(systemName: group.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 10, height: 22)
                }.accessibilityLabel((group.collapsed ? "Expand " : "Collapse ") + group.name)
                if renaming == group.id {
                    TextField("Category name", text: $renameText).textFieldStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .onSubmit { workspace.renameCategory(group.id, renameText); renaming = nil; controller.editing = false }
                        .onAppear { controller.editing = true }
                } else {
                    Text(group.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).onTapGesture { workspace.toggleCategory(group.id) }
                }
                Text("\(workspace.items(in: group).count)").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
                Spacer()
                Button { workspace.selectedCategory = group.id; newCategory = false; inputFocused = true } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(width: 22, height: 22)
                }.opacity(hoveredCategory == group.id ? 1 : 0.45).help("Add to " + group.name).accessibilityLabel("Add to " + group.name)
            }.contextMenu {
                Button("Rename category…") { renameText = group.name; renaming = group.id }
                Button("Add a task") { workspace.selectedCategory = group.id; inputFocused = true }
                if group.items.isEmpty && workspace.categories.count > 1 { Divider(); Button("Remove empty category") { workspace.removeCategory(group.id) } }
            }
            if !group.collapsed {
                ForEach(workspace.items(in: group)) { item in NoteRow(item: item, workspace: workspace, controller: controller).padding(.leading, 7) }
            }
        }.onHover { hoveredCategory = $0 ? group.id : nil }
    }
    private var emptyMessage: String {
        switch workspace.statusFilter {
        case .todo: return "A little space for what’s next."
        case .pending: return "Nothing waiting."
        case .completed: return "Completed tasks will appear here."
        case .cancelled: return "Cancelled tasks will appear here."
        }
    }
    private func submit() {
        if newCategory { if workspace.addCategory(input) { input = ""; newCategory = false } }
        else if workspace.add(input) { input = "" }
        inputFocused = true
    }
}

private struct NoteRow: View {
    let item: NoteItem
    @ObservedObject var workspace: Workspace
    @ObservedObject var controller: AppController
    @State private var editing = false
    @State private var value = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button { workspace.toggle(item.id) } label: {
                ZStack {
                    Circle().strokeBorder(.primary.opacity(item.done ? 0 : 0.28), lineWidth: 1)
                    if item.done { Circle().fill(NoteDesign.accent); Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                    if item.status == .cancelled { Image(systemName: "minus").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) }
                }.frame(width: 16, height: 16).frame(width: 22, height: 22)
            }.accessibilityLabel((item.done ? "Reopen " : "Complete ") + item.title)
            if editing {
                TextField("Task", text: $value, axis: .vertical).textFieldStyle(.plain).font(controller.typeface.taskFont).focused($focused)
                    .onSubmit { finishEdit() }.onChange(of: focused) { if !$0 { finishEdit() } }
                    .onExitCommand { editing = false; controller.editing = false }
            } else {
                Text(item.title).font(controller.typeface.taskFont).lineSpacing(3)
                    .foregroundStyle(.primary.opacity(item.done || item.status == .cancelled ? 0.46 : 0.92))
                    .strikethrough(item.done || item.status == .cancelled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                    .onTapGesture(count: 2) { edit() }
            }
        }.padding(.vertical, 4).contextMenu {
            Button("Edit task…") { edit() }
            Menu("Move to") { ForEach(workspace.categories) { category in Button(category.name) { workspace.move(item.id, to: category.id) } } }
            Divider()
            ForEach(NoteStatus.allCases) { status in if status != item.status { Button("Move to " + status.title) { workspace.setStatus(item.id, status) } } }
            Divider(); Button("Delete task") { workspace.delete(item.id) }
        }
    }
    private func edit() { value = item.title; editing = true; focused = true; controller.editing = true }
    private func finishEdit() { workspace.renameItem(item.id, value); editing = false; controller.editing = false }
}

private final class DragSurface: NSView {
    private var startPointer: NSPoint?
    private var startOrigin: NSPoint?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { startPointer = window?.convertPoint(toScreen: event.locationInWindow); startOrigin = window?.frame.origin }
    override func mouseDragged(with event: NSEvent) {
        guard let startPointer, let startOrigin else { return }
        guard let pointer = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + pointer.x - startPointer.x, y: startOrigin.y + pointer.y - startPointer.y))
    }
    override func mouseUp(with event: NSEvent) { startPointer = nil; startOrigin = nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
private struct NoteDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragSurface() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
private final class ResizeSurface: NSView {
    var controller: AppController?
    private var startPointer: NSPoint?
    private var startFrame: NSRect?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { startPointer = window?.convertPoint(toScreen: event.locationInWindow); startFrame = window?.frame }
    override func mouseDragged(with event: NSEvent) {
        guard let startPointer, let startFrame else { return }
        guard let pointer = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        controller?.resize(from: startFrame, translation: CGSize(width: pointer.x - startPointer.x, height: startPointer.y - pointer.y))
    }
    override func mouseUp(with event: NSEvent) { startPointer = nil; startFrame = nil; controller?.finishResize() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.3).setStroke()
        let path = NSBezierPath(); path.lineWidth = 0.8
        for offset in [CGFloat(5), 9, 13] {
            path.move(to: NSPoint(x: offset, y: 5))
            path.line(to: NSPoint(x: 17, y: 22 - offset))
        }
        path.stroke()
    }
}
private struct NoteResizeArea: NSViewRepresentable {
    let controller: AppController
    func makeNSView(context: Context) -> NSView { let view = ResizeSurface(); view.controller = controller; return view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension Notification.Name {
    static let captureNoteTask = Notification.Name("mini.captureNoteTask")
    static let addNoteCategory = Notification.Name("mini.addNoteCategory")
}
