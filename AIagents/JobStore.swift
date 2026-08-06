import Foundation
import SwiftUI

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case saved = "Saved"
    case applied = "Applied"
    case interviewing = "Interviewing"
    case offer = "Offer"
    case rejected = "Rejected"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .saved: return .purple
        case .applied: return .blue
        case .interviewing: return .orange
        case .offer: return .green
        case .rejected: return .gray
        }
    }
}

/// AI verdict on a manual application: odds of getting it, ATS-style.
struct JobScore: Codable, Equatable {
    var odds: Int              // 0-100 chance estimate
    var atsScore: Int          // 0-100 keyword/parse fit
    var verdict: String
    var missingKeywords: [String]
    var fixes: [String]
    var requirements: [String]?   // what the application needs (resume, cover letter, portfolio…)
}

struct ManualJob: Identifiable, Codable, Equatable {
    var id = UUID()
    var company: String
    var role: String
    var url: String = ""
    var status: JobStatus = .applied
    var jobDescription: String = ""
    var notes: String = ""
    var dateAdded = Date()
    var score: JobScore?
}

/// Int that may arrive as a JSON number or a numeric string.
struct FlexInt: Codable, Equatable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let s = try? c.decode(String.self) { value = Int(s) }
        else { value = nil }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// One row from scipio's public apply_log.json (tolerant decode).
struct ScipioRun: Identifiable, Codable {
    struct Details: Codable {
        let ats: String?
        let ats_score: FlexInt?
        let ats_missing: [String]?
        let match_score: FlexInt?
        let match_reason: String?
        let matching_skills: [String]?
        let resume: String?
    }

    let timestamp: String?
    let company: String?
    let role: String?
    let url: String?
    let status: String?
    let details: Details?

    var id: String { (timestamp ?? "") + (url ?? "") }

    var atsScore: Int? { details?.ats_score?.value }
    var matchScore: Int? { details?.match_score?.value }

    /// Blunt read on the odds, from scipio's own scoring.
    var verdict: String {
        let ats = atsScore ?? -1
        let match = matchScore ?? -1
        if ats < 0 && match < 0 { return "Not scored" }
        if ats >= 70 || match >= 8 { return "Strong shot" }
        if ats >= 50 || match >= 6 { return "Fair shot" }
        return "Long shot"
    }

    var resumePDFURL: URL? {
        guard let name = details?.resume, !name.isEmpty,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://assiamahs.github.io/scipio/resumes/\(encoded)")
    }

    var displayCompany: String {
        let c = company ?? "Unknown"
        if c == "Unknown", let u = url, let host = URL(string: u)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return c
    }

    var isConfirmed: Bool {
        let s = (status ?? "").lowercased()
        return s.contains("submit") || s.contains("confirm")
    }

    var day: String {
        String((timestamp ?? "").prefix(10))
    }
}

@MainActor
final class JobStore: ObservableObject {
    @Published var manual: [ManualJob] = [] {
        didSet { persist() }
    }
    @Published var scipio: [ScipioRun] = []
    @Published var loadingScipio = false
    @Published var scipioError: String?

    private static let storageKey = "manualJobs"
    private static let feedURL = URL(string: "https://assiamahs.github.io/scipio/apply_log.json")!
    private static let resumeURL = URL(string: "https://assiamahs.github.io/scipio/resume.md")!

    /// The resume the scorer judges against. Auto-synced from the scipio site
    /// unless the user has edited their own copy in Settings.
    var resumeText: String {
        UserDefaults.standard.string(forKey: "resumeText") ?? ""
    }

    /// Coverage board row: what ATS a Fortune 500 company runs and whether
    /// scipio can reach it. Fetched from the scipio pages site.
    struct Coverage: Codable {
        let name: String
        let ats: String?
        let board: String?
        let applied: Int
        let status: String   // applied | attemptable | workday | other_ats | unknown
        let site: String?    // workday career-site ID, discovered separately
    }

    @Published var coverage: [String: Coverage] = [:]   // keyed by company name

    func refreshCoverage() async {
        guard let url = URL(string: "https://assiamahs.github.io/scipio/f500_coverage.json") else { return }
        struct Board: Codable { let companies: [Coverage] }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let board = try? JSONDecoder().decode(Board.self, from: data) {
            coverage = Dictionary(uniqueKeysWithValues: board.companies.map { ($0.name, $0) })
        }
    }

    /// Per-company salary stats from public H-1B disclosures (f500_salaries.json).
    struct SalaryStat: Codable {
        let n: Int
        let median: Int
        let p25: Int?
        let p75: Int?
        let lane_n: Int?
        let lane_median: Int?
        let clears_floor: Bool?
    }

