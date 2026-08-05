import Foundation

/// Talks to OpenRouter's free models when a key is set,
/// otherwise falls back to a built-in question bank so the app works offline.
struct LLMClient {

    struct ChatMessage: Codable {
        let role: String   // "system" | "user" | "assistant"
        let content: String
    }

    static var apiKey: String {
        UserDefaults.standard.string(forKey: "openRouterKey") ?? ""
    }

    static var model: String {
        let m = UserDefaults.standard.string(forKey: "openRouterModel") ?? ""
        return m.isEmpty ? "google/gemma-4-26b-a4b-it:free" : m
    }

    static var hasLiveBrain: Bool { !apiKey.isEmpty }

    static func systemPrompt(role: String, candidateName: String) -> String {
        """
        You are Victoria, a warm but sharp professional recruiter conducting a live spoken video interview \
        for a \(role) position. The candidate's name is \(candidateName). Rules:
        - Ask exactly ONE question per message. Never ask two things at once.
        - Keep every message under 60 spoken words — this is voice, not text.
        - React briefly and naturally to the candidate's last answer (one short sentence), then ask the next question.
        - Mix behavioral and role-specific questions. Ask a follow-up that digs into their last answer when it is interesting or vague.
        - Never use markdown, lists, or stage directions. Output only the words you would say aloud.
        """
    }

    /// One chat completion round-trip. Throws on network/API failure.
    static func complete(messages: [ChatMessage], maxTokens: Int = 300) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Codable {
            let model: String
            let messages: [ChatMessage]
            let max_tokens: Int
            let temperature: Double
        }
        request.httpBody = try JSONEncoder().encode(
            Body(model: model, messages: messages, max_tokens: maxTokens, temperature: 0.7)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "LLMClient", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "Model API returned \(code)"])
        }

        struct Choice: Codable { struct Msg: Codable { let content: String }; let message: Msg }
        struct Resp: Codable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw NSError(domain: "LLMClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Empty completion"])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Offline question bank fallback

    static func bankQuestions(forRoleId roleId: String) -> [String] {
        let common = [
            "Tell me a little about yourself and what brought you to this point in your career.",
            "Tell me about a time you dealt with a difficult person at work. What did you do?",
            "What would you say is your biggest strength, and how has it shown up recently?",
            "Where do you see yourself in a few years, and how does this role fit into that?",
        ]
        let roleSpecific: [String: [String]] = [
            "sales": [
                "Walk me through how you would approach a customer who says they're just browsing.",
                "Tell me about a time you turned a no into a yes.",
                "How do you handle missing a sales target?",
            ],
            "swe": [
                "Walk me through a project you're proud of. What was the hardest technical decision?",
                "Tell me about a bug that took you a long time to find. How did you finally crack it?",
                "How do you decide when code is good enough to ship?",
            ],
            "healthcare": [
                "Tell me about a time you had to stay calm with an upset patient or family member.",
                "How do you balance speed and accuracy when things get busy?",
                "Why patient care? What keeps you in it on the hard days?",
            ],
            "customer": [
                "A customer is angry about something that isn't your fault. What do you do?",
                "Tell me about the best service experience you've ever given someone.",
                "How do you handle back-to-back difficult interactions without burning out?",
            ],
        ]
        let extras = roleSpecific[roleId] ?? [
            "Tell me about a challenge you faced recently and how you worked through it.",
            "What kind of team environment do you do your best work in?",
        ]
        // Interleave: intro question first, then alternate role/common.
        var out: [String] = [common[0]]
        var r = extras.makeIterator()
        var c = common.dropFirst().makeIterator()
        while true {
            let a = r.next(); let b = c.next()
            if let a { out.append(a) }
            if let b { out.append(b) }
            if a == nil && b == nil { break }
        }
        return out
    }

    /// Heuristic report used when there is no API token.
    static func heuristicReport(turns: [Turn]) -> InterviewReport {
        let answers = turns.filter { $0.speaker == .candidate }.map { $0.text }
        let words = answers.map { $0.split(separator: " ").count }
        let avg = words.isEmpty ? 0 : words.reduce(0, +) / max(words.count, 1)
        let communication = min(10, max(3, avg / 12 + 4))
        let content = min(10, max(3, avg / 15 + 4))
        let confidence = min(10, max(3, answers.count + 3))
        var strengths = ["You showed up and finished the interview — reps are how this gets easy."]
        var improvements: [String] = []
        if avg >= 40 { strengths.append("Good answer length — you gave the interviewer something to work with.") }
        if avg < 25 { improvements.append("Answers were short. Aim for 45–90 seconds using Situation → Action → Result.") }
        improvements.append("Add an OpenRouter key in Settings to unlock AI scoring and adaptive follow-up questions.")
        return InterviewReport(
            communication: communication, content: content, confidence: confidence,
            strengths: strengths, improvements: improvements,
            summary: "Practice interview complete: \(answers.count) answers, ~\(avg) words per answer. This report was generated locally — add a free OpenRouter key in Settings for full AI feedback."
        )
    }
}
