import SwiftUI

/// The place for every job applied to: manual entries + Scipio's auto-applies.
struct JobsView: View {
    @EnvironmentObject var engine: InterviewEngine
    @EnvironmentObject var store: JobStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                statsHeader

                Section("My applications") {
                    if store.manual.isEmpty {
                        Text("Jobs you apply to by hand go here — tap + to add one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.manual) { job in
                        NavigationLink {
                            JobDetailView(job: binding(for: job))
                        } label: {
                            manualRow(job)
                        }
                    }
                    .onDelete { store.manual.remove(atOffsets: $0) }
                }

                Section("Auto-applied by Scipio") {
                    if store.loadingScipio && store.scipio.isEmpty {
                        ProgressView()
                    }
                    if let err = store.scipioError {
                        Text(err).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(store.scipio.prefix(50)) { run in
                        scipioRow(run)
                    }
                }
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddJobView() }
            .refreshable { await store.refreshScipio() }
            .task { if store.scipio.isEmpty { await store.refreshScipio() } }
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

    private func manualRow(_ job: ManualJob) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.role).font(.subheadline.weight(.semibold))
            Text(job.company).font(.footnote).foregroundStyle(.secondary)
            Text(job.status.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(job.status.color.opacity(0.25), in: Capsule())
                .foregroundStyle(job.status.color)
        }
        .padding(.vertical, 2)
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
                Text(run.day).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Company", text: $company)
                    TextField("Role / title", text: $role)
                    TextField("Link (optional)", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                }
                Section("Job description (for interview practice)") {
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
}

struct JobDetailView: View {
    @EnvironmentObject var engine: InterviewEngine
    @Binding var job: ManualJob

    var body: some View {
        Form {
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
            }
            Section("Notes") {
                TextEditor(text: $job.notes).frame(minHeight: 80)
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
}
