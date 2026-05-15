import Foundation

/// Routes server replies to per-request awaiters by `requestID`.
///
/// Slots track each registered request so that a reply arriving before the
/// caller suspends in `wait(_:)` is buffered rather than dropped.
actor PendingRequests {

    private enum Slot {
        case expecting  // registered, no waiter yet
        case pending(CheckedContinuation<Data, any Error>)  // suspended waiter
        case buffered(Data)  // reply arrived before wait
        case failed(any Error)  // fail before wait
    }

    private var slots: [String: Slot] = [:]

    /// Pre-registers a request so a fast reply can be buffered.
    func register(_ id: String) {
        // Idempotent — re-registering is a no-op if already expecting / pending.
        if slots[id] == nil {
            slots[id] = .expecting
        }
    }

    /// Suspends until the reply (or failure) for `id` is available.
    func wait(_ id: String) async throws -> Data {
        switch slots[id] {
        case .buffered(let data):
            slots.removeValue(forKey: id)
            return data
        case .failed(let err):
            slots.removeValue(forKey: id)
            throw err
        case .pending:
            // Not tested: fatalError cannot be caught by XCTest. Branch exists
            // to surface internal misuse (double-wait) during development.
            fatalError("PendingRequests.wait called twice for \(id)")
        case .expecting, .none:
            return try await withCheckedThrowingContinuation { cont in
                slots[id] = .pending(cont)
            }
        }
    }

    /// Routes a reply payload to the waiter (or buffers it).
    /// If `id` is nil, the call is a no-op — this lets callers pass an optional
    /// parse result (e.g., `Subjects.parseRequestID(...)`) directly.
    func deliver(_ id: String?, payload: Data) {
        guard let id = id else { return }
        switch slots[id] {
        case .pending(let cont):
            slots.removeValue(forKey: id)
            cont.resume(returning: payload)
        case .expecting:
            slots[id] = .buffered(payload)
        case .none, .buffered, .failed:
            return  // unknown or already done
        }
    }

    /// Fails a registered request.
    func fail(_ id: String, error: any Error) {
        switch slots[id] {
        case .pending(let cont):
            slots.removeValue(forKey: id)
            cont.resume(throwing: error)
        case .expecting:
            slots[id] = .failed(error)
        case .none, .buffered, .failed:
            return
        }
    }

    /// Drops the slot. If a waiter is suspended on `.pending`, it is resumed
    /// with `CancellationError` so the continuation contract is honoured.
    func discard(_ id: String) {
        if case .pending(let cont) = slots[id] {
            cont.resume(throwing: CancellationError())
        }
        slots.removeValue(forKey: id)
    }

    /// Fails every pending waiter with `CancellationError()` and clears all slots.
    func cancelAll() {
        for (_, slot) in slots {
            if case .pending(let cont) = slot {
                cont.resume(throwing: CancellationError())
            }
        }
        slots.removeAll()
    }
}
