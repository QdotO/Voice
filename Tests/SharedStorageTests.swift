import Foundation
import XCTest

@testable import WhisperShared

final class SharedStorageTests: XCTestCase {
    private static let stateLock = ExclusiveTestLock()

    override func setUp() {
        super.setUp()
        Self.stateLock.lock()
        SharedStorage.appGroupID = nil
    }

    override func tearDown() {
        SharedStorage.appGroupID = nil
        Self.stateLock.unlock()
        super.tearDown()
    }

    func testAppGroupIDSupportsConcurrentReadsAndWrites() {
        let observations = LockedValues<String?>()

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            if index.isMultiple(of: 2) {
                SharedStorage.appGroupID = "group.test.\(index)"
            } else {
                SharedStorage.appGroupID = nil
            }

            observations.append(SharedStorage.appGroupID)
        }

        XCTAssertEqual(observations.count, 1_000)
        XCTAssertTrue(
            observations.values.allSatisfy { value in
                value == nil || value?.hasPrefix("group.test.") == true
            }
        )
    }

    func testNilAppGroupIDUsesApplicationSupportFallback() {
        let expected = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        XCTAssertNil(SharedStorage.appGroupID)
        XCTAssertEqual(SharedStorage.baseDirectory(), expected)
    }
}

private final class ExclusiveTestLock: @unchecked Sendable {
    private let mutex = NSLock()

    func lock() {
        mutex.lock()
    }

    func unlock() {
        mutex.unlock()
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

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
