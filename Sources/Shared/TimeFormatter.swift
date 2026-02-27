import Foundation

public enum TimeFormatter {
    public static func formatDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
