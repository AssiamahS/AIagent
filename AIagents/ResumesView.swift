import SwiftUI
import WebKit

/// Head-of-HR view of every resume scipio sent: grade, the exact PDF, and a
/// green check / red X from Sylvester that flows back to scipio.
/// Base tab = the sector samples (Finance / Tech / Healthcare) sent when
/// there is no job description to tailor against.
struct ResumesView: View {
    @EnvironmentObject var store: ResumeStore
    @State private var segment = 0
    @State private var filter: String? = nil   // grade filter on the Sent list

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    Text("Sent").tag(0)
                    Text("Base").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 4)

                if segment == 0 { sentList } else { baseList }
            }
            .navigationTitle("Resumes")
            .task { if store.review == nil { await store.refresh() } }
        }
    }

    // MARK: - Sent

    private var sent: [ResumeReview.Sent] {
        let all = store.review?.applications ?? []
        guard let f = filter else { return all }
        if f == "mine-bad" { return all.filter { store.verdicts[$0.id]?.isGood == false } }
        if f == "mine-good" { return all.filter { store.verdicts[$0.id]?.isGood == true } }
        return all.filter { $0.grade == f }
    }

    private var sentList: some View {
        List {
            if let s = store.review?.summary {
                Section {
                    HStack(spacing: 8) {
                        gradeTile("\(s.good)", "Good", "good")
                        gradeTile("\(s.weak)", "Weak", "weak")
                        gradeTile("\(s.junk)", "Junk", "junk")
                        gradeTile("\(s.unknown)", "Unknown", "unknown")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("\(s.jobs_sent) jobs sent (\(s.confirmed) confirmed). Graded against RESUME_RULES + the ATS keyword score. Junk = would be blocked today.")
                }
                Section {
                    HStack(spacing: 8) {
                        mineTile("mine-good", "My ✓", .green)
                        mineTile("mine-bad", "My ✗", .red)
                        if store.pendingCount > 0 {
                            Text("\(store.pendingCount) unsynced")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if let err = store.error {
                Text(err).font(.footnote).foregroundStyle(.secondary)
            }
            if store.loading && store.review == nil {
                ProgressView()
            }

            Section(filter == nil ? "Every resume sent — newest first" : "Filtered: \(sent.count)") {
                ForEach(sent) { row in
                    NavigationLink {
                        SentResumeDetail(row: row)
                    } label: {
                        sentRow(row)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            store.set("bad", for: row.id, resume: row.resume ?? "",
                                      company: row.displayCompany, role: row.role ?? "")
                        } label: { Label("Bad", systemImage: "xmark") }
                        .tint(.red)
                        Button {
                            store.set("good", for: row.id, resume: row.resume ?? "",
                                      company: row.displayCompany, role: row.role ?? "")
                        } label: { Label("Good", systemImage: "checkmark") }
                        .tint(.green)
                    }
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    private func gradeTile(_ value: String, _ label: String, _ grade: String) -> some View {
        let selected = filter == grade
        return Button {
            filter = selected ? nil : grade
        } label: {
            VStack(spacing: 2) {
                Text(value).font(.title3.bold()).foregroundStyle(ResumeGrade.color(grade))
                Text(label).font(.caption2).foregroundStyle(selected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? ResumeGrade.color(grade).opacity(0.35) : Color(white: 0.12),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func mineTile(_ key: String, _ label: String, _ color: Color) -> some View {
        let selected = filter == key
        let count = store.verdicts.values.filter { key == "mine-good" ? $0.isGood : !$0.isGood }.count
        return Button {
            filter = selected ? nil : key
        } label: {
            Text("\(label) \(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? color.opacity(0.4) : color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func sentRow(_ row: ResumeReview.Sent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ResumeGrade.icon(row.grade))
                .foregroundStyle(ResumeGrade.color(row.grade))
                .font(.title3)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.role ?? "Unknown role").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(row.displayCompany).font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    pill(ResumeGrade.label(row.grade), ResumeGrade.color(row.grade))
                    if let ats = row.ats_score { pill("ATS \(ats)", .purple) }
                    if row.confirmed == true { pill("Confirmed", .blue) }
                    Text(row.day ?? "").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(row.resumeShort).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            verdictMark(row.id)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func verdictMark(_ id: String) -> some View {
        if let v = store.verdicts[id] {
            Image(systemName: v.isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(v.isGood ? .green : .red)
                .font(.title2)
                .opacity(v.synced ? 1 : 0.5)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Base

    private var featured: [ResumeReview.Base] { (store.review?.base ?? []).filter { $0.featured == true } }
    private var others: [ResumeReview.Base] { (store.review?.base ?? []).filter { $0.featured != true } }

    private var baseList: some View {
        List {
            Section {
                ForEach(featured) { b in
                    NavigationLink { BaseResumeDetail(base: b) } label: { baseCard(b) }
                }
            } header: {
                Text("No job description? These three go out")
            } footer: {
                Text("One clean sample per sector. Everything scipio tailors starts from one of these; a ✗ here changes the bank, not just one application.")
            }
            if !others.isEmpty {
                Section("Other variants") {
                    ForEach(others) { b in
                        NavigationLink { BaseResumeDetail(base: b) } label: { baseCard(b) }
                    }
                }
            }
            if store.review == nil {
                if let err = store.error { Text(err).font(.footnote).foregroundStyle(.secondary) }
                else { ProgressView() }
            }
        }
        .refreshable { await store.refresh() }
    }

    private func baseCard(_ b: ResumeReview.Base) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sectorIcon(b.key))
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(b.title).font(.headline)
                if let blurb = b.blurb { Text(blurb).font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    pill(b.grade == "good" ? "Passes rules" : "Fails rules", ResumeGrade.color(b.grade))
                    if let w = b.words { pill("\(w) words", .gray) }
                    if let n = b.sent, n > 0 { pill("sent \(n)×", .blue) }
                }
            }
            Spacer(minLength: 0)
            verdictMark(b.key)
        }
        .padding(.vertical, 4)
    }

    private func sectorIcon(_ key: String) -> String {
        switch key {
        case "finance": return "dollarsign.circle"
        case "tech": return "desktopcomputer"
        case "healthcare": return "cross.case"
        default: return "doc.text"
        }
    }
}

// MARK: - Verdict controls (shared)

/// Green check / red X row. A ✗ asks for one line on why — that line is what
/// the next tailor/bank change is built from.
struct VerdictBar: View {
    @EnvironmentObject var store: ResumeStore
    let id: String
    let resume: String
    let company: String
    let role: String
    @State private var askReason = false
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    store.set("good", for: id, resume: resume, company: company, role: role)
                } label: {
                    Label("Good", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(current?.isGood == true ? Color.green.opacity(0.45) : Color.green.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                Button {
                    reason = current?.isGood == false ? (current?.reason ?? "") : ""
                    askReason = true
                } label: {
                    Label("Bad", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(current?.isGood == false ? Color.red.opacity(0.45) : Color.red.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            if let v = current {
                HStack {
                    Text(v.isGood ? "You marked this good" : "You marked this bad" + (v.reason.isEmpty ? "" : ": \(v.reason)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(v.synced ? "synced" : "saving…").font(.caption2).foregroundStyle(.tertiary)
                    Button("Clear") { store.clear(id) }.font(.caption)
                }
            }
        }
        .alert("What's wrong with it?", isPresented: $askReason) {
            TextField("e.g. wrong title, missing Epic, reads fake", text: $reason)
            Button("Mark bad") {
                store.set("bad", for: id, reason: reason, resume: resume, company: company, role: role)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One line is enough. Scipio reads it before the next tailor change.")
        }
    }

    private var current: ResumeVerdict? { store.verdicts[id] }
}

// MARK: - Detail views

struct SentResumeDetail: View {
    @EnvironmentObject var store: ResumeStore
    @EnvironmentObject var engine: InterviewEngine
    let row: ResumeReview.Sent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.role ?? "Unknown role").font(.headline)
                    Text(row.displayCompany).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Label(ResumeGrade.label(row.grade), systemImage: ResumeGrade.icon(row.grade))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ResumeGrade.color(row.grade))
                        Text("·").foregroundStyle(.tertiary)
                        Text(row.day ?? "").font(.caption).foregroundStyle(.tertiary)
                        if row.confirmed == true {
                            Text("· confirmed").font(.caption).foregroundStyle(.blue)
                        }
                    }
                }
            }

            Section("Your call") {
                VerdictBar(id: row.id, resume: row.resume ?? "", company: row.displayCompany, role: row.role ?? "")
            }

            Section("Why scipio graded it \(ResumeGrade.label(row.grade).lowercased())") {
                ForEach(row.reasons ?? [], id: \.self) { r in
                    Label(r, systemImage: "info.circle").font(.footnote)
                }
            }

            if let missing = row.ats_missing, !missing.isEmpty {
                Section("JD keywords the resume was missing") {
                    FlowChips(words: missing, color: .orange)
                }
            }

            Section("The exact PDF sent") {
                if let pdf = row.pdfURL {
                    PDFPane(url: pdf)
                        .frame(height: 520)
                        .listRowInsets(EdgeInsets())
                    ShareLink(item: pdf) { Label("Share / open PDF", systemImage: "square.and.arrow.up") }
                } else {
                    Text(row.resume == nil
                         ? "Scipio never recorded which resume went out for this one."
                         : "PDF not published for \(row.resumeShort).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                if let u = row.url, let url = URL(string: u) {
                    Link(destination: url) { Label("View job posting", systemImage: "link") }
                }
                Button {
                    engine.prepareInterview(role: row.role ?? "", company: row.displayCompany, jobDescription: "")
                } label: {
                    Label("Practice this interview with Victoria", systemImage: "video.fill")
                }
            }
        }
        .navigationTitle(row.displayCompany)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BaseResumeDetail: View {
    @EnvironmentObject var store: ResumeStore
    let base: ResumeReview.Base

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(base.title).font(.title2.bold())
                    if let blurb = base.blurb { Text(blurb).font(.subheadline).foregroundStyle(.secondary) }
                    if let s = base.summary, !s.isEmpty {
                        Text(s).font(.footnote).padding(.top, 4)
                    }
                }
            }
            Section("Your call") {
                VerdictBar(id: base.key, resume: base.title, company: "base", role: base.title)
            }
            Section("Rules check") {
                ForEach(base.reasons ?? [], id: \.self) { r in
                    Label(r, systemImage: base.grade == "good" ? "checkmark.circle" : "xmark.circle")
                        .font(.footnote)
                        .foregroundStyle(base.grade == "good" ? .green : .red)
                }
            }
            Section("The PDF") {
                if let pdf = base.pdfURL {
                    PDFPane(url: pdf)
                        .frame(height: 560)
                        .listRowInsets(EdgeInsets())
                    ShareLink(item: pdf) { Label("Share / send this resume", systemImage: "square.and.arrow.up") }
                } else {
                    Text("PDF not published yet.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(base.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Renders a remote PDF inline (WKWebView handles PDFs natively).
struct PDFPane: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url != url {
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }
}
