import Foundation

public struct NoteReleaseVersion: Comparable, Equatable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let value = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part) else { return nil }
            parsed.append(number)
        }
        components = parsed
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: NoteReleaseVersion, rhs: NoteReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: NoteReleaseVersion, rhs: NoteReleaseVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct LatestNoteRelease: Decodable {
    public let tagName: String
    public let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public func isNewer(than current: NoteReleaseVersion) -> Bool {
        guard let latest = NoteReleaseVersion(tagName) else { return false }
        return latest > current
    }
}
