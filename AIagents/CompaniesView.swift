import SwiftUI

struct F500Company: Identifiable, Codable {
    let rank: Int
    let name: String
    let sector: String
    let industry: String

    var id: Int { rank }

    var careersURL: URL {
        let q = "\(name) careers jobs".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://www.google.com/search?q=\(q)")!
    }

    /// The role to hunt for, based on the user's healthcare-IT / infra / PM background.
    var suggestedRole: String {
        switch sector {
        case "Health Care": return "Healthcare IT Project Manager / Clinical Systems Analyst"
        case "Technology", "Telecommunications": return "IT Project Manager / Infrastructure Engineer"
        case "Financials": return "IT Project Manager / Business Systems Analyst"
        case "Retailing", "Food and Drug Stores", "Wholesalers": return "IT Operations / Systems Project Manager"
        case "Aerospace & Defense", "Industrials", "Engineering & Construction":
            return "Infrastructure / IT Program Coordinator"
        default: return "IT Project Manager"
        }
    }

    static func loadAll() -> [F500Company] {
        guard let url = Bundle.main.url(forResource: "F500", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([F500Company].self, from: data)
        else { return [] }
        return list
    }
}

/// Fortune 500 directory: sortable by sector, applied badges,
/// paste a job link → JD is fetched → score + what's needed.
struct CompaniesView: View {
    @EnvironmentObject var store: JobStore
    @State private var companies: [F500Company] = []
    @State private var search = ""
    @State private var sector: String = "All sectors"

    private var sectors: [String] {
        ["All sectors"] + Array(Set(companies.map { $0.sector })).sorted()
    }

    private var filtered: [F500Company] {
        companies.filter { c in
            (sector == "All sectors" || c.sector == sector) &&
            (search.isEmpty || c.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sector", selection: $sector) {
                    ForEach(sectors, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
            }
            Section("Fortune 500 — \(filtered.count) companies") {
                ForEach(filtered) { company in
                    NavigationLink {
                        CompanyDetailView(company: company)
                    } label: {
                        row(company)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Company name")
        .onAppear { if companies.isEmpty { companies = F500Company.loadAll() } }
    }

    private func row(_ company: F500Company) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name).font(.subheadline.weight(.semibold))
                Text(company.sector).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let count = store.appliedCount(company: company.name)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.3), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
    }
}

struct CompanyDetailView: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var engine: InterviewEngine
    let company: F500Company

    @State private var jobLink = ""
    @State private var fetching = false
    @State private var fetchError: String?
    @State private var savedJob = false

    var body: some View {
        List {
            Section {
                LabeledContent("Rank", value: "#\(company.rank)")
                LabeledContent("Sector", value: company.sector)
                LabeledContent("Industry", value: company.industry)
            }

            Section("Your angle") {
                Label(company.suggestedRole, systemImage: "target")
                    .font(.footnote)
                Link(destination: company.careersURL) {
                    Label("Find their careers site", systemImage: "safari")
                }
            }

            Section("Add a job from their site") {
                TextField("Paste job posting link", text: $jobLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if let err = fetchError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Button {
                    addJob()
                } label: {
                    if fetching {
                        HStack { ProgressView(); Text("Fetching job description…") }
                    } else if savedJob {
                        Label("Added — check My Applications", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Fetch description & add to my jobs", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(fetching || jobLink.isEmpty)
            }

            let mine = store.manual.filter { $0.company.localizedCaseInsensitiveContains(company.name) }
            if !mine.isEmpty {
                Section("My applications here") {
                    ForEach(mine) { job in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.role.isEmpty ? "Untitled role" : job.role)
                                .font(.subheadline)
                            Text(job.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(company.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addJob() {
        fetchError = nil
        fetching = true
        Task {
            defer { fetching = false }
            var jd = ""
            if let url = URL(string: jobLink) {
                jd = (try? await Self.fetchJobDescription(url)) ?? ""
            }
            if jd.isEmpty {
                fetchError = "Couldn't extract the description (site may need JavaScript) — job saved anyway, paste the JD in its page."
            }
            store.manual.insert(
                ManualJob(company: company.name, role: company.suggestedRole,
                          url: jobLink, status: .applied, jobDescription: jd),
                at: 0)
            savedJob = true
        }
    }

    /// Plain fetch + tag strip. Enough for Greenhouse/Lever-style pages;
    /// JS-only ATSes come back empty and the user pastes instead.
    static func fetchJobDescription(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard var html = String(data: data, encoding: .utf8) else { return "" }
        for tag in ["script", "style", "nav", "header", "footer"] {
            html = html.replacingOccurrences(
                of: "<\(tag)[\\s\\S]*?</\(tag)>", with: " ",
                options: [.regularExpression, .caseInsensitive])
        }
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 200 ? String(text.prefix(8000)) : ""
    }
}
