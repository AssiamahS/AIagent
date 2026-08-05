import SwiftUI

/// Pre-interview lobby: camera check, mic test, role pick, Start Interview.
struct LobbyView: View {
    @EnvironmentObject var engine: InterviewEngine
    @StateObject private var camera = CameraController()
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                // Camera preview card
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(white: 0.13))
                    if camera.ready {
                        CameraPreview(session: camera.session)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Connecting to device media sources…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Text(engine.candidateName)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.6), in: Capsule())
                            Spacer()
                        }
                        .padding(12)
                    }
                }
                .frame(height: 300)

                micTest

                rolePicker

                Button {
                    engine.startInterview()
                } label: {
                    Text("Start Interview")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [Color(red: 0.29, green: 0.44, blue: 1.0),
                                                    Color(red: 0.2, green: 0.6, blue: 1.0)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)

                tips
            }
            .padding(20)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            camera.start()
            engine.speech.requestPermissions()
        }
        .onDisappear { camera.stop() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2).padding(6))
                Text("A.I.agents")
                    .font(.title3.bold())
                Text("Interview powered by AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var micTest: some View {
        VStack(spacing: 10) {
            avatarCircle
            Text("Victoria is waiting")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Test your microphone")
                .font(.title2.bold())
            Text("Start speaking and make sure the circle animates with your voice")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 90, height: 90)
                    .scaleEffect(1 + engine.speech.micLevel * 0.5)
                    .animation(.easeOut(duration: 0.12), value: engine.speech.micLevel)
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .offset(y: engine.speech.micLevel > CGFloat(i) * 0.2 ? -4 : 0)
                    }
                }
            }
            .padding(.top, 6)
            .onAppear { try? engine.speech.startListening() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 20))
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.6),
                                              Color(red: 0.9, green: 0.6, blue: 0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "person.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 72, height: 72)
        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 2))
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interviewing for")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(RolePreset.all) { role in
                        Button {
                            engine.roleId = role.id
                            engine.roleTitle = role.title
                            engine.jobContext = ""   // preset picked → drop job-specific JD
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: role.icon)
                                Text(role.title)
                            }
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(engine.roleId == role.id ? Color.blue : Color(white: 0.15),
                                        in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tips for a successful AI Interview")
                .font(.subheadline.weight(.semibold))
            Label("Find a quiet place with minimal background noise.", systemImage: "checkmark.circle.fill")
            Label("Speak naturally — Victoria waits for you to finish.", systemImage: "checkmark.circle.fill")
            Label("Answers of 45–90 seconds score best.", systemImage: "checkmark.circle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}
