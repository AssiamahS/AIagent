import SwiftUI

@main
struct AIagentsApp: App {
    @StateObject private var engine = InterviewEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: InterviewEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch engine.phase {
            case .lobby:
                LobbyView()
            case .connecting, .live:
                InterviewView()
            case .report:
                ReportView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: engine.phase)
    }
}
