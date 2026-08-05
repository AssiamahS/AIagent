import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("candidateName") private var candidateName = "Candidate"
    @AppStorage("githubModelsToken") private var githubToken = ""
    @AppStorage("elevenLabsKey") private var elevenKey = ""
    @AppStorage("elevenLabsVoiceId") private var elevenVoice = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $candidateName)
                }

                Section {
                    SecureField("GitHub token (models:read)", text: $githubToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("AI Brain — GitHub Models (free)")
                } footer: {
                    Text("Free adaptive questions + real scoring. Create a fine-grained token at github.com/settings/tokens with the Models permission. Without it, the app uses a built-in question bank.")
                }

                Section {
                    SecureField("ElevenLabs API key (optional)", text: $elevenKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Voice ID (blank = Rachel)", text: $elevenVoice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Voice — ElevenLabs (optional)")
                } footer: {
                    Text("Studio-quality voice for Victoria. Free tier at elevenlabs.io. Without a key, the built-in iOS voice is used.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
