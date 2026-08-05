import Foundation
import AVFoundation
import Speech

/// Live speech-to-text with a published partial transcript and mic level.
final class SpeechManager: NSObject, ObservableObject {
    @Published var liveTranscript: String = ""
    @Published var micLevel: CGFloat = 0          // 0...1, for the pulse animation
    @Published var authorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var lastTranscriptChange = Date()

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { self.authorized = (status == .authorized) }
        }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func startListening() throws {
        stopListening()
        liveTranscript = ""
        lastTranscriptChange = Date()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.audioEngine = engine
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            // RMS mic level for UI
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames { sum += data[i] * data[i] }
            let rms = frames > 0 ? sqrt(sum / Float(frames)) : 0
            let level = CGFloat(min(1.0, rms * 12))
            DispatchQueue.main.async { self?.micLevel = level }
        }

        engine.prepare()
        try engine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            DispatchQueue.main.async {
                if text != self.liveTranscript {
                    self.liveTranscript = text
                    self.lastTranscriptChange = Date()
                }
            }
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        DispatchQueue.main.async { self.micLevel = 0 }
    }
}
