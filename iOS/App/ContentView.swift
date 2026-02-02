import SwiftUI
import WhisperShared

struct ContentView: View {
    @StateObject private var viewModel = DictationViewModel()

    var body: some View {
        ZStack {
            background

            VStack(spacing: 20) {
                header
                dictationCard
                statusCard
                Spacer()
            }
            .padding(24)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.05, blue: 0.14),
                Color(red: 0.08, green: 0.08, blue: 0.22),
                Color(red: 0.1, green: 0.15, blue: 0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Whisper")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("System-wide dictation lives in the keyboard. This app is your control center.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dictationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Magic Wand")
                    .font(.headline)
                Spacer()
                Text(viewModel.stateLabel)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Button(action: viewModel.toggleRecording) {
                HStack {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "wand.and.stars")
                    Text(viewModel.isRecording ? "Stop Dictation" : "Start Dictation")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.isBusy)

            Text("Use the keyboard extension for system-wide typing.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(18)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Transcript")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))

            ScrollView {
                Text(viewModel.lastTranscript)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)

            HStack {
                Button("Copy") {
                    UIPasteboard.general.string = viewModel.lastTranscript
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.lastTranscript.isEmpty)

                Spacer()

                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
