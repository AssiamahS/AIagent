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
    @State private var onlyAttemptable = false

    private var sectors: [String] {
        ["All sectors"] + Array(Set(companies.map { $0.sector })).sorted()
    }

    private var filtered: [F500Company] {
        companies.filter { c in
            (sector == "All sectors" || c.sector == sector) &&
            (search.isEmpty || c.name.localizedCaseInsensitiveContains(search)) &&
            (!onlyAttemptable || isAttemptable(c))
        }
    }

    private func isAttemptable(_ c: F500Company) -> Bool {
        let s = store.coverage[c.name]?.status
        return s == "attemptable" || s == "applied"
    }

    var body: some View {
        List {
            Section {
                Picker("Sector", selection: $sector) {
                    ForEach(sectors, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Toggle("Only auto-appliable now", isOn: $onlyAttemptable)
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
        .task { if store.coverage.isEmpty { await store.refreshCoverage() } }
        .refreshable { await store.refreshCoverage() }
    }

    private func row(_ company: F500Company) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(company.sector).font(.caption).foregroundStyle(.secondary)
                    if let cov = store.coverage[company.name] {
                        statusChip(cov)
                    }
                }
            }
            Spacer()
            let count = max(store.appliedCount(company: company.name),
                            store.coverage[company.name]?.applied ?? 0)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.3), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
    }

    private func statusChip(_ cov: JobStore.Coverage) -> some View {
        let (text, color): (String, Color) = {
            switch cov.status {
            case "applied": return ("Applied", .green)
            case "attemptable": return ("Ready — \(cov.ats ?? "board") found", .blue)
            case "workday": return ("Workday — needs account flow", .orange)
            case "other_ats": return ("\(cov.ats ?? "ATS") — handler needed", .purple)
            default: return ("No public board found", .gray)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
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

            if let cov = store.coverage[company.name], cov.ats != nil {
                Section {
                    NavigationLink {
                        JobSearchView(company: company, coverage: cov)
                    } label: {
                        Label("Search their open jobs", systemImage: "magnifyingglass.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                }
            }

            if let cov = store.coverage[company.name] {
                Section("Auto-apply status") {
                    coverageExplainer(cov)
                    if let board = cov.board, let boardURL = URL(string: board) {
                        Link(destination: boardURL) {
                            Label("Open their job board", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }

            if let pay = store.salaries[company.name] {
                Section("What they pay (public H-1B disclosures)") {
                    if let laneMed = pay.lane_median, let laneN = pay.lane_n {
                        LabeledContent("Your lane (PM/analyst/infra)",
                                       value: "$\(laneMed.formatted()) median · \(laneN) filings")
                    }
                    LabeledContent("All roles", value: "$\(pay.median.formatted()) median · \(pay.n) filings")
                    if let lo = pay.p25, let hi = pay.p75 {
                        LabeledContent("Middle range", value: "$\(lo.formatted()) – $\(hi.formatted())")
                    }
                    let clears = pay.clears_floor ?? (pay.median >= store.salaryFloor)
                    Label(clears
                          ? "Clears your $\(store.salaryFloor.formatted()) floor — worth your time"
                          : "Below your $\(store.salaryFloor.formatted()) floor — negotiate hard or skip",
                          systemImage: clears ? "dollarsign.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(clears ? .green : .orange)
                }
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

            let auto = store.scipio.filter {
                $0.displayCompany.localizedCaseInsensitiveContains(company.name) ||
                company.name.localizedCaseInsensitiveContains($0.displayCompany)
            }
            if !auto.isEmpty {
                Section("Scipio applied here — resumes sent") {
                    ForEach(auto) { run in
                        NavigationLink {
                            ScipioJobDetailView(run: run)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.role ?? "Unknown role").font(.subheadline)
                                HStack(spacing: 6) {
                                    Text(run.day).font(.caption).foregroundStyle(.secondary)
                                    if run.details?.resume != nil {
                                        Label("resume PDF", systemImage: "doc.richtext")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(company.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func coverageExplainer(_ cov: JobStore.Coverage) -> some View {
        switch cov.status {
        case "applied":
            Label("Applied ×\(cov.applied) — Scipio has already reached this company.", systemImage: "checkmark.seal.fill")
                .font(.footnote).foregroundStyle(.green)
        case "attemptable":
            Label("Ready: \(cov.ats ?? "board") detected — Scipio's handler can apply on the next run.", systemImage: "bolt.fill")
                .font(.footnote).foregroundStyle(.blue)
        case "workday":
            Label("Workday tenant — blocked on per-tenant account creation. Fix queued: account flow + email-code reader.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
        case "other_ats":
            Label("\(cov.ats ?? "ATS") board found — handler not written yet. Paste a job link below to apply through the app instead.", systemImage: "wrench.and.screwdriver.fill")
                .font(.footnote).foregroundStyle(.purple)
        default:
            Label("No public board found by probing — open their careers site and paste a job link below.", systemImage: "questionmark.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func addJob() {
        fetchError = nil
        fetching = true
        Task {
            defer { fetching = false }
            let fetched = await JDFetcher.fetch(from: jobLink)
            let jd = fetched.jobDescription ?? ""
            if jd.isEmpty {
                fetchError = "Couldn't extract the description (site may need JavaScript) — job saved anyway, paste the JD in its page."
            }
            store.manual.insert(
                ManualJob(company: fetched.company ?? company.name,
                          role: fetched.role ?? company.suggestedRole,
                          url: jobLink, status: .applied, jobDescription: jd),
                at: 0)
            savedJob = true
        }
    }
}
