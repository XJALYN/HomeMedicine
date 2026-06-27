import AVFoundation
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private let locale: Locale

    init(locale: Locale) {
        self.locale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording(onTranscript: @escaping (String) -> Void) async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = L10n.t("voice.unavailable", locale: locale)
            return
        }

        guard await requestAuthorization() else {
            errorMessage = L10n.t("voice.permission_denied", locale: locale)
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        stopRecording()

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            if let result {
                Task { @MainActor in
                    onTranscript(result.bestTranscription.formattedString)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            stopRecording()
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
