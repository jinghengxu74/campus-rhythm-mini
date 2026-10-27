import AppKit
import SwiftUI
import NoteCore

enum NoteTypeface: String, CaseIterable, Identifiable {
    case monospaced, system, editorial, kaiti
    var id: String { rawValue }
    var title: String {
        switch self {
        case .monospaced: return "Original · Monospaced"
        case .system: return "System · SF Pro"
        case .editorial: return "Serif · New York"
        case .kaiti: return "Handwritten · STKaiti"
        }
    }
    static var kaitiName: String? {
        ["STKaiti", "STKaitiSC-Regular", "Kaiti SC", "STKaitiTC-Regular", "Kaiti TC"].first { NSFont(name: $0, size: 15) != nil }
    }
    var available: Bool { self != .kaiti || Self.kaitiName != nil }
    // Keep the same hierarchy while applying the selected family to every text role.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        case .system: return .system(size: size + 1, weight: weight)
        case .editorial: return .system(size: size + 2, weight: weight, design: .serif)
        case .kaiti:
            if let name = Self.kaitiName { return .custom(name, size: size + 3).weight(weight) }
            return .system(size: size + 1, weight: weight)
        }
    }
    var taskFont: Font { font(size: 12) }
    func nativeFont(size: CGFloat) -> NSFont {
        switch self {
        case .monospaced: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .system: return .systemFont(ofSize: size + 1)
        case .editorial:
            let base = NSFont.systemFont(ofSize: size + 2)
            return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size + 2) } ?? base
        case .kaiti:
            return Self.kaitiName.flatMap { NSFont(name: $0, size: size + 3) } ?? .systemFont(ofSize: size + 1)
        }
    }
}

enum NoteGlassFinish: String, CaseIterable, Identifiable {
    case glass, frosted
    var id: String { rawValue }
    var title: String { self == .glass ? "Glass" : "Frosted" }
}
enum NoteTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme { self == .dark ? .dark : .light }
    var appearance: NSAppearance? { NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
    var paper: NSColor { self == .dark ? NSColor(srgbRed: 0.012, green: 0.012, blue: 0.014, alpha: 1) : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.985, alpha: 1) }
    var ink: Color { self == .dark ? Color(white: 0.95) : Color(white: 0.13) }
}
enum NoteEdgeStyle: String, CaseIterable, Identifiable {
    case rounded, compact, minimal
    var id: String { rawValue }
    var title: String { switch self { case .rounded: return "Rounded Glass"; case .compact: return "Compact"; case .minimal: return "Minimal" } }
    var corner: CGFloat { switch self { case .rounded: return 24; case .compact: return 13; case .minimal: return 7 } }
}
enum NoteDesign {
    static let accent = Color.primary
    static let highlights: [(String, String)] = [("Yellow", "#FFD966"), ("Mint", "#7DDCB6"), ("Lavender", "#B9A7F5"), ("Rose", "#F3A7BD"), ("Blue", "#8DC6F4")]
    static let inks: [(String, String)] = [("Graphite", "#25282D"), ("White", "#FFFFFF"), ("Blue", "#4E91E5"), ("Purple", "#A17BE8"), ("Rose", "#E57596"), ("Green", "#42A98D")]
}

