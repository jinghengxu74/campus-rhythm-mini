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

/// Maps the appearance slider (left = see-through, right = solid paper).
enum NotePaperOpacity {
    static let sliderMin = 0.15
    static let solidThreshold = 0.78

    static func backdrop(finish: NoteGlassFinish, slider: Double) -> CGFloat {
        let t = CGFloat(min(1, max(sliderMin, slider)))
        if t >= CGFloat(solidThreshold) { return 1 }
        let floor: CGFloat = finish == .glass ? 0.04 : 0.1
        let span = CGFloat(solidThreshold - sliderMin)
        return floor + (t - CGFloat(sliderMin)) / span * (1 - floor)
    }

    static func isSolid(slider: Double) -> Bool { slider >= solidThreshold }
}

struct NoteDeskSkin: Identifiable {
    let id: String
    let title: String
    let theme: NoteTheme
    let paper: String
    let ink: String
    let finish: NoteGlassFinish
    /// Apple-inspired paper + ink pairs (Midnight / Starlight first, then popular hues).
    static let presets: [NoteDeskSkin] = [
        NoteDeskSkin(id: "midnight", title: "Midnight", theme: .dark, paper: "#0C0D10", ink: "#F5F5F7", finish: .glass),
        NoteDeskSkin(id: "starlight", title: "Starlight", theme: .light, paper: "#FAFAFC", ink: "#1D1D1F", finish: .glass),
        NoteDeskSkin(id: "space-gray", title: "Space Gray", theme: .dark, paper: "#3A3A3C", ink: "#F2F2F7", finish: .frosted),
        NoteDeskSkin(id: "silver", title: "Silver", theme: .light, paper: "#E8E8ED", ink: "#2C2C2E", finish: .frosted),
        NoteDeskSkin(id: "ultramarine", title: "Ultramarine", theme: .dark, paper: "#1A2847", ink: "#FFFFFF", finish: .glass),
        NoteDeskSkin(id: "sky-blue", title: "Sky Blue", theme: .light, paper: "#EEF4FF", ink: "#184A9A", finish: .glass),
        NoteDeskSkin(id: "pacific-blue", title: "Pacific Blue", theme: .dark, paper: "#1F3A52", ink: "#D6E9F5", finish: .frosted),
        NoteDeskSkin(id: "alpine-green", title: "Alpine Green", theme: .dark, paper: "#1E2E28", ink: "#D8E8DF", finish: .glass),
        NoteDeskSkin(id: "sage", title: "Sage", theme: .light, paper: "#E4EDE6", ink: "#1F4D3A", finish: .glass),
        NoteDeskSkin(id: "product-red", title: "(PRODUCT) RED", theme: .dark, paper: "#5C1418", ink: "#FFF5F5", finish: .glass),
        NoteDeskSkin(id: "rose", title: "Rose", theme: .light, paper: "#FCE8EC", ink: "#8B2942", finish: .frosted),
        NoteDeskSkin(id: "lavender", title: "Lavender", theme: .light, paper: "#EDE7F6", ink: "#4A3D6B", finish: .frosted),
        NoteDeskSkin(id: "deep-purple", title: "Deep Purple", theme: .dark, paper: "#2A1F3D", ink: "#E8DDF8", finish: .glass),
        NoteDeskSkin(id: "graphite", title: "Graphite", theme: .dark, paper: "#1C1C1E", ink: "#AEAEB2", finish: .frosted),
    ]
}

/// Fixed-size specular rim for the folded circle — no hover scale; follows light/dark theme.
struct NoteLiquidGlassOrb: View {
    var theme: NoteTheme
    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            let dark = theme == .dark
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: dark
                                ? [Color.white.opacity(0.2), Color(white: 0.12).opacity(0.85), Color.black.opacity(0.72)]
                                : [Color.white.opacity(0.55), Color.white.opacity(0.22), Color.white.opacity(0.05)],
                            center: UnitPoint(x: 0.38, y: 0.22),
                            startRadius: 0,
                            endRadius: d * 0.62
                        )
                    )
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: dark
                                ? [Color.white.opacity(0.55), Color.white.opacity(0.12), Color.black.opacity(0.35), Color.white.opacity(0.22)]
                                : [Color.white.opacity(0.95), Color.white.opacity(0.35), Color.white.opacity(0.08), Color.white.opacity(0.42)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(dark ? 0.35 : 0.72), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: d * 0.52, height: d * 0.2)
                    .offset(y: -d * 0.2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
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
    private var glassFinish: NoteGlassFinish = .glass
    private var panelOpacity: Double = 0.65
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
            material.material = .popover
            material.maskImage = Self.circleImage(side)
            material.state = .active
            material.isEmphasized = true
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
        glassFinish = finish
        panelOpacity = opacity
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
            tint.layer?.backgroundColor = Self.tintColor(paper: paper, theme: theme, opacity: opacity, finish: finish).cgColor
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
                let solid = !circle && NotePaperOpacity.isSolid(slider: opacity)
                if solid {
                    glass.style = .regular
                } else {
                    glass.style = (circle || finish == .glass) ? .clear : .regular
                }
                glass.cornerRadius = max(corner, circle ? min(bounds.width, bounds.height) / 2 : corner)
            }
        } else if effect == nil {
            content.removeFromSuperview()
            let material = NoteVisualEffectView(frame: bounds)
            material.material = circle ? .popover : Self.material(theme: theme, finish: finish)
            material.applyActiveGlass(); material.wantsLayer = true
            material.layer?.cornerRadius = corner; material.layer?.masksToBounds = true
            content.frame = material.bounds; content.autoresizingMask = [.width, .height]
            material.addSubview(content); effect = material
            effect!.frame = bounds; effect!.autoresizingMask = [.width, .height]
            addSubview(effect!, positioned: .below, relativeTo: rim)
        }
        effect?.layer?.cornerRadius = corner
        (effect as? NoteVisualEffectView)?.applyActiveGlass()
        if let material = effect as? NoteVisualEffectView, !circle {
            material.material = Self.material(theme: theme, finish: finish)
        }
        shadow = nil
        needsLayout = true
    }
    private static func tintColor(paper: NSColor, theme: NoteTheme, opacity: Double, finish: NoteGlassFinish) -> NSColor {
        let base = (paper.alphaComponent > 0.01 ? paper : (theme == .dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.98, alpha: 1))).usingColorSpace(.deviceRGB) ?? paper
        return base.withAlphaComponent(NotePaperOpacity.backdrop(finish: finish, slider: opacity))
    }
    private static func material(theme: NoteTheme, finish: NoteGlassFinish) -> NSVisualEffectView.Material {
        if theme == .dark { return finish == .glass ? .hudWindow : .underWindowBackground }
        return finish == .glass ? .popover : .sheet
    }
    func refreshMaterial() {
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            if circle {
                glass.style = .clear
            } else if NotePaperOpacity.isSolid(slider: panelOpacity) {
                glass.style = .regular
            } else {
                glass.style = glassFinish == .glass ? .clear : .regular
            }
        }
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
