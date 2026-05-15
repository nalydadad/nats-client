import Foundation

public actor ChatClient {

    private let transport: any NATSTransport
    private let auth: any AuthProvider
    private let defaultTimeout: TimeInterval
    private let pending = PendingRequests()

    // Lifecycle state
    private var account: String?
    private var subscription: (any NATSSubscription)?
    private var responderTask: Task<Void, Never>?

    public init(
        transport: any NATSTransport,
        auth: any AuthProvider,
        defaultTimeout: TimeInterval = 10
    ) {
        self.transport = transport
        self.auth = auth
        self.defaultTimeout = defaultTimeout
    }

    /// Resolves identity, opens the shared response subscription, starts the demuxer.
    /// Idempotent — safe to call multiple times.
    public func start() async throws {
        if responderTask != nil { return }
        let identity = try await auth.currentIdentity()
        let subject = Subjects.userResponseWildcard(account: identity.account)
        let sub = try await transport.subscribe(subject: subject)
        self.account = identity.account
        self.subscription = sub
        let responder = Responder(subscription: sub, pending: pending)
        self.responderTask = Task { await responder.run() }
    }

    /// Cancels the demuxer, fails pending waiters, unsubscribes. Idempotent.
    public func stop() async {
        responderTask?.cancel()
        responderTask = nil
        await pending.cancelAll()
        if let sub = subscription {
            await sub.cancel()
        }
        subscription = nil
        account = nil
    }

    /// Stub — real implementation lands in Task 9. Always throws `.notStarted`
    /// (after the started-check) for now so the lifecycle tests can verify
    /// the not-started path.
    public func sendMessage(
        roomID: String,
        siteID: String,
        content: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> SentMessage {
        guard account != nil else { throw ChatClientError.notStarted }
        // Filled in by Task 9.
        throw ChatClientError.notStarted
    }
}