struct NoteLiquidSegmentBar: View {
    let tabs: [NoteTab]
    @Binding var selection: NoteTab
    let font: (CGFloat, Font.Weight) -> Font
    let ink: Color
    var reduceMotion: Bool
    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button { withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) { selection = tab } } label: {
                    Text(tab.title)
                        .font(font(10, selection == tab ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(ink.opacity(selection == tab ? 1 : 0.68))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
    }
}
extension NSColor {
    convenience init?(noteHex: String) {
        guard NoteCore.NoteDay.isColor(noteHex), let n = UInt32(noteHex.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    var noteHex: String {
        let c = usingColorSpace(.deviceRGB) ?? self
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
extension Color {
    init(noteHex: String) { self.init(nsColor: NSColor(noteHex: noteHex) ?? .labelColor) }
    var noteHex: String { NSColor(self).noteHex }
}

@MainActor func makeNoteSurface<Content: View>(_ content: Content, circle: Bool = false) -> NoteSurfaceView {
    let surface = NoteSurfaceView(circle: circle)
    let host = FirstClickHostingView(rootView: content)
    host.translatesAutoresizingMaskIntoConstraints = false
    surface.content.addSubview(host)
    NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: surface.content.leadingAnchor), host.trailingAnchor.constraint(equalTo: surface.content.trailingAnchor), host.topAnchor.constraint(equalTo: surface.content.topAnchor), host.bottomAnchor.constraint(equalTo: surface.content.bottomAnchor)])
    return surface
}
/// Keeps Control Center–style vibrancy even when the note window is not key.
private final class NoteVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyActiveGlass()
    }
    func applyActiveGlass() {
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
    }
    override func layout() {
        super.layout()
        if state != .active { state = .active }
    }
}
final class NoteSurfaceView: NSView {
    let content = NSView()
    private let tint = PassthroughView()
    private let rim = NSView()
    private var effect: NSView?
    private let circle: Bool
    override var isOpaque: Bool { circle ? false : super.isOpaque }
    init(circle: Bool) {
        self.circle = circle; super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        content.wantsLayer = true; content.layer?.masksToBounds = true
        tint.wantsLayer = true; tint.autoresizingMask = [.width, .height]
        rim.wantsLayer = true; rim.autoresizingMask = [.width, .height]
        addSubview(rim)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        guard circle, bounds.width > 1, bounds.height > 1 else { return }
        let side = min(bounds.width, bounds.height)
        effect?.frame = bounds
        content.frame = effect?.bounds ?? bounds
        layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            layer?.mask = nil
            glass.layer?.mask = nil
            glass.cornerRadius = side / 2
            glass.style = .clear
        } else if let material = effect as? NSVisualEffectView {
            material.material = .hudWindow
            material.maskImage = Self.circleImage(side)
            material.state = .active
        }
    }
    private static func circleImage(_ side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: side, height: side)).fill()
        image.unlockFocus()
        return image
    }
    func configure(theme: NoteTheme, edge: NoteEdgeStyle, paper: NSColor, opacity: Double, finish: NoteGlassFinish) {
        appearance = theme.appearance
        let corner: CGFloat = circle ? min(bounds.width, bounds.height) / 2 : edge.corner
        content.layer?.cornerRadius = corner
        rim.isHidden = true
        if circle {
            tint.isHidden = true
            tint.layer?.backgroundColor = NSColor.clear.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            tint.isHidden = false
            tint.removeFromSuperview()
            content.addSubview(tint, positioned: .below, relativeTo: content.subviews.first)
            tint.frame = content.bounds
            tint.autoresizingMask = [.width, .height]
            tint.layer?.backgroundColor = (theme == .dark ? NSColor.black : NSColor.white).cgColor
        }
        if #available(macOS 26.0, *) {
            if effect == nil || effect is NoteVisualEffectView {
                content.removeFromSuperview(); effect?.removeFromSuperview()
                let glass = NSGlassEffectView(frame: bounds)
                content.frame = glass.bounds; content.autoresizingMask = [.width, .height]
                glass.contentView = content; effect = glass
                effect!.frame = bounds; effect!.autoresizingMask = [.width, .height]
                addSubview(effect!, positioned: .below, relativeTo: rim)
            }
            if let glass = effect as? NSGlassEffectView {
                glass.style = (circle || finish == .glass) ? .clear : .regular
                glass.cornerRadius = max(corner, circle ? min(bounds.width, bounds.height) / 2 : corner)
            }
        } else if effect == nil {
            content.removeFromSuperview()
            let material = NoteVisualEffectView(frame: bounds)
            material.material = circle ? .hudWindow : Self.material(theme: theme, finish: finish)
            material.applyActiveGlass(); material.wantsLayer = true
            material.layer?.cornerRadius = corner; material.layer?.masksToBounds = true
            content.frame = material.bounds; content.autoresizingMask = [.width, .height]
            material.addSubview(content); effect = material
            effect!.frame = bounds; effect!.autoresizingMask = [.width, .height]
            addSubview(effect!, positioned: .below, relativeTo: rim)
        }
        effect?.layer?.cornerRadius = corner
        (effect as? NoteVisualEffectView)?.applyActiveGlass()
        shadow = nil
        needsLayout = true
    }
    private static func material(theme: NoteTheme, finish: NoteGlassFinish) -> NSVisualEffectView.Material {
        if theme == .dark { return finish == .glass ? .hudWindow : .underWindowBackground }
        return finish == .glass ? .popover : .sheet
    }
    func refreshMaterial() {
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView { glass.style = .clear }
        (effect as? NoteVisualEffectView)?.applyActiveGlass()
    }
}
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private extension NSView {
    func removeFromSubviews() { subviews.forEach { $0.removeFromSuperview() } }
}
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
