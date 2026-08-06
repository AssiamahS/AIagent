import SwiftUI

/// One posting from any ATS, normalized.
struct FoundJob: Identifiable {
    let id = UUID()
    let title: String
    let location: String
    let url: String
    let jdFetchURL: String?   // API URL that returns the JD (workday cxs)
    var jdInline: String?     // JD already in the search response (greenhouse/lever)
}

/// Search a company's real openings from inside the app.
/// Workday cxs / Greenhouse / Lever / Ashby / SmartRecruiters public APIs.
struct JobSearchView: View {
    @EnvironmentObject var store: JobStore
    let company: F500Company
    let coverage: JobStore.Coverage

    @AppStorage("searchQuery") private var query = "project manager"
    @AppStorage("searchLocation") private var location = "NJ"
    @State private var results: [FoundJob] = []
    @State private var total = 0
    @State private var searching = false
    @State private var error: String?
    @State private var addedURLs: Set<String> = []

    var body: some View {
        List {
            Section {
                TextField("Role keyword", text: $query)
                TextField("Location filter (blank = anywhere)", text: $location)
                Button {
                    Task { await search() }
                } label: {
                    if searching {
                        HStack { ProgressView(); Text("Searching their openings…") }
                    } else {
                        Label("Search \(company.name) jobs", systemImage: "magnifyingglass")
                    }
                }
                .disabled(searching || query.isEmpty)
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.orange) }
            }

