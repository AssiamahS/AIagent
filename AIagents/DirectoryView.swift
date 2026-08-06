import SwiftUI

/// One employer in a bundled sector directory (Healthcare.json / Finance.json).
/// Healthcare = every CMS-registered East Coast hospital; Finance = every
/// active East Coast FDIC institution, largest assets first.
struct DirectoryCompany: Identifiable, Codable, Hashable {
    let name: String
    let city: String
    let state: String
    let type: String
    let ownership: String?

    var id: String { name + city + state }

    var careersURL: URL {
        let q = "\(name) \(state) careers jobs".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://www.google.com/search?q=\(q)")!
    }

    static func load(resource: String) -> [DirectoryCompany] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([DirectoryCompany].self, from: data)
        else { return [] }
        return list
    }
}

/// East Coast sector directory: filter by state, search, tap → paste a job
/// link and the JD fetcher fills the rest.
struct DirectoryView: View {
    @EnvironmentObject var store: JobStore
    let title: String
    let resource: String

    @State private var companies: [DirectoryCompany] = []
    @State private var search = ""
    @State private var state = "All states"

    private var states: [String] {
        ["All states"] + Array(Set(companies.map { $0.state })).sorted()
    }

    private var filtered: [DirectoryCompany] {
        companies.filter { c in
            (state == "All states" || c.state == state) &&
            (search.isEmpty || c.name.localizedCaseInsensitiveContains(search)
                || c.city.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("State", selection: $state) {
                    ForEach(states, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
            }
            Section("\(title) — \(filtered.count) East Coast employers") {
                ForEach(filtered.prefix(300)) { company in
                    NavigationLink {
                        DirectoryDetailView(company: company)
                    } label: {
                        row(company)
                    }
                }
                if filtered.count > 300 {
                    Text("Showing 300 — narrow by state or search to see the rest.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $search, prompt: "Name or city")
        .onAppear { if companies.isEmpty { companies = DirectoryCompany.load(resource: resource) } }
    }

    private func row(_ company: DirectoryCompany) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(company.city), \(company.state) · \(company.type)")
                    .font(.caption).foregroundStyle(.secondary)
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

struct DirectoryDetailView: View {
    @EnvironmentObject var store: JobStore
    let company: DirectoryCompany

    @State private var jobLink = ""
    @State private var fetching = false
    @State private var fetchError: String?
    @State private var savedJob = false

    var body: some View {
        List {
            Section {
                LabeledContent("Location", value: "\(company.city), \(company.state)")
                LabeledContent("Type", value: company.type)
                if let o = company.ownership {
                    LabeledContent(company.type == "Bank" ? "Size" : "Ownership", value: o)
                }
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
                            Text(job.role.isEmpty ? "Untitled role" : job.role).font(.subheadline)
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
            let fetched = await JDFetcher.fetch(from: jobLink)
            let jd = fetched.jobDescription ?? ""
            if jd.isEmpty {
                fetchError = "Couldn't extract the description (site may need JavaScript) — job saved anyway, paste the JD in its page."
            }
            store.manual.insert(
                ManualJob(company: fetched.company ?? company.name,
                          role: fetched.role ?? "",
                          url: jobLink, status: .applied, jobDescription: jd),
                at: 0)
            savedJob = true
        }
    }
}
