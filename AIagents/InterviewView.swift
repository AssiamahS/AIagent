import SwiftUI

/// The live call screen: full-bleed self camera, Victoria bubble,
/// live transcript panel, bottom control bar. Tenzo-style.
struct InterviewView: View {
    @EnvironmentObject var engine: InterviewEngine
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack {
            // Full-screen self view
            if camera.ready {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color(white: 0.1).ignoresSafeArea()
            }

            if engine.phase == .connecting {
                connectingOverlay
            }

            VStack {
                topBar
                Spacer()
                if engine.showTranscript && engine.phase == .live {
                    TranscriptPanel()
                        .frame(maxHeight: 300)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomBar
            }
            .padding(.horizontal, 14)

            // Victoria bubble
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    victoriaBubble
                        .padding(.trailing, 16)
                        .padding(.bottom, engine.showTranscript && engine.phase == .live ? 372 : 96)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.showTranscript)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .overlay(alignment: .top) {
            if let banner = engine.errorBanner {
                Text(banner)
                    .font(.footnote)
                    .padding(10)
                    .background(.orange.opacity(0.9), in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 50)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            engine.errorBanner = nil
                        }
                    }
            }
        }
    }

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Connecting you with your interviewer…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            Spacer()
            Text(engine.candidateName)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var statusColor: Color {
        switch engine.state {
        case .listening: return .green
        case .aiSpeaking: return .blue
        case .thinking: return .orange
        default: return .gray
        }
    }

    private var statusText: String {
        switch engine.state {
        case .listening: return "Listening — your turn"
        case .aiSpeaking: return "Victoria is speaking"
        case .thinking: return "Victoria is thinking…"
        case .ended: return "Interview ended"
        case .idle: return "Connecting.."
        }
    }

    private var victoriaBubble: some View {
        VStack(spacing: 4) {
            ZStack {
                // Speaking pulse ring
                Circle()
                    .stroke(Color.blue.opacity(engine.speaker.isSpeaking ? 0.9 : 0), lineWidth: 3)
                    .frame(width: 76, height: 76)
                    .scaleEffect(engine.speaker.isSpeaking ? 1.15 : 1.0)
                    .animation(engine.speaker.isSpeaking ?
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                        value: engine.speaker.isSpeaking)
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.6),
                                                  Color(red: 0.85, green: 0.55, blue: 0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 66, height: 66)
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("Victoria")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .padding(8)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text("\(engine.clockText)  |  Video Interview")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())

            Spacer()

            if engine.state == .listening {
                Button { engine.finishAnswer() } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.black)
                }
            }

            Button {
                engine.showTranscript.toggle()
            } label: {
                Image(systemName: "text.bubble.fill")
                    .padding(12)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white)
            }

            Button {
                engine.endInterview()
            } label: {
                Label("End Interview", systemImage: "phone.down.fill")
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.bottom, 10)
    }
}
