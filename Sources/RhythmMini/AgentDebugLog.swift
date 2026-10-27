import Foundation

enum AgentDebugLog {
    static func emit(hypothesisId: String, location: String, message: String, data: [String: String] = [:], runId: String = "") {
        _ = (hypothesisId, location, message, data, runId)
    }
}
