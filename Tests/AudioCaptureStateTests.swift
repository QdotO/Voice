import Dispatch
import XCTest

@testable import WhisperShared

final class AudioCaptureStateTests: XCTestCase {
    func testRecordAndDrainAreLockedAndPreserveSamples() {
        let state = AudioCaptureState()
        let deliveredLevel = LockedSnapshot<Float?>(nil)
        state.setLevelHandler { deliveredLevel.replace(with: $0) }

        let result = state.record(samples: [0.1, 0.2], level: 0.5)
        result.1?(result.0)

        XCTAssertEqual(state.drainAudio(), [0.1, 0.2])
        XCTAssertEqual(deliveredLevel.read() ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertEqual(state.drainAudio(), [])
    }

    func testConcurrentRecordingAndDrainingDoNotCorruptState() {
        let state = AudioCaptureState()

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = state.record(samples: [1], level: 1)
            _ = state.drainAudio()
        }

        XCTAssertTrue(state.drainAudio().allSatisfy { $0 == 1 })
    }
}
