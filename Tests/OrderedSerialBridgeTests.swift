import XCTest

@testable import WhisperShared

final class OrderedSerialBridgeTests: XCTestCase {
    func testReversedCallbackTasksDeliverInSourceOrder() async {
        let delivered = LockedValues<Int>()
        let bridge = OrderedSerialBridge<Int> { value in
            delivered.append(value)
        }

        let firstSequence = bridge.reserveSequence()
        let secondSequence = bridge.reserveSequence()

        let secondTask = Task {
            bridge.enqueue(2, sequence: secondSequence)
        }
        _ = await secondTask.value

        let firstTask = Task {
            bridge.enqueue(1, sequence: firstSequence)
        }
        _ = await firstTask.value

        await bridge.stop(drain: true)
        XCTAssertEqual(delivered.values, [1, 2])
    }

    func testStaleSequenceRejectedAfterDelivery() async {
        let deliveredExpectation = XCTestExpectation(description: "value delivered")
        let delivered = LockedValues<Int>()
        let bridge = OrderedSerialBridge<Int> { value in
            delivered.append(value)
            deliveredExpectation.fulfill()
        }
        let sequence = bridge.reserveSequence()

        XCTAssertTrue(bridge.enqueue(1, sequence: sequence))
        await fulfillment(of: [deliveredExpectation], timeout: 1)

        XCTAssertFalse(bridge.enqueue(99, sequence: sequence))
        await bridge.stop(drain: true)
        XCTAssertEqual(delivered.values, [1])
    }

    func testStopDrainsAcceptedWorkBeforeReturning() async {
        let delivered = LockedValues<Int>()
        let bridge = OrderedSerialBridge<Int> { value in
            delivered.append(value)
        }
        let firstSequence = bridge.reserveSequence()
        let secondSequence = bridge.reserveSequence()

        XCTAssertTrue(bridge.enqueue(2, sequence: secondSequence))
        XCTAssertTrue(bridge.enqueue(1, sequence: firstSequence))

        await bridge.stop(drain: true)
        XCTAssertEqual(delivered.values, [1, 2])
    }

    func testCancellationDropsQueuedWorkAndDoesNotHang() async {
        let started = XCTestExpectation(description: "handler started")
        let delivered = LockedValues<Int>()
        let bridge = OrderedSerialBridge<Int> { value in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(30))
                delivered.append(value)
            } catch {
                // Cancellation must end handler without delivery.
            }
        }

        _ = bridge.enqueue(1)
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(bridge.enqueue(2) != nil)

        await bridge.stop(drain: false)
        XCTAssertEqual(delivered.values, [])
        XCTAssertNil(bridge.enqueue(2))
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
