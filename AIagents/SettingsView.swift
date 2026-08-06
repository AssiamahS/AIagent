import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("candidateName") private var candidateName = "Candidate"
    @AppStorage("openRouterKey") private var openRouterKey = ""
    @AppStorage("githubPAT") private var githubPAT = ""
    @AppStorage("openRouterModel") private var openRouterModel = ""
    @AppStorage("elevenLabsKey") private var elevenKey = ""
    @AppStorage("elevenLabsVoiceId") private var elevenVoice = ""
    @AppStorage("resumeText") private var resumeText = ""
    @AppStorage("resumeTextEdited") private var resumeEdited = false

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $candidateName)
                }

                Section {
                    SecureField("OpenRouter API key (sk-or-…)", text: $openRouterKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model (blank = free Gemma)", text: $openRouterModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("AI Brain — OpenRouter (free)")
                } footer: {
                    Text("Free adaptive questions + real scoring via OpenRouter's free models (default: google/gemma-4-26b-a4b-it:free). Get a key at openrouter.ai. Without it, the app uses a built-in question bank.")
                }

                Section {
                    SecureField("GitHub token (repo+actions on scipio)", text: $githubPAT)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Cloud apply — Scipio")
                } footer: {
                    Text("Lets the app tell Scipio to apply to a job from the cloud. Fine-grained token at github.com/settings/personal-access-tokens scoped to AssiamahS/scipio with Actions read-write.")
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
                    TextEditor(text: $resumeText)
                        .frame(minHeight: 140)
                        .font(.footnote)
                        .onChange(of: resumeText) { _, _ in resumeEdited = true }
                    if resumeEdited {
                        Button("Reset to auto-synced resume") {
                            resumeEdited = false
                            resumeText = ""
                        }
                    }
                } header: {
                    Text("My resume (used for job scoring)")
                } footer: {
                    Text("Auto-synced from your Scipio site. Edit here to override; scoring compares this text against each job description.")
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
