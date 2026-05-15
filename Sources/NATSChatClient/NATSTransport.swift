import Foundation

public struct NATSMessage: Sendable, Equatable {
    public let subject: String
    public let payload: Data

    public init(subject: String, payload: Data) {
        self.subject = subject
        self.payload = payload
    }
}

public protocol NATSSubscription: Sendable {
    /// AsyncStream of inbound messages on this subscription.
    /// The stream finishes when `cancel()` is called or the transport tears it down.
    var messages: AsyncStream<NATSMessage> { get }
    func cancel() async
}

public protocol NATSTransport: Sendable {
    /// Publish a payload to `subject`.
    func publish(subject: String, payload: Data) async throws

    /// Subscribe to `subject`. The subject may contain wildcards (`*`, `>`).
    func subscribe(subject: String) async throws -> any NATSSubscription
}
