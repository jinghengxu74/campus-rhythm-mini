import Foundation

public enum CompletedChartWindow {
    public static let totalDayCount = 56
    public static let visibleDayCount = 7
    public static let maximumStartIndex = totalDayCount - visibleDayCount

    public static func startIndex(scrollX: Double, dayWidth: Double) -> Int {
        guard scrollX.isFinite, dayWidth > 0 else { return 0 }
        let index = Int((scrollX / dayWidth).rounded())
        return min(maximumStartIndex, max(0, index))
    }

    public static func endOffset(scrollX: Double, dayWidth: Double) -> Int {
        startIndex(scrollX: scrollX, dayWidth: dayWidth) - maximumStartIndex
    }
}
