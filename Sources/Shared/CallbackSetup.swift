import Foundation

public enum CallbackSetup {
    public static func configure(
        audioCapture: AudioCapture,
        transcriber: Transcriber,
        onAudioError: @escaping (String) -> Void,
        onAudioLevel: ((Float) -> Void)? = nil,
        onTranscriberError: @escaping (String) -> Void,
        onModelLoaded: @escaping (Bool, String?) -> Void
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
