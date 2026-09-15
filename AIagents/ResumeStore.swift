import Foundation
import SwiftUI

/// scipio's HR pass over every resume it sent (resume_review.json):
/// one row per job, the exact artifact, its rule-lint grade, JD scores.
struct ResumeReview: Codable {
    struct Summary: Codable {
        let jobs_sent: Int
        let confirmed: Int
        let good: Int
        let weak: Int
        let junk: Int
        let unknown: Int
    }

    struct Sent: Codable, Identifiable {
        let id: String
        let job_id: Int?
        let company: String?
        let role: String?
        let url: String?
        let ts: String?
        let day: String?
        let status: String?
        let confirmed: Bool?
        let resume: String?
        let pdf: String?
        let md: String?
        let family: String?
        let grade: String
        let reasons: [String]?
        let ats_score: Int?
        let ats_missing: [String]?
        let match_score: Int?

        var displayCompany: String {
            let c = company ?? "Unknown"
            if c == "Unknown", let u = url, let host = URL(string: u)?.host {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return c
        }
        var resumeShort: String {
            (resume ?? "not recorded")
                .replacingOccurrences(of: "Resume - Sylvester Assiamah ", with: "")
                .replacingOccurrences(of: ".pdf", with: "")
        }
        var pdfURL: URL? { ResumeStore.siteURL(pdf) }
        var mdURL: URL? { ResumeStore.siteURL(md) }
    }

    struct Base: Codable, Identifiable {
        let key: String
        let title: String
        let blurb: String?
        let featured: Bool?
        let pdf: String?
        let md: String?
        let words: Int?
        let grade: String
        let reasons: [String]?
        let summary: String?
        let sent: Int?

        var id: String { key }
        var pdfURL: URL? { ResumeStore.siteURL(pdf) }
        var mdURL: URL? { ResumeStore.siteURL(md) }
    }

    struct RemoteVerdict: Codable {
        let verdict: String
        let reason: String?
        let ts: String?
    }

    let generated: String?
    let summary: Summary
    let applications: [Sent]
    let base: [Base]
    let verdicts: [String: RemoteVerdict]?
}

/// A thumbs-up / thumbs-down Sylvester gave one resume. Kept on the phone
/// immediately; synced to scipio (reviews/verdicts.json) when the network
/// and the worker cooperate — `synced` says which.
struct ResumeVerdict: Codable, Equatable {
    var verdict: String        // "good" | "bad"
    var reason: String = ""
    var resume: String = ""
    var company: String = ""
    var role: String = ""
    var ts = Date()
    var synced = false

    var isGood: Bool { verdict == "good" }
}

enum ResumeGrade {
    static func color(_ g: String) -> Color {
        switch g {
        case "good": return .green
        case "weak": return .orange
        case "junk": return .red
        default: return .gray
        }
    }
    static func label(_ g: String) -> String {
        switch g {
        case "good": return "Good"
        case "weak": return "Weak"
        case "junk": return "Junk"
        default: return "Unknown"
        }
    }
    static func icon(_ g: String) -> String {
        switch g {
        case "good": return "checkmark.seal.fill"
        case "weak": return "exclamationmark.triangle.fill"
        case "junk": return "xmark.octagon.fill"
        default: return "questionmark.circle"
        }
    }
}

@MainActor
final class ResumeStore: ObservableObject {
    nonisolated static let site = "https://assiamahs.github.io/scipio/"
    private static let reviewURL = URL(string: site + "resume_review.json")!
    private static let verdictURL = URL(string: "https://scipio-api.sylvesterassiamahpm.workers.dev/api/resume-verdict")!
    private static let storageKey = "resumeVerdicts"

    @Published var review: ResumeReview?
    @Published var loading = false
    @Published var error: String?
    @Published var verdicts: [String: ResumeVerdict] = [:] {
        didSet { persist() }
    }

    nonisolated static func siteURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        // paths arrive percent-encoded already (resume_review.py quotes them)
        return URL(string: site + p)
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: ResumeVerdict].self, from: data) {
            verdicts = saved
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(verdicts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        var request = URLRequest(url: Self.reviewURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let doc = try JSONDecoder().decode(ResumeReview.self, from: data)
            review = doc
            // verdicts already committed on the scipio side (from this phone
            // or the review page) fill in anything the phone never saw
            for (id, v) in doc.verdicts ?? [:] where verdicts[id] == nil {
                verdicts[id] = ResumeVerdict(verdict: v.verdict, reason: v.reason ?? "", synced: true)
            }
        } catch {
            self.error = "Couldn't load the resume review — the site rebuilds after each scipio run."
        }
        await flushPending()
    }

    /// Record a verdict now, sync in the background.
    func set(_ verdict: String, for id: String, reason: String = "",
             resume: String = "", company: String = "", role: String = "") {
        verdicts[id] = ResumeVerdict(verdict: verdict, reason: reason, resume: resume,
                                     company: company, role: role)
        Task { await sync(id) }
    }

    func clear(_ id: String) {
        verdicts[id] = nil
        Task { _ = await post(["id": id, "verdict": "clear"]) }
    }

    var pendingCount: Int { verdicts.values.filter { !$0.synced }.count }

    private func flushPending() async {
        for (id, v) in verdicts where !v.synced {
            await sync(id)
        }
    }

    private func sync(_ id: String) async {
        guard let v = verdicts[id] else { return }
        let ok = await post(["id": id, "verdict": v.verdict, "reason": v.reason,
                             "resume": v.resume, "company": v.company, "role": v.role])
        if ok, var cur = verdicts[id] {
            cur.synced = true
            verdicts[id] = cur
        }
    }

    private func post(_ body: [String: String]) async -> Bool {
        var request = URLRequest(url: Self.verdictURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
