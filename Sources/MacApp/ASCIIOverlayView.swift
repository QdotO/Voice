import SwiftUI

// MARK: - NSViewRepresentable Bridge

struct ASCIICanvasRepresentable: NSViewRepresentable {
    var amplitude: Float
    var mode: AnimationMode

    func makeNSView(context: Context) -> ASCIICanvasView {
        ASCIICanvasView(mode: mode)
    }

    func updateNSView(_ nsView: ASCIICanvasView, context: Context) {
        nsView.amplitude = amplitude
        nsView.mode = mode
    }
}

// MARK: - Mode Resolution

extension AnimationMode {
    static func from(isRecording: Bool, isProcessing: Bool) -> AnimationMode {
        // PROCESSING → thinking noise swirl; LISTENING → fire
        isProcessing && !isRecording ? .noise : .fire
    }
}

// MARK: - ASCIIOverlayView

/// Full-screen ASCII animation overlay for use inside the main window's ZStack.
/// Visible during dictation (fire mode) and transcription processing (noise mode).
struct ASCIIOverlayView: View {
    var amplitude: Float
    var state: DictationState

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    private var isVisible: Bool { isRecording || isProcessing }

    private var mode: AnimationMode {
        .from(isRecording: isRecording, isProcessing: isProcessing)
    }

    var body: some View {
        ASCIICanvasRepresentable(amplitude: amplitude, mode: mode)
            .ignoresSafeArea()
            .opacity(isVisible ? 0.55 : 0)
            .animation(
                isVisible
                    ? .easeIn(duration: 0.4).delay(0.05)
                    : .easeOut(duration: 0.8),
                value: isVisible
            )
            // Screen blend makes the ASCII characters glow over the dark gradient
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}
