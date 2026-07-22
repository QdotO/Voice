import Foundation

/// Synchronously mutates and reads one immutable-value snapshot under a lock.
///
/// Callers receive value copies, so async consumers never retain mutable store state.
/// `@unchecked Sendable` is valid here because `value` is the only mutable field,
/// `Value` is `Sendable`, and every access to `value` holds `lock`.
final class LockedSnapshot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func replace(with value: Value) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func asyncSnapshot() async -> Value {
        read()
    }
}
