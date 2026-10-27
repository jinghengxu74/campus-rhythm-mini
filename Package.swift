// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CampusRhythmMini",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CampusRhythmMini", targets: ["RhythmMini"])],
    targets: [
        .target(name: "NoteCore"),
        .executableTarget(name: "RhythmMini", dependencies: ["NoteCore"], exclude: ["Cloud.swift"]),
        .testTarget(name: "NoteCoreTests", dependencies: ["NoteCore"], resources: [.process("Fixtures")])
    ]
)
