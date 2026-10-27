import CoreGraphics
import Foundation

public struct NoteResizeEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = Self(rawValue: 1)
    public static let right = Self(rawValue: 2)
    public static let top = Self(rawValue: 4)
    public static let bottom = Self(rawValue: 8)
}
public enum NoteWindowGeometry {
    // Screen coordinates: positive Y is up. The opposite edge stays anchored.
    public static func resized(_ start: CGRect, by delta: CGSize, edges: NoteResizeEdges, minimum: CGSize, maximum: CGSize) -> CGRect {
        var frame = start
        if edges.contains(.left) || edges.contains(.right) {
            frame.size.width = min(max(start.width + (edges.contains(.left) ? -delta.width : delta.width), minimum.width), maximum.width)
            if edges.contains(.left) { frame.origin.x = start.maxX - frame.width }
        }
        if edges.contains(.top) || edges.contains(.bottom) {
            frame.size.height = min(max(start.height + (edges.contains(.bottom) ? -delta.height : delta.height), minimum.height), maximum.height)
            if edges.contains(.bottom) { frame.origin.y = start.maxY - frame.height }
        }
        return frame
    }
}
