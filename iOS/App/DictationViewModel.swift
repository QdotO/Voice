import Foundation
import WhisperShared

@MainActor
final class DictationViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var lastTranscript = ""
    @Published var errorMessage = ""
    @Published var stateLabel = "Loading model"

    private let audioCapture = AudioCapture()
    private let transcriber = Transcriber()
    private var transcriptionTask: Task<Void, Never>?

    init() {
        setupCallbacks()
        requestPermissionsAndLoad()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func setupCallbacks() {
        audioCapture.onError = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error
            }
        }

        transcriber.onError = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error
            }
        }

        transcriber.onModelLoaded = { [weak self] success, error in
            Task { @MainActor in
                if success {
                    self?.stateLabel = "Ready"
                } else {
                    self?.stateLabel = error ?? "Model error"
                }
            }
        }
    }

    private func requestPermissionsAndLoad() {
        Task {
            let granted = await audioCapture.requestPermission()
            await MainActor.run {
                if !granted {
                    errorMessage = "Microphone access denied"
                }
            }
            await transcriber.loadModel("base.en")
        }
    }

    private func startRecording() {
        guard !isBusy else { return }
        errorMessage = ""

        do {
            try audioCapture.start()
            isRecording = true
            stateLabel = "Listening"
        } catch {
            errorMessage = error.localizedDescription
            stateLabel = "Error"
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isBusy = true
        stateLabel = "Processing"

        let audio = audioCapture.stop()
        guard audio.count >= 8000 else {
            lastTranscript = "(too short)"
            isBusy = false
            stateLabel = "Ready"
            return
        }

        transcriptionTask?.cancel()
        transcriptionTask = Task { [audio] in
            guard let payload = await transcriber.transcribe(audio) else {
                await MainActor.run {
                    self.lastTranscript = "(no speech detected)"
                    self.isBusy = false
                    self.stateLabel = "Ready"
                }
                return
            }

            let finalText = CorrectionEngine.shared.apply(to: payload.text)
            await MainActor.run {
                self.lastTranscript = finalText
                self.isBusy = false
                self.stateLabel = "Ready"
            }
        }
    }
}
