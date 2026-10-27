import AppKit
import SwiftUI

enum NoteTypeface: String, CaseIterable, Identifiable {
    case system, editorial, kaiti
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System · SF Pro"
        case .editorial: return "Serif · New York"
        case .kaiti: return "Handwritten · STKaiti"
        }
    }
    static var kaitiName: String? {
        ["STKaiti", "STKaitiSC-Regular", "Kaiti SC", "STKaitiTC-Regular", "Kaiti TC"].first { NSFont(name: $0, size: 15) != nil }
    }
    var available: Bool { self != .kaiti || Self.kaitiName != nil }
    var taskFont: Font {
        switch self {
        case .system: return .system(size: 13, weight: .regular)
        case .editorial: return .system(size: 14, weight: .regular, design: .serif)
        case .kaiti:
            if let name = Self.kaitiName { return .custom(name, size: 15) }
            return .system(size: 13)
        }
    }
}

enum NoteDesign {
    static let corner: CGFloat = 24
    static let accent = Color(red: 0.39, green: 0.36, blue: 0.76)
}

struct RhythmMark: View {
    var body: some View {
        HStack(spacing: 2.5) {
            Capsule().fill(NoteDesign.accent.opacity(0.55)).frame(width: 3, height: 11)
            Capsule().fill(NoteDesign.accent).frame(width: 3, height: 19)
            Capsule().fill(Color.teal.opacity(0.75)).frame(width: 3, height: 14)
        }.frame(width: 20, height: 26).accessibilityHidden(true)
    }
}

// Use the system compositor, with the hosting view inside its documented contentView.
// No opaque paper overlay, stacked glass effects, or global-opacity transparency trick.
@MainActor func makeNoteGlass<Content: View>(_ content: Content, corner: CGFloat, frosted: Bool = false) -> NSView {
    let host = NSHostingView(rootView: content.environment(\.colorScheme, .light))
    host.autoresizingMask = [.width, .height]
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.style = frosted ? .regular : .clear
        glass.cornerRadius = corner
        glass.appearance = NSAppearance(named: .aqua)
        glass.contentView = host
        return glass
    }
    let material = NSVisualEffectView()
    material.material = .hudWindow
    material.blendingMode = .behindWindow
    material.state = .active
    material.appearance = NSAppearance(named: .aqua)
    material.wantsLayer = true
    material.layer?.cornerRadius = corner
    material.layer?.masksToBounds = true
    host.translatesAutoresizingMaskIntoConstraints = false
    material.addSubview(host)
    NSLayoutConstraint.activate([
        host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
        host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
        host.topAnchor.constraint(equalTo: material.topAnchor),
        host.bottomAnchor.constraint(equalTo: material.bottomAnchor)
    ])
    return material
}
