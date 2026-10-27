import AppKit
import SwiftUI

/// Captures trackpad / mouse horizontal scroll over the completed chart (SwiftUI horizontal ScrollView is unreliable in NSPanel).
struct NoteChartHorizontalWheelCapture: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    var onScrollEnd: () -> Void

    func makeNSView(context: Context) -> WheelView {
        let view = WheelView()
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        return view
    }

    func updateNSView(_ nsView: WheelView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onScrollEnd = onScrollEnd
    }

    final class WheelView: NSView {
        var onScroll: (CGFloat) -> Void = { _ in }
        var onScrollEnd: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let dx = event.hasPreciseScrollingDeltas
                ? CGFloat(event.scrollingDeltaX)
                : CGFloat(event.deltaX) * 10
            let dy = event.hasPreciseScrollingDeltas
                ? CGFloat(event.scrollingDeltaY)
                : CGFloat(event.deltaY) * 10
            guard abs(dx) >= abs(dy) * 0.35, abs(dx) > 0.05 else {
                super.scrollWheel(with: event)
                return
            }
            onScroll(dx)
            if event.phase == .ended || event.momentumPhase == .ended {
                onScrollEnd()
            }
        }
    }
}

struct CompletedChartViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
