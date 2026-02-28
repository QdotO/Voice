import SwiftUI

// MARK: - UIViewRepresentable Bridge

struct ASCIICanvasRepresentable: UIViewRepresentable {
    var amplitude: Float
    var mode: AnimationMode

    func makeUIView(context: Context) -> ASCIICanvasView {
        ASCIICanvasView(mode: mode)
    }

    func updateUIView(_ uiView: ASCIICanvasView, context: Context) {
        uiView.amplitude = amplitude
        uiView.mode      = mode
    }
}

// MARK: - Overlay State

/// Which animation mode to show based on app dictation state.
extension AnimationMode {
    static func from(isRecording: Bool, isBusy: Bool) -> AnimationMode {
        // PROCESSING → thinking swirl; LISTENING → fire
        isBusy && !isRecording ? .noise : .fire
    }
}

// MARK: - ASCIIOverlayView

/// Full-screen ASCII animation layer. Sits between the app background and its content cards,
/// appearing when the app is recording or processing (LISTENING / PROCESSING states).
struct ASCIIOverlayView: View {
    var amplitude: Float
    var isRecording: Bool
    var isBusy: Bool

    private var isVisible: Bool { isRecording || isBusy }
    private var mode: AnimationMode { .from(isRecording: isRecording, isBusy: isBusy) }

    var body: some View {
        ASCIICanvasRepresentable(amplitude: amplitude, mode: mode)
            .ignoresSafeArea()
            .opacity(isVisible ? 0.65 : 0)
            // Soft fade in/out — delay entry slightly so audio fires first
            .animation(
                isVisible
                    ? .easeIn(duration: 0.4).delay(0.05)
                    : .easeOut(duration: 0.7),
                value: isVisible
            )
            // Screen blend makes the ASCII glow against the dark purple gradient
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}
