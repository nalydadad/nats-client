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
    private var startGeneration: Int = 0

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
        startGeneration &+= 1
        let gen = startGeneration

        let identity = try await auth.currentIdentity()
        guard gen == startGeneration else { return }   // stop() ran during await

        let subject = Subjects.userResponseWildcard(account: identity.account)
        let sub = try await transport.subscribe(subject: subject)
        guard gen == startGeneration else {
            await sub.cancel()
            return
        }

        self.account = identity.account
        self.subscription = sub
        let responder = Responder(subscription: sub, pending: pending)
        self.responderTask = Task { await responder.run() }
    }

    /// Cancels the demuxer, fails pending waiters, unsubscribes. Idempotent.
    public func stop() async {
        startGeneration &+= 1
        if let sub = subscription {
            await sub.cancel()
        }
        subscription = nil
        await pending.cancelAll()
        responderTask?.cancel()
        responderTask = nil
        account = nil
    }

    public func sendMessage(
        roomID: String,
        siteID: String,
        content: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> SentMessage {
        guard let account = account else { throw ChatClientError.notStarted }

        let id = Base62.randomID(length: 20)
        let requestID = UUIDv7.next()
        let subject = Subjects.msgSend(account: account, roomID: roomID, siteID: siteID)

        let body = SendMessageRequest(
            id: id,
            content: content,
            requestId: requestID,
            threadParentMessageId: threadParentMessageID,
            threadParentMessageCreatedAt: threadParentMessageCreatedAt,
            quotedParentMessageId: quotedParentMessageID
        )

        let encoder = JSONEncoder()
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw ChatClientError.invalidPayload("encode failed: \(error)")
        }

        await pending.register(requestID)
        defer { Task { [pending] in await pending.discard(requestID) } }

        do {
            try await transport.publish(subject: subject, payload: payload)
        } catch {
            throw ChatClientError.transport(error)
        }

        let effectiveTimeout = timeout ?? defaultTimeout
        let data = try await raceWaitVsTimeout(
            requestID: requestID,
            seconds: effectiveTimeout
        )

        return try decodeReply(data, requestID: requestID)
    }

    private func raceWaitVsTimeout(
        requestID: String,
        seconds: TimeInterval
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            let p = self.pending
            group.addTask { try await p.wait(requestID) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ChatClientError.timeout(requestID: requestID)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func decodeReply(_ data: Data, requestID: String) throws -> SentMessage {
        let decoder = JSONDecoder()
        // Error branch first.
        if let env = try? decoder.decode(ErrorEnvelopeDTO.self, from: data),
           !env.error.isEmpty {
            throw ChatClientError.server(code: env.code, message: env.error)
        }
        do {
            let dto = try decoder.decode(SentMessageDTO.self, from: data)
            return dto.toModel(requestID: requestID)
        } catch {
            throw ChatClientError.invalidPayload("decode failed: \(error)")
        }
    }
}
