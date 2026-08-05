import SwiftUI

/// Live transcript side panel — chat bubbles plus the in-progress answer.
struct TranscriptPanel: View {
    @EnvironmentObject var engine: InterviewEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Transcript")
                    .font(.subheadline.bold())
                Spacer()
                Button { engine.showTranscript = false } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if engine.turns.isEmpty {
                            Text("Interview questions will appear in this chat window.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
                        }
                        ForEach(engine.turns) { turn in
                            bubble(turn)
                                .id(turn.id)
                        }
                        if engine.state == .listening && !engine.speech.liveTranscript.isEmpty {
                            bubble(Turn(speaker: .candidate, text: engine.speech.liveTranscript))
                                .opacity(0.7)
                                .id("live")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .onChange(of: engine.turns.count) { _, _ in
                    withAnimation { proxy.scrollTo(engine.turns.last?.id, anchor: .bottom) }
                }
                .onChange(of: engine.speech.liveTranscript) { _, _ in
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bubble(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(turn.speaker == .interviewer ? "Victoria" : engine.candidateName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(turn.speaker == .interviewer ? Color.blue : Color.green)
            Text(turn.text)
                .font(.footnote)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: turn.speaker == .interviewer ? 0.16 : 0.12),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
