import Foundation

/// Serializes source-sequenced values and drains them in source order.
///
/// Sequence reservation happens synchronously at the callback boundary. This
/// keeps callback order independent from later task scheduling.
final class OrderedSerialBridge<Element: Sendable>: @unchecked Sendable {
    typealias Handler = @Sendable (Element) async -> Void

    private struct Entry: Sendable {
        let sequence: UInt64
        let element: Element
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        let continuation: AsyncStream<Entry>.Continuation
        var nextReservedSequence: UInt64 = 0
        var lastDeliveredSequence: UInt64 = 0
        var acceptedSequences: Set<UInt64> = []
        var isTerminal = false
        var isCancelled = false

        init(continuation: AsyncStream<Entry>.Continuation) {
            self.continuation = continuation
        }

        func reserveSequence() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            nextReservedSequence &+= 1
            return nextReservedSequence
        }

        func accept(_ entry: Entry) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !isTerminal,
                  entry.sequence > lastDeliveredSequence,
                  acceptedSequences.insert(entry.sequence).inserted else {
                return false
            }

            nextReservedSequence = max(nextReservedSequence, entry.sequence)
            continuation.yield(entry)
            return true
        }

        func markDelivered(_ sequence: UInt64) {
            lock.lock()
            acceptedSequences.remove(sequence)
            lastDeliveredSequence = max(lastDeliveredSequence, sequence)
            lock.unlock()
        }

        func beginTerminalState(cancel: Bool) {
            lock.lock()
            isTerminal = true
            isCancelled = cancel
            lock.unlock()
        }

        func canDeliver() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return !isCancelled
        }
    }

    private let storage: Storage
    private let consumerTask: Task<Void, Never>

    init(handler: @escaping Handler) {
        let pair = AsyncStream.makeStream(of: Entry.self)
        let storage = Storage(continuation: pair.continuation)
        self.storage = storage
        self.consumerTask = Task {
            await Self.consume(
                pair.stream,
                storage: storage,
                handler: handler
            )
        }
    }

    /// Reserves source sequence before callback work is enqueued.
    func reserveSequence() -> UInt64 {
        storage.reserveSequence()
    }

    /// Enqueues value using sequence reserved at source callback boundary.
    /// Returns false for stale, duplicate, or terminal work.
    @discardableResult
    func enqueue(_ element: Element, sequence: UInt64) -> Bool {
        storage.accept(Entry(sequence: sequence, element: element))
    }

    /// Reserves and enqueues one value synchronously.
    @discardableResult
    func enqueue(_ element: Element) -> UInt64? {
        let sequence = reserveSequence()
        return enqueue(element, sequence: sequence) ? sequence : nil
    }

    /// Finishes bridge. Drain mode delivers every accepted value before return.
    /// Cancel mode drops queued values and cancels current handler work.
    func stop(drain: Bool) async {
        storage.beginTerminalState(cancel: !drain)
        storage.continuation.finish()
        if !drain {
            consumerTask.cancel()
        }
        await consumerTask.value
    }

    private static func consume(
        _ stream: AsyncStream<Entry>,
        storage: Storage,
        handler: @escaping Handler
    ) async {
        var pending: [UInt64: Element] = [:]
        var nextSequence: UInt64 = 1

        for await entry in stream {
            guard !Task.isCancelled, storage.canDeliver() else { return }
            pending[entry.sequence] = entry.element

            while let element = pending.removeValue(forKey: nextSequence) {
                guard !Task.isCancelled, storage.canDeliver() else { return }
                await handler(element)
                storage.markDelivered(nextSequence)
                nextSequence &+= 1
            }
        }

        // Explicit callers can leave a sequence gap. On stop, accepted work
        // still drains deterministically in source sequence order.
        guard !Task.isCancelled else { return }
        for sequence in pending.keys.sorted() {
            guard let element = pending.removeValue(forKey: sequence) else { continue }
            await handler(element)
            storage.markDelivered(sequence)
        }
    }
}
