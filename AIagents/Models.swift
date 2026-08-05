import Foundation

enum InterviewPhase: Equatable {
    case lobby
    case connecting
    case live
    case report
}

enum TurnSpeaker: String, Codable {
    case interviewer
    case candidate
}

struct Turn: Identifiable, Equatable {
    let id = UUID()
    let speaker: TurnSpeaker
    var text: String
}

enum EngineState: Equatable {
    case idle
    case aiSpeaking
    case listening
    case thinking
    case ended
}

struct InterviewReport: Equatable {
    var communication: Int   // 1-10
    var content: Int         // 1-10
    var confidence: Int      // 1-10
    var strengths: [String]
    var improvements: [String]
    var summary: String

    var overall: Int {
        Int((Double(communication + content + confidence) / 3.0).rounded())
    }
}

struct RolePreset: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String

    static let all: [RolePreset] = [
        RolePreset(id: "sales", title: "Sales Consultant", icon: "chart.line.uptrend.xyaxis"),
        RolePreset(id: "swe", title: "Software Engineer", icon: "chevron.left.forwardslash.chevron.right"),
        RolePreset(id: "healthcare", title: "Healthcare / Patient Care", icon: "cross.case"),
        RolePreset(id: "customer", title: "Customer Service", icon: "person.wave.2"),
        RolePreset(id: "general", title: "General / Behavioral", icon: "briefcase"),
    ]
}
