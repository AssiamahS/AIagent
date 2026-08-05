import Foundation
import SwiftUI

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case applied = "Applied"
    case interviewing = "Interviewing"
    case offer = "Offer"
    case rejected = "Rejected"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .applied: return .blue
        case .interviewing: return .orange
        case .offer: return .green
        case .rejected: return .gray
        }
    }
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
}

/// One row from scipio's public apply_log.json (tolerant decode).
struct ScipioRun: Identifiable, Codable {
    let timestamp: String?
    let company: String?
    let role: String?
    let url: String?
    let status: String?

    var id: String { (timestamp ?? "") + (url ?? "") }

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
