import Foundation
import NATSChatClient

/// In-memory NATS transport for tests.
/// - Records every publish so assertions can verify subject/payload.
/// - Lets tests inject server replies onto active subscriptions via `deliver(...)`.
/// - Optional `publishError` lets tests simulate publish failures.
actor MockTransport: NATSTransport {

    struct PublishedMessage: Equatable {
        let subject: String
        let payload: Data
    }

    private(set) var published: [PublishedMessage] = []
    var publishError: (any Error)?

    // Active subscriptions keyed by their subject filter.
    private var subscriptions: [String: AsyncStream<NATSMessage>.Continuation] = [:]

    func setPublishError(_ err: (any Error)?) { self.publishError = err }

    /// Test helper: explicit accessor for use from test helpers; semantically
    /// equivalent to `await transport.published`.
    func snapshot() -> [PublishedMessage] { published }

    // MARK: NATSTransport

    func publish(subject: String, payload: Data) async throws {
        if let e = publishError { throw e }
        published.append(PublishedMessage(subject: subject, payload: payload))
    }

    func subscribe(subject: String) async throws -> any NATSSubscription {
        var continuation: AsyncStream<NATSMessage>.Continuation!
        let stream = AsyncStream<NATSMessage> { continuation = $0 }
        assert(subscriptions[subject] == nil, "MockTransport: duplicate subscription for \(subject)")
        subscriptions[subject] = continuation
        return MockSubscription(
            stream: stream,
            onCancel: { [self, subject] in
                await self.cancelSubscription(subject: subject)
            }
        )
    }

    // MARK: Test helpers

    /// Deliver a message into every active subscription whose filter matches `subject`.
    /// Matching is wildcard-aware for the `>` suffix.
    func deliver(subject: String, payload: Data) {
        let msg = NATSMessage(subject: subject, payload: payload)
        for (filter, cont) in subscriptions where matches(filter: filter, subject: subject) {
            cont.yield(msg)
        }
    }

    private func cancelSubscription(subject: String) {
        if let cont = subscriptions.removeValue(forKey: subject) {
            cont.finish()
        }
    }

    private func matches(filter: String, subject: String) -> Bool {
        if filter == subject { return true }
        if filter.hasSuffix(".>") {
            let prefix = String(filter.dropLast(1))  // keep trailing dot
            return subject.hasPrefix(prefix) && subject.count > prefix.count
        }
        return false
    }
}

private struct MockSubscription: NATSSubscription, Sendable {
    let stream: AsyncStream<NATSMessage>
    let onCancel: @Sendable () async -> Void
    var messages: AsyncStream<NATSMessage> { stream }
    func cancel() async { await onCancel() }
}
