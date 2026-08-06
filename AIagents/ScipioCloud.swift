import Foundation

/// One call: paste a job URL → scipio's cloud queue → the codespace runner
/// applies unattended. No token on the phone; the worker holds it.
enum ScipioCloud {
    private static let applyURL = URL(string: "https://scipio-api.sylvesterassiamahpm.workers.dev/api/apply")!

    struct QueueReply: Codable {
        let queued: Bool?
        let known_ats: Bool?
        let error: String?
    }

    /// Queues the apply and returns a human-readable status line.
    static func apply(jobURL: String) async -> (ok: Bool, message: String) {
        var request = URLRequest(url: applyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": jobURL])
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let reply = try? JSONDecoder().decode(QueueReply.self, from: data)
            guard (response as? HTTPURLResponse)?.statusCode == 200, reply?.queued == true else {
                return (false, "Scipio couldn't queue it: \(reply?.error ?? "server error") — try again in a minute.")
            }
            if reply?.known_ats == true {
                return (true, "Queued — Scipio is applying now with a tailored resume. Pull-refresh Applied in ~15 min for the result.")
            }
            return (true, "Queued — this ATS isn't one Scipio fully automates yet, so it will try, log what happened, and park it for review if the site blocks it.")
        } catch {
            return (false, "Network error reaching Scipio — try again.")
        }
    }
}
