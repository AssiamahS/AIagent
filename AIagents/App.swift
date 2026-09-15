import SwiftUI

@main
struct AIagentsApp: App {
    @StateObject private var engine = InterviewEngine()
    @StateObject private var jobs = JobStore()
    @StateObject private var resumes = ResumeStore()

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(engine)
                .environmentObject(jobs)
                .environmentObject(resumes)
                .preferredColorScheme(.dark)
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var engine: InterviewEngine

    var body: some View {
        TabView(selection: $engine.selectedTab) {
            RootView()
                .tabItem { Label("Interview", systemImage: "video.fill") }
                .tag(0)
            JobsView()
                .tabItem { Label("Jobs", systemImage: "briefcase.fill") }
                .tag(1)
            ResumesView()
                .tabItem { Label("Resumes", systemImage: "doc.text.magnifyingglass") }
                .tag(2)
        }
        // Hide the tab bar during the live call so it looks like a real video call.
        .toolbar(engine.phase == .connecting || engine.phase == .live ? .hidden : .visible, for: .tabBar)
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