    @Published var salaries: [String: SalaryStat] = [:]
    @Published var salaryFloor: Int = 120_000

    func refreshSalaries() async {
        guard let url = URL(string: "https://assiamahs.github.io/scipio/f500_salaries.json") else { return }
        struct Feed: Codable { let floor: Int?; let companies: [String: SalaryStat] }
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let feed = try? JSONDecoder().decode(Feed.self, from: data) {
            salaries = feed.companies
            if let f = feed.floor { salaryFloor = f }
        }
    }

    /// Funnel: resume-variant performance, ghosted applications, open invites.
    struct VariantStat: Codable, Identifiable {
        let resume: String
        let sent: Int
        let rejected: Int
        let interviews: Int
        let response_rate: Double
        var id: String { resume }
    }
    struct Ghost: Codable, Identifiable {
        let company: String
        let role: String
        let url: String
        let days_silent: Int
        var id: String { url }
    }
    struct OpenInvite: Codable, Identifiable {
        let company: String?
        let subject: String?
        let date: String?
        var id: String { (company ?? "") + (date ?? "") }
    }

    @Published var variantStats: [VariantStat] = []
    @Published var ghosts: [Ghost] = []
    @Published var openInvites: [OpenInvite] = []

    func refreshFunnel() async {
        guard let url = URL(string: "https://assiamahs.github.io/scipio/funnel_stats.json") else { return }
        struct Feed: Codable {
            let variants: [VariantStat]?
            let ghosts: [Ghost]?
            let open_invites: [OpenInvite]?
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let feed = try? JSONDecoder().decode(Feed.self, from: data) {
            variantStats = feed.variants ?? []
            ghosts = feed.ghosts ?? []
            openInvites = feed.open_invites ?? []
        }
    }

    /// Job descriptions from scipio's jobs.json, keyed by posting URL —
    /// pairs each sent resume with the JD it was sent against.
    @Published var jdByURL: [String: String] = [:]

    func refreshJobsFeed() async {
        guard let url = URL(string: "https://assiamahs.github.io/scipio/jobs.json") else { return }
        struct Feed: Codable { let jobs: [Entry] }
        struct Entry: Codable {
            let url: String?
            let description: String?
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let feed = try? JSONDecoder().decode(Feed.self, from: data) {
            var map: [String: String] = [:]
            for j in feed.jobs {
                if let u = j.url, let d = j.description, !u.isEmpty, !d.isEmpty {
                    map[u] = d
                }
            }
            jdByURL = map
        }
    }

    func refreshResume() async {
        guard !UserDefaults.standard.bool(forKey: "resumeTextEdited") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: Self.resumeURL),
           let text = String(data: data, encoding: .utf8), text.count > 200 {
            UserDefaults.standard.set(text, forKey: "resumeText")
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let jobs = try? JSONDecoder().decode([ManualJob].self, from: data) {
            manual = jobs
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(manual) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func refreshScipio() async {
        loadingScipio = true
        scipioError = nil
        defer { loadingScipio = false }
        do {
            var request = URLRequest(url: Self.feedURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let runs = try JSONDecoder().decode([ScipioRun].self, from: data)
            scipio = runs.reversed()   // newest first
        } catch {
            scipioError = "Couldn't load Scipio feed"
        }
    }

    var confirmedCount: Int { scipio.filter { $0.isConfirmed }.count }

    /// How many times this company has been applied to (manual + scipio).
    func appliedCount(company: String) -> Int {
        guard !company.isEmpty else { return 0 }
        let m = manual.filter { $0.company.localizedCaseInsensitiveContains(company) }.count
        let s = scipio.filter { $0.displayCompany.localizedCaseInsensitiveContains(company) }.count
        return m + s
    }

    /// Unique companies in the manual list, with counts, newest first.
    var manualCompanies: [(company: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for job in manual {
            let key = job.company.isEmpty ? "Unknown" : job.company
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    var appliedThisWeek: Int {
        let cal = Calendar.current
        let manualWeek = manual.filter {
            cal.dateComponents([.day], from: $0.dateAdded, to: Date()).day ?? 99 < 7
        }.count
        let fmt = ISO8601DateFormatter()
        let scipioWeek = scipio.filter {
            guard let t = $0.timestamp,
                  let d = fmt.date(from: String(t.prefix(19)) + "Z") else { return false }
            return cal.dateComponents([.day], from: d, to: Date()).day ?? 99 < 7
        }.count
        return manualWeek + scipioWeek
    }
}
