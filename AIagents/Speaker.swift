import Foundation
import AVFoundation

/// Voice output for Victoria. Uses ElevenLabs when a key is set (studio quality),
/// otherwise the free on-device AVSpeechSynthesizer.
final class Speaker: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    private var elevenKey: String {
        UserDefaults.standard.string(forKey: "elevenLabsKey") ?? ""
    }

    func speak(_ text: String, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        isSpeaking = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio,
                                 options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)

        if !elevenKey.isEmpty {
            Task { [weak self] in
                await self?.speakElevenLabs(text)
            }
        } else {
            speakOnDevice(text)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        isSpeaking = false
        onFinish = nil
    }

    private func speakOnDevice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Prefer an enhanced US female voice when installed.
        let preferred = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language == "en-US" && $0.gender == .female && $0.quality != .default
        } ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.voice = preferred
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }

    // MARK: - ElevenLabs

    private func speakElevenLabs(_ text: String) async {
        // "Rachel" — default professional female voice.
        let voiceId = UserDefaults.standard.string(forKey: "elevenLabsVoiceId").flatMap { $0.isEmpty ? nil : $0 } ?? "21m00Tcm4TlvDq8ikWAM"
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!)
        request.httpMethod = "POST"
        request.setValue(elevenKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "Speaker", code: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            await MainActor.run {
                do {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    self.player = player
                    player.play()
                } catch {
                    self.speakOnDevice(text)   // fall back if audio data is unplayable
                }
            }
        } catch {
            await MainActor.run { self.speakOnDevice(text) }  // quota/network → free voice
        }
    }

    private func finished() {
        DispatchQueue.main.async {
            self.isSpeaking = false
            let cb = self.onFinish
            self.onFinish = nil
            cb?()
        }
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished()
    }
}

extension Speaker: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finished()
    }
}
