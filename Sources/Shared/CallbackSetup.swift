import Foundation

public enum CallbackSetup {
    @MainActor
    public static func configure(
        audioCapture: AudioCapture,
        transcriber: Transcriber,
        onAudioError: @escaping @MainActor @Sendable (String) -> Void,
        onAudioLevel: (@MainActor @Sendable (Float) -> Void)? = nil,
        onTranscriberError: @escaping @MainActor @Sendable (String) -> Void,
        onModelLoaded: @escaping @MainActor @Sendable (Bool, String?) -> Void
    ) {
        audioCapture.onError = { error in
            DispatchQueue.main.async {
                onAudioError(error)
            }
        }

        if let onAudioLevel {
            audioCapture.onLevel = { level in
                DispatchQueue.main.async {
                    onAudioLevel(level)
                }
            }
        }

        transcriber.onError = { error in
            DispatchQueue.main.async {
                onTranscriberError(error)
            }
        }

        transcriber.onModelLoaded = { success, error in
            DispatchQueue.main.async {
                onModelLoaded(success, error)
            }
        }
    }
}
