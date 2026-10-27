import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteDrag: Equatable {
    enum Kind: Equatable { case category, task }
    let kind: Kind
    let id: UUID
}
enum NoteDropTarget: Equatable {
    case category(UUID, after: Bool)
    case task(category: UUID, anchor: UUID?, after: Bool)
    case completed(dayID: String, anchor: UUID?, after: Bool)
}
enum NoteDropZone: Equatable {
    case header(UUID), row(category: UUID, task: UUID), tail(UUID)
    case completedHeader(String), completedRow(dayID: String, task: UUID), completedTail(String), completedChart(String)
}
private let orderType = UTType(exportedAs: "com.campusrhythm.note-order")

@MainActor extension Workspace {
    func dragProvider(_ source: NoteDrag) -> NSItemProvider {
        dragging = source; dropTarget = nil
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: orderType.identifier, visibility: .ownProcess) { complete in
            complete(Data(source.id.uuidString.utf8), nil); return nil
        }
        return provider
    }
    func cancelDrag() { dragging = nil; dropTarget = nil }
    func applyDrop(_ target: NoteDropTarget) -> Bool {
        guard let source = dragging else { return false }
        switch (source.kind, target) {
        case (.category, .category(let anchor, let after)):
            reorderCategory(source.id, relativeTo: anchor, after: after)
        case (.task, .task(let category, let anchor, let after)):
            reorderItem(source.id, to: category, relativeTo: anchor, after: after)
        case (.task, .completed(let dayID, let anchor, let after)):
            guard isCompletedTask(source.id) else { cancelDrag(); return false }
            reorderCompleted(source.id, dayID: dayID, relativeTo: anchor, after: after)
        default: cancelDrag(); return false
        }
        cancelDrag(); return true
    }
}

private struct NoteOrderDelegate: DropDelegate {
    let workspace: Workspace
    let zone: NoteDropZone
    func validateDrop(info: DropInfo) -> Bool { destination(info) != nil && info.hasItemsConforming(to: [orderType.identifier]) }
    func dropEntered(info: DropInfo) { workspace.dropTarget = destination(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        workspace.dropTarget = destination(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { if workspace.dropTarget == destination(info) { workspace.dropTarget = nil } }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let target = destination(info) else { return false }
        return workspace.applyDrop(target)
    }
    private func destination(_ info: DropInfo) -> NoteDropTarget? {
        guard let source = workspace.dragging else { return nil }
        switch (source.kind, zone) {
        case (.category, .header(let category)):
            guard source.id != category else { return nil }
            return .category(category, after: info.location.y > 11)
        case (.task, .header(let category)):
            guard workspace.isCompletedTask(source.id) == false else { return nil }
            guard let group = workspace.categories.first(where: { $0.id == category }) else { return nil }
            return .task(category: category, anchor: workspace.items(in: group).first?.id, after: false)
        case (.task, .row(let category, let task)):
            guard workspace.isCompletedTask(source.id) == false else { return nil }
            guard source.id != task else { return nil }
            return .task(category: category, anchor: task, after: info.location.y > 15)
        case (.task, .tail(let category)):
            guard workspace.isCompletedTask(source.id) == false else { return nil }
            return .task(category: category, anchor: nil, after: false)
        case (.task, .completedHeader(let dayID)):
            guard workspace.isCompletedTask(source.id) else { return nil }
            return .completed(dayID: dayID, anchor: workspace.firstCompletedEntry(in: dayID), after: info.location.y > 11)
        case (.task, .completedRow(let dayID, let task)):
            guard workspace.isCompletedTask(source.id) else { return nil }
            guard source.id != task else { return nil }
            return .completed(dayID: dayID, anchor: task, after: info.location.y > 15)
        case (.task, .completedTail(let dayID)):
            guard workspace.isCompletedTask(source.id) else { return nil }
            return .completed(dayID: dayID, anchor: nil, after: false)
        case (.task, .completedChart(let dayID)):
            guard workspace.isCompletedTask(source.id) else { return nil }
            return .completed(dayID: dayID, anchor: nil, after: false)
        default: return nil
        }
    }
}

struct NoteOrderZone: ViewModifier {
    @ObservedObject var workspace: Workspace
    let zone: NoteDropZone
    private var insertion: (active: Bool, after: Bool) {
        switch (workspace.dropTarget, zone) {
        case (.category(let id, let after), .header(let target)) where id == target: return (true, after)
        case (.task(let category, let anchor, let after), .row(let targetCategory, let task)) where category == targetCategory && anchor == task: return (true, after)
        case (.task(let category, nil, _), .tail(let target)) where category == target: return (true, false)
        case (.completed(let dayID, let anchor, let after), .completedRow(let targetDay, let task)) where dayID == targetDay && anchor == task: return (true, after)
        case (.completed(let dayID, nil, _), .completedTail(let target)) where dayID == target: return (true, false)
        case (.completed(let dayID, _, let after), .completedHeader(let target)) where dayID == target: return (true, after)
        default: return (false, false)
        }
    }
    private var chartDropActive: Bool {
        switch (workspace.dropTarget, zone) {
        case (.completed(let dayID, nil, false), .completedChart(let target)) where dayID == target: return true
        default: return false
        }
    }
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .onDrop(of: [orderType.identifier], delegate: NoteOrderDelegate(workspace: workspace, zone: zone))
            .overlay {
                if chartDropActive {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NoteDesign.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NoteDesign.accent.opacity(0.7), lineWidth: 1.5))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: insertion.after ? .bottom : .top) {
                if insertion.active { Rectangle().fill(NoteDesign.accent.opacity(0.65)).frame(height: 1.5).allowsHitTesting(false) }
            }
    }
}

struct NoteDragHandle: View {
    @ObservedObject var workspace: Workspace
    let source: NoteDrag
    let name: String
    var body: some View {
        Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.45))
            .frame(width: 18, height: 22).contentShape(Rectangle())
            .onDrag { workspace.dragProvider(source) }
            .help(workspace.isCompletedTask(source.id) ? "Drag onto a chart day or between lists to change completion date" : "Drag to reorder " + name)
            .accessibilityLabel(workspace.isCompletedTask(source.id) ? "Move completion date for " + name : "Drag to reorder " + name)
    }
}

struct NoteStatusDropZone: ViewModifier {
    @ObservedObject var workspace: Workspace
    let tab: NoteTab
    @State private var targeted = false
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .onDrop(of: [orderType.identifier], isTargeted: $targeted) { _ in
                guard let source = workspace.dragging, source.kind == .task, tab == .pending || tab == .todo else { return false }
                workspace.setStatus(source.id, tab == .pending ? .pending : .todo)
                workspace.cancelDrag(); workspace.tab = tab
                return true
            }
            .overlay { if targeted && workspace.dragging?.kind == .task && (tab == .pending || tab == .todo) { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.65), lineWidth: 2).allowsHitTesting(false) } }
    }
}
