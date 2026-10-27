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
        private var scrollMonitor: Any?

        deinit {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
            guard window != nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, window == event.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                // #region agent log
                AgentDebugLog.emit(hypothesisId: "B", location: "CompletedChartScroll:monitor", message: "chart scroll captured", data: [
                    "boundsW": String(format: "%.0f", self.bounds.width),
                    "boundsH": String(format: "%.0f", self.bounds.height),
                ])
                // #endregion
                self.handleScrollWheel(event)
                return nil
            }
        }

        private func handleScrollWheel(_ event: NSEvent) {
            let precise = event.hasPreciseScrollingDeltas
            var dx = precise ? CGFloat(event.scrollingDeltaX) : CGFloat(event.deltaX) * 12
            let dy = precise ? CGFloat(event.scrollingDeltaY) : CGFloat(event.deltaY) * 12
            if event.modifierFlags.contains(.shift), abs(dy) > abs(dx) {
                dx = -dy
            }
            let horizontal = abs(dx) >= abs(dy) * 0.28 || abs(dx) > 0.4
            guard horizontal, abs(dx) > 0.02 else { return }
            // #region agent log
            AgentDebugLog.emit(hypothesisId: "A", location: "CompletedChartScroll:handle", message: "horizontal scroll applied", data: [
                "dx": String(format: "%.2f", dx),
                "dy": String(format: "%.2f", dy),
            ])
            // #endregion
            onScroll(dx)
            if event.phase == .ended || event.momentumPhase == .ended {
                onScrollEnd()
            }
        }

        override func scrollWheel(with event: NSEvent) {
            handleScrollWheel(event)
        }
    }
}

struct CompletedChartViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
