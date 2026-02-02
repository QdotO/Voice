import SwiftUI
import WhisperShared

@main
struct WhisperiOSApp: App {
    init() {
        SharedStorage.appGroupID = "group.com.quincy.whisper"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
