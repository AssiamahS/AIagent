import SwiftUI

/// The place for every job applied to: manual entries + Scipio's auto-applies,
/// plus the Fortune 500 directory.
struct JobsView: View {
    @EnvironmentObject var engine: InterviewEngine
    @EnvironmentObject var store: JobStore
    @State private var showAdd = false
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    Text("Applied").tag(0)
                    Text("F500").tag(1)
                    Text("Health").tag(2)
                    Text("Finance").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 4)

                switch segment {
                case 0: appliedList
                case 1: CompaniesView()
                case 2: DirectoryView(title: "Healthcare", resource: "Healthcare")
                default: DirectoryView(title: "Finance", resource: "Finance")
                }
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddJobView() }
        }
    }

    // MARK: - Applied

    private var appliedList: some View {
        List {
            if !store.openInvites.isEmpty {
                Section {
                    ForEach(store.openInvites) { invite in
                        VStack(alignment: .leading, spacing: 3) {
                            Label("\(invite.company ?? "Someone") wants to talk — reply today",
                                  systemImage: "bell.badge.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            if let s = invite.subject {
                                Text(s).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Needs your reply")
                }
            }

            statsHeader

            if !store.variantStats.isEmpty {
                Section("Resume variants — what actually gets responses") {
                    ForEach(store.variantStats) { v in
                        HStack {
                            Text(v.resume
                                .replacingOccurrences(of: "Resume - Sylvester Assiamah ", with: "")
                                .replacingOccurrences(of: ".pdf", with: ""))
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer()
                            Text("\(v.sent) sent · \(v.interviews) 🎯 · \(Int(v.response_rate * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !store.ghosts.isEmpty {
                Section("Ghosted 21+ days — follow up or let go") {
                    ForEach(store.ghosts.prefix(10)) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(g.company) — \(g.role)").font(.footnote)
                            Text("\(g.days_silent) days silent").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("My applications") {
                if store.manual.isEmpty {
                    Text("Jobs you apply to by hand go here — tap + to add one, or add from the Fortune 500 tab.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.manualCompanies, id: \.company) { entry in
                    NavigationLink {
                        CompanyJobsList(company: entry.company)
                    } label: {
                        HStack {
                            Text(entry.company).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(entry.count)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.blue.opacity(0.3), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            Section("Auto-applied by Scipio") {
                if store.loadingScipio && store.scipio.isEmpty {
                    ProgressView()
                }
                if let err = store.scipioError {
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(store.scipio.prefix(50)) { run in
                    NavigationLink {
                        ScipioJobDetailView(run: run)
                    } label: {
                        scipioRow(run)
                    }
                }
            }
        }
        .refreshable {
            await store.refreshScipio()
            await store.refreshResume()
            await store.refreshJobsFeed()
            await store.refreshFunnel()
            await store.refreshSalaries()
        }
        .task {
            if store.scipio.isEmpty { await store.refreshScipio() }
            await store.refreshResume()
            if store.jdByURL.isEmpty { await store.refreshJobsFeed() }
            await store.refreshFunnel()
            if store.salaries.isEmpty { await store.refreshSalaries() }
        }
    }

    private var statsHeader: some View {
        Section {
            HStack(spacing: 10) {
                statTile("\(store.manual.count + store.scipio.count)", "Total")
                statTile("\(store.appliedThisWeek)", "This week")
                statTile("\(store.confirmedCount)", "Confirmed")
                statTile("\(store.manual.filter { $0.status == .interviewing }.count)", "Interviews")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func scipioRow(_ run: ScipioRun) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(run.role ?? "Unknown role").font(.subheadline.weight(.semibold))
            Text(run.displayCompany).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Text(run.isConfirmed ? "Submitted" : (run.status ?? "?"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((run.isConfirmed ? Color.green : Color.gray).opacity(0.25), in: Capsule())
                    .foregroundStyle(run.isConfirmed ? Color.green : Color.gray)
                if let ats = run.atsScore {
                    Text("ATS \(ats)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.25), in: Capsule())
                        .foregroundStyle(.purple)
                }
                Text(run.day).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// All my applications at one company.
struct CompanyJobsList: View {
    @EnvironmentObject var store: JobStore
    let company: String

    private var jobs: [ManualJob] {
        store.manual.filter { ($0.company.isEmpty ? "Unknown" : $0.company) == company }
    }

    var body: some View {
        List {
            ForEach(jobs) { job in
                NavigationLink {
                    JobDetailView(job: binding(for: job))
                } label: {
                    jobRow(job)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle(company)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func jobRow(_ job: ManualJob) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.role.isEmpty ? "Untitled role" : job.role)
                .font(.subheadline.weight(.semibold))
            HStack {
                statusChip(job.status.rawValue, color: job.status.color)
                if let odds = job.score?.odds {
                    statusChip("Odds \(odds)%", color: .purple)
                }
            }
        }
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }

    private func delete(_ offsets: IndexSet) {
        let mine = jobs
        for i in offsets {
            store.manual.removeAll { $0.id == mine[i].id }
        }
    }

    private func binding(for job: ManualJob) -> Binding<ManualJob> {
        Binding(
            get: { store.manual.first(where: { $0.id == job.id }) ?? job },
            set: { updated in
                if let idx = store.manual.firstIndex(where: { $0.id == job.id }) {
                    store.manual[idx] = updated
                }
            }
        )
    }
}

struct AddJobView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: JobStore
    @State private var company = ""
    @State private var role = ""
    @State private var url = ""
    @State private var status: JobStatus = .applied
    @State private var jd = ""
    @State private var fetching = false
    @State private var fetchNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Paste the job link — details auto-fill", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        fetchFromLink()
                    } label: {
                        if fetching {
                            HStack { ProgressView(); Text("Reading the posting…") }
                        } else {
                            Label("Fill from link", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(fetching || url.isEmpty)
                    if let note = fetchNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Company", text: $company)
                    TextField("Role / title", text: $role)
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                }
                Section("Job description (for scoring + interview practice)") {
                    TextEditor(text: $jd).frame(minHeight: 120)
                }
            }
            .navigationTitle("Add Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.manual.insert(
                            ManualJob(company: company, role: role, url: url,
                                      status: status, jobDescription: jd),
                            at: 0)
                        dismiss()
                    }
                    .disabled(company.isEmpty && role.isEmpty)
                }
            }
        }
    }

    private func fetchFromLink() {
        fetching = true
        fetchNote = nil
        Task {
            defer { fetching = false }
            let fetched = await JDFetcher.fetch(from: url)
            if let c = fetched.company, company.isEmpty { company = c }
            if let r = fetched.role, role.isEmpty { role = r }
            if let d = fetched.jobDescription, jd.isEmpty { jd = d }
            fetchNote = fetched.jobDescription == nil
                ? "Couldn't read that page (may need JavaScript) — fill the fields by hand."
                : "Filled from the posting — edit anything that looks off."
        }
    }
}

struct JobDetailView: View {
    @EnvironmentObject var engine: InterviewEngine
    @EnvironmentObject var store: JobStore
    @Binding var job: ManualJob
    @State private var scoring = false
    @State private var scoreError: String?
    @State private var dispatching = false
    @State private var dispatchResult: String?
    @State private var refetching = false
    @State private var refetchNote: String?

    var body: some View {
        Form {
            scoreSection

            Section("Job") {
                TextField("Company", text: $job.company)
                TextField("Role", text: $job.role)
                TextField("Link", text: $job.url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Status", selection: $job.status) {
                    ForEach(JobStatus.allCases) { s in Text(s.rawValue).tag(s) }
                }
            }
            Section("Job description") {
                TextEditor(text: $job.jobDescription).frame(minHeight: 120)
                if !job.url.isEmpty {
                    Button {
                        refetchJD()
                    } label: {
                        if refetching {
                            HStack { ProgressView(); Text("Reading the posting…") }
                        } else {
                            Label("Re-fetch clean JD from link", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(refetching)
                    if let note = refetchNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Notes") {
                TextEditor(text: $job.notes).frame(minHeight: 80)
            }
            Section {
                Button {
                    cloudApply()
                } label: {
                    if dispatching {
                        HStack { ProgressView(); Text("Telling Scipio to apply…") }
                    } else {
                        Label("Have Scipio apply (cloud)", systemImage: "paperplane.fill")
                            .font(.headline)
                    }
                }
                .disabled(dispatching || job.url.isEmpty)
                if let r = dispatchResult {
                    Text(r).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(cloudApplyFooter)
            }

            Section {
                Button {
                    engine.prepareInterview(role: job.role, company: job.company,
                                            jobDescription: job.jobDescription)
                } label: {
                    Label("Practice this interview with Victoria", systemImage: "video.fill")
                        .font(.headline)
                }
            }
        }
        .navigationTitle(job.company.isEmpty ? "Job" : job.company)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Honest per-ATS expectation instead of a blanket promise.
    private var cloudApplyFooter: String {
        let base = "Runs in the cloud with a resume tailored to this exact job description — no laptop needed. Check Applied in ~15 minutes for the result and the PDF sent."
        guard let ats = JDFetcher.atsInfo(for: job.url) else { return base }
        return ats.autoSubmit
            ? "\(ats.name) posting — Scipio can fill AND submit this one end-to-end. " + base
            : "\(ats.name) posting — Scipio can't fully auto-submit here yet (needs an account/login flow). It will still tailor a resume and log the attempt; finish the submit from their site if it stalls."
    }

    private func refetchJD() {
        refetching = true
        refetchNote = nil
        Task {
            defer { refetching = false }
            let fetched = await JDFetcher.fetch(from: job.url)
            if let d = fetched.jobDescription, !d.isEmpty {
                job.jobDescription = d
                if let c = fetched.company, job.company.isEmpty { job.company = c }
                if let r = fetched.role, job.role.isEmpty { job.role = r }
                refetchNote = "Clean description pulled from the posting."
            } else {
                refetchNote = "Couldn't read that page (may need JavaScript) — paste the JD by hand."
            }
        }
    }

    private func cloudApply() {
        dispatching = true
        dispatchResult = nil
        Task {
            defer { dispatching = false }
            let result = await ScipioCloud.apply(jobURL: job.url)
            dispatchResult = result.message
            if result.ok {
                job.status = .applied
                job.notes = (job.notes.isEmpty ? "" : job.notes + "\n") + "Sent to Scipio's cloud queue."
            }
        }
    }

    @ViewBuilder
    private var scoreSection: some View {
        Section("Will I get it?") {
            if let score = job.score {
                HStack(spacing: 14) {
                    oddsRing(score.odds, label: "Odds")
                    oddsRing(score.atsScore, label: "ATS")
                    Text(score.verdict).font(.footnote)
                }
                .padding(.vertical, 4)
                if !score.missingKeywords.isEmpty {
                    Text("Missing: " + score.missingKeywords.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(score.fixes, id: \.self) { fix in
                    Label(fix, systemImage: "wrench.adjustable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let reqs = job.score?.requirements, !reqs.isEmpty {
                DisclosureGroup("What this application needs") {
                    ForEach(reqs, id: \.self) { req in
                        Label(req, systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let err = scoreError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Button {
                scoreJob()
            } label: {
                if scoring {
                    HStack { ProgressView(); Text("Scoring against your resume…") }
                } else {
                    Label(job.score == nil ? "Score my chances (ATS)" : "Re-score",
                          systemImage: "gauge.with.needle")
                }
            }
            .disabled(scoring)
        }
    }

    private func oddsRing(_ value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color(white: 0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(value) / 100)
                    .stroke(value >= 70 ? Color.green : (value >= 45 ? .orange : .red),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)").font(.subheadline.bold())
            }
            .frame(width: 52, height: 52)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func scoreJob() {
        scoreError = nil
        guard LLMClient.hasLiveBrain else {
            scoreError = "Add your OpenRouter key in Settings first."
            return
        }
        guard !job.jobDescription.isEmpty else {
            scoreError = "Paste the job description above first."
            return
        }
        guard !store.resumeText.isEmpty else {
            scoreError = "No resume loaded — pull to refresh the Jobs list or paste one in Settings."
            return
        }
        scoring = true
        Task {
            defer { scoring = false }
            do {
                job.score = try await LLMClient.scoreJob(resume: store.resumeText,
                                                         jobDescription: job.jobDescription)
            } catch {
                scoreError = "Scoring failed — free model may be busy, try again."
            }
        }
    }
}
