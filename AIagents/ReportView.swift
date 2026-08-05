import SwiftUI

/// Post-interview feedback report card.
struct ReportView: View {
    @EnvironmentObject var engine: InterviewEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let report = engine.report {
                    Text("Interview Complete")
                        .font(.largeTitle.bold())
                        .padding(.top, 30)
                    Text(engine.roleTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    overallRing(report)

                    HStack(spacing: 12) {
                        scoreTile("Communication", report.communication)
                        scoreTile("Content", report.content)
                        scoreTile("Confidence", report.confidence)
                    }

                    section("What went well", items: report.strengths, icon: "checkmark.circle.fill", tint: .green)
                    section("What to improve", items: report.improvements, icon: "arrow.up.circle.fill", tint: .orange)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.subheadline.bold())
                        Text(report.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16))

                    transcriptSection

                    Button {
                        engine.backToLobby()
                    } label: {
                        Text("Practice Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 6)
                } else {
                    ProgressView("Victoria is writing your feedback…")
                        .padding(.top, 120)
                }
            }
            .padding(20)
        }
    }

    private func overallRing(_ report: InterviewReport) -> some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(report.overall) / 10.0)
                .stroke(LinearGradient(colors: [.blue, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack {
                Text("\(report.overall)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("out of 10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
    }

    private func scoreTile(_ title: String, _ score: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(score)")
                .font(.title2.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func section(_ title: String, items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: icon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .tint(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var transcriptSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(engine.turns) { turn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(turn.speaker == .interviewer ? "Victoria" : engine.candidateName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(turn.speaker == .interviewer ? Color.blue : Color.green)
                        Text(turn.text)
                            .font(.footnote)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Full transcript")
                .font(.subheadline.bold())
        }
        .padding(16)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}