            if !results.isEmpty {
                Section("\(results.count) shown\(total > results.count ? " of \(total)" : "") — tap to add") {
                    ForEach(results) { job in
                        Button {
                            Task { await add(job) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(job.location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: addedURLs.contains(job.url)
                                      ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(addedURLs.contains(job.url) ? .green : .blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search openings")
        .navigationBarTitleDisplayMode(.inline)
        .task { if results.isEmpty { await search() } }
    }

    private func locationOK(_ loc: String) -> Bool {
        let l = location.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return true }
        let hay = loc.lowercased()
        let needles = [l.lowercased()]
            + (l.uppercased() == "NJ" ? ["new jersey", "remote"] : ["remote"])
        return needles.contains { hay.contains($0) }
    }

    // MARK: - Search dispatch by ATS

    private func search() async {
        searching = true
        error = nil
        results = []
        total = 0
        defer { searching = false }
        do {
            switch coverage.ats {
            case "workday": try await searchWorkday()
            case "greenhouse": try await searchGreenhouse()
            case "lever": try await searchLever()
            case "ashby": try await searchAshby()
            case "smartrecruiters": try await searchSmartRecruiters()
            default:
                error = "No public job API found for \(company.name) — use their careers site and paste a specific posting link on the company page."
            }
            if results.isEmpty && error == nil {
                error = total > 0
                    ? "They have \(total) \"\(query)\" roles, but none matched \"\(location)\" — clear the location to see all."
                    : "No \"\(query)\" openings right now."
            }
        } catch {
            self.error = "Search failed — their API may be down. Try again."
        }
    }

    private func searchWorkday() async throws {
        guard let board = coverage.board,
              let host = URL(string: board)?.host,
              let site = coverage.site else {
            error = "Workday tenant found but its site ID isn't mapped yet — pull-refresh the Jobs tab after the next data update."
            return
        }
        let tenant = host.components(separatedBy: ".").first ?? ""
        var request = URLRequest(url: URL(string: "https://\(host)/wday/cxs/\(tenant)/\(site)/jobs")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject:
            ["searchText": query, "limit": 20, "offset": 0, "appliedFacets": [:]])
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Resp: Codable {
            struct Post: Codable { let title: String?; let locationsText: String?; let externalPath: String? }
            let total: Int?
            let jobPostings: [Post]?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        total = r.total ?? 0
        results = (r.jobPostings ?? []).compactMap { p in
            guard let t = p.title, let path = p.externalPath else { return nil }
            let loc = p.locationsText ?? ""
            guard locationOK(loc) || locationOK(t) else { return nil }
            return FoundJob(title: t, location: loc,
                            url: "https://\(host)/en-US/\(site)\(path)",
                            jdFetchURL: "https://\(host)/wday/cxs/\(tenant)/\(site)\(path)",
                            jdInline: nil)
        }
    }

    private func searchGreenhouse() async throws {
        guard let slug = coverage.board?.split(separator: "/").last else { return }
        let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(slug)/jobs?content=true")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Resp: Codable {
            struct Job: Codable {
                struct Loc: Codable { let name: String? }
                let title: String?; let absolute_url: String?; let location: Loc?; let content: String?
            }
            let jobs: [Job]?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        let q = query.lowercased()
        let matches = (r.jobs ?? []).filter { ($0.title ?? "").lowercased().contains(q) }
        total = matches.count
        results = matches.compactMap { j in
            guard let t = j.title, let u = j.absolute_url else { return nil }
            let loc = j.location?.name ?? ""
            guard locationOK(loc) else { return nil }
            return FoundJob(title: t, location: loc, url: u, jdFetchURL: nil,
                            jdInline: j.content.map(Self.stripHTML))
        }
    }

    private func searchLever() async throws {
        guard let slug = coverage.board?.split(separator: "/").last else { return }
        let url = URL(string: "https://api.lever.co/v0/postings/\(slug)?mode=json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Post: Codable {
            struct Cat: Codable { let location: String? }
            let text: String?; let hostedUrl: String?; let categories: Cat?; let descriptionPlain: String?
        }
        let posts = try JSONDecoder().decode([Post].self, from: data)
        let q = query.lowercased()
        let matches = posts.filter { ($0.text ?? "").lowercased().contains(q) }
        total = matches.count
        results = matches.compactMap { p in
            guard let t = p.text, let u = p.hostedUrl else { return nil }
            let loc = p.categories?.location ?? ""
            guard locationOK(loc) else { return nil }
            return FoundJob(title: t, location: loc, url: u, jdFetchURL: nil, jdInline: p.descriptionPlain)
        }
    }

    private func searchAshby() async throws {
        guard let slug = coverage.board?.split(separator: "/").last else { return }
        let url = URL(string: "https://api.ashbyhq.com/posting-api/job-board/\(slug)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Resp: Codable {
            struct Job: Codable { let title: String?; let location: String?; let jobUrl: String?; let descriptionPlain: String? }
            let jobs: [Job]?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        let q = query.lowercased()
        let matches = (r.jobs ?? []).filter { ($0.title ?? "").lowercased().contains(q) }
        total = matches.count
        results = matches.compactMap { j in
            guard let t = j.title, let u = j.jobUrl else { return nil }
            let loc = j.location ?? ""
            guard locationOK(loc) else { return nil }
            return FoundJob(title: t, location: loc, url: u, jdFetchURL: nil, jdInline: j.descriptionPlain)
        }
    }

    private func searchSmartRecruiters() async throws {
        guard let slug = coverage.board?.split(separator: "/").last else { return }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://api.smartrecruiters.com/v1/companies/\(slug)/postings?q=\(q)&limit=20")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Resp: Codable {
            struct Post: Codable {
                struct Loc: Codable { let city: String?; let region: String? }
                let name: String?; let location: Loc?; let ref: String?; let applyUrl: String?
            }
            let totalFound: Int?
            let content: [Post]?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        total = r.totalFound ?? 0
        results = (r.content ?? []).compactMap { p in
            guard let t = p.name else { return nil }
            let loc = [p.location?.city, p.location?.region].compactMap { $0 }.joined(separator: ", ")
            guard locationOK(loc) else { return nil }
            let u = p.applyUrl ?? p.ref ?? ""
            guard !u.isEmpty else { return nil }
            return FoundJob(title: t, location: loc, url: u, jdFetchURL: nil, jdInline: nil)
        }
    }

    // MARK: - Add with JD

    private func add(_ job: FoundJob) async {
        var jd = job.jdInline ?? ""
        if jd.isEmpty, let api = job.jdFetchURL, let url = URL(string: api) {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let info = obj["jobPostingInfo"] as? [String: Any],
               let desc = info["jobDescription"] as? String {
                jd = Self.stripHTML(desc)
            }
        }
        store.manual.insert(
            ManualJob(company: company.name, role: job.title, url: job.url,
                      status: .saved, jobDescription: String(jd.prefix(8000))),
            at: 0)
        addedURLs.insert(job.url)
    }

    static func stripHTML(_ html: String) -> String {
        var t = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s{2,}", with: "\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
