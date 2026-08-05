import Foundation
import Combine
import SwiftUI

/// Orchestrates the interview: AI speaks → listens to the candidate →
/// thinks (LLM or question bank) → speaks again. Ends with a report.
@MainActor
final class InterviewEngine: ObservableObject {
    @Published var phase: InterviewPhase = .lobby
    @Published var state: EngineState = .idle
    @Published var turns: [Turn] = []
    @Published var report: InterviewReport?
    @Published var errorBanner: String?
    @Published var showTranscript = true
    @Published var elapsed: TimeInterval = 0

    @AppStorage("candidateName") var candidateName = "Candidate"
    @AppStorage("roleId") var roleId = "general"
    @AppStorage("roleTitle") var roleTitle = "General / Behavioral"

    /// Job-specific practice: set from the Jobs tab, cleared on lobby role change.
    @Published var jobContext: String = ""
    @Published var selectedTab: Int = 0

    let speech = SpeechManager()
    let speaker = Speaker()

    /// Interview length before wrap-up.
    private let questionLimit = 6
    private var questionsAsked = 0
    private var bankQueue: [String] = []
    private var silenceTimer: Timer?
    private var clockTimer: Timer?
    private var startedAt: Date?

    // MARK: - Lifecycle

    /// Called from the Jobs tab: tailor the interview to a specific application.
    func prepareInterview(role: String, company: String, jobDescription: String) {
        let title = [role, company].filter { !$0.isEmpty }.joined(separator: " at ")
        if !title.isEmpty {
            roleTitle = title
            roleId = "general"
        }
        jobContext = jobDescription
        phase = .lobby
        selectedTab = 0
    }

    func startInterview() {
        turns = []
        report = nil
        questionsAsked = 0
        bankQueue = LLMClient.bankQuestions(forRoleId: roleId)
        phase = .connecting
        startedAt = Date()
        startClock()

        // Small "connecting you with your interviewer" beat, like the real thing.
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard self.phase == .connecting else { return }
            self.phase = .live
            await self.askNextQuestion(isFirst: true)
        }
    }

    func endInterview() {
        speaker.stop()
        speech.stopListening()
        silenceTimer?.invalidate()
        clockTimer?.invalidate()
        state = .ended
        phase = .report
        Task { await generateReport() }
    }

    func backToLobby() {
        phase = .lobby
        state = .idle
        elapsed = 0
    }

    // MARK: - Conversation loop

    private func askNextQuestion(isFirst: Bool = false) async {
        state = .thinking
        questionsAsked += 1

        let text: String
        if questionsAsked > questionLimit {
            text = "That's everything from me, \(candidateName). Thanks so much for your time today — you'll see your feedback in just a moment."
        } else if LLMClient.hasLiveBrain {
            text = await liveQuestion(isFirst: isFirst)
        } else if isFirst {
            let q = bankQueue.isEmpty ? "Tell me about yourself." : bankQueue.removeFirst()
            text = "Hi \(candidateName), I'm Victoria — great to meet you. Thanks for making time for this \(roleTitle) interview. Let's jump in. \(q)"
        } else {
            text = bankQueue.isEmpty ? "Tell me more about that." : bankQueue.removeFirst()
        }

        turns.append(Turn(speaker: .interviewer, text: text))
        state = .aiSpeaking
        speaker.speak(text) { [weak self] in
            guard let self else { return }
            if self.questionsAsked > self.questionLimit {
                self.endInterview()
            } else {
                self.beginListening()
            }
        }
    }

    private func liveQuestion(isFirst: Bool) async -> String {
        var system = LLMClient.systemPrompt(role: roleTitle, candidateName: candidateName)
        if !jobContext.isEmpty {
            system += "\nThe job description follows — ground your questions in it:\n\(jobContext.prefix(2000))"
        }
        var messages: [LLMClient.ChatMessage] = [
            .init(role: "system", content: system)
        ]
        for turn in turns {
            messages.append(.init(role: turn.speaker == .interviewer ? "assistant" : "user", content: turn.text))
        }
        if isFirst {
            messages.append(.init(role: "user", content: "(The candidate has just joined the call. Greet them briefly and ask your first question.)"))
        }
        do {
            return try await LLMClient.complete(messages: messages)
        } catch {
            errorBanner = "AI brain unreachable — using built-in questions."
            return bankQueue.isEmpty ? "Tell me about a recent challenge and how you handled it." : bankQueue.removeFirst()
        }
    }

    private func beginListening() {
        do {
            try speech.startListening()
            state = .listening
            startSilenceWatch()
        } catch {
            errorBanner = "Microphone unavailable: \(error.localizedDescription)"
            state = .idle
        }
    }

    /// Candidate taps "Done" or goes quiet for a few seconds.
    func finishAnswer() {
        guard state == .listening else { return }
        silenceTimer?.invalidate()
        speech.stopListening()
        let answer = speech.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        turns.append(Turn(speaker: .candidate, text: answer.isEmpty ? "(no answer)" : answer))
        Task { await askNextQuestion() }
    }

    private func startSilenceWatch() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                let quiet = Date().timeIntervalSince(self.speech.lastTranscriptChange)
                let hasText = !self.speech.liveTranscript.isEmpty
                if hasText && quiet > 3.5 {
                    self.finishAnswer()
                }
            }
        }
    }

    private func startClock() {
        elapsed = 0
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    // MARK: - Report

    private func generateReport() async {
        if LLMClient.hasLiveBrain {
            let transcript = turns.map { "\($0.speaker == .interviewer ? "Victoria" : candidateName): \($0.text)" }
                .joined(separator: "\n")
            let prompt = """
            You are an interview coach. Score this \(roleTitle) practice interview transcript. \
            Respond with ONLY valid JSON, no code fences: \
            {"communication": 1-10, "content": 1-10, "confidence": 1-10, \
            "strengths": ["...", "..."], "improvements": ["...", "..."], "summary": "2-3 sentences"}

            TRANSCRIPT:
            \(transcript)
            """
            do {
                var raw = try await LLMClient.complete(
                    messages: [.init(role: "user", content: prompt)], maxTokens: 500)
                raw = raw.replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                struct R: Codable {
                    let communication: Int; let content: Int; let confidence: Int
                    let strengths: [String]; let improvements: [String]; let summary: String
                }
                if let data = raw.data(using: .utf8) {
                    let r = try JSONDecoder().decode(R.self, from: data)
                    report = InterviewReport(communication: r.communication, content: r.content,
                                             confidence: r.confidence, strengths: r.strengths,
                                             improvements: r.improvements, summary: r.summary)
                    return
                }
            } catch { /* fall through to heuristic */ }
        }
        report = LLMClient.heuristicReport(turns: turns)
    }

    var clockText: String {
        let m = Int(elapsed) / 60, s = Int(elapsed) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
