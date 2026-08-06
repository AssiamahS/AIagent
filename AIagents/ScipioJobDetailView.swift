import SwiftUI

/// Everything scipio recorded about one auto-application:
/// scores, missing ATS keywords, the exact resume PDF sent.
struct ScipioJobDetailView: View {
    @EnvironmentObject var engine: InterviewEngine
    @EnvironmentObject var store: JobStore
    let run: ScipioRun

    private var jobDescription: String {
        guard let u = run.url else { return "" }
        return store.jdByURL[u] ?? ""
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.role ?? "Unknown role").font(.headline)
                    Text(run.displayCompany).font(.subheadline).foregroundStyle(.secondary)
                    Text(run.day).font(.caption).foregroundStyle(.tertiary)
                }
            }

            Section("Will I get it?") {
                HStack(spacing: 12) {
                    scoreRing(value: run.atsScore, max: 100, label: "ATS")
                    scoreRing(value: run.matchScore, max: 10, label: "Match")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.verdict).font(.subheadline.bold())
                        if let reason = run.details?.match_reason, !reason.isEmpty, reason != "Could not score" {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if let missing = run.details?.ats_missing, !missing.isEmpty {
                Section("ATS keywords the resume was missing") {
                    keywordWrap(missing, color: .orange)
                }
            }

            if let matching = run.details?.matching_skills, !matching.isEmpty {
                Section("Matched skills") {
                    keywordWrap(matching, color: .green)
                }
            }

            Section("Resume sent") {
                if let pdf = run.resumePDFURL {
                    Link(destination: pdf) {
                        Label(run.details?.resume ?? "Resume.pdf", systemImage: "doc.richtext")
                    }
                } else {
                    Text("Not recorded").foregroundStyle(.secondary)
                }
            }

            if !jobDescription.isEmpty {
                Section("Job description it was sent against") {
                    Text(jobDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                }
            }

            Section {
                if let urlString = run.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("View job posting", systemImage: "link")
                    }
                }
                Button {
                    engine.prepareInterview(role: run.role ?? "",
                                            company: run.displayCompany,
                                            jobDescription: jobDescription)
                } label: {
                    Label("Practice this interview with Victoria", systemImage: "video.fill")
                }
            }
        }
        .navigationTitle(run.displayCompany)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scoreRing(value: Int?, max maxValue: Int, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color(white: 0.18), lineWidth: 6)
                if let v = value {
                    Circle()
                        .trim(from: 0, to: CGFloat(v) / CGFloat(maxValue))
                        .stroke(ringColor(v, maxValue), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(v)").font(.subheadline.bold())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func ringColor(_ v: Int, _ maxValue: Int) -> Color {
        let pct = Double(v) / Double(maxValue)
        if pct >= 0.7 { return .green }
        if pct >= 0.5 { return .orange }
        return .red
    }

    private func keywordWrap(_ words: [String], color: Color) -> some View {
        FlowChips(words: words, color: color)
    }
}

/// Simple wrapping chip layout for keyword lists.
struct FlowChips: View {
    let words: [String]
    let color: Color

    var body: some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(words, id: \.self) { word in
                    chip(word)
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width {
                                width = 0; height -= d.height + 8
                            }
                            let result = width
                            width = word == words.last ? 0 : width - d.width - 8
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if word == words.last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(minHeight: CGFloat((words.count / 3 + 1)) * 34)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
