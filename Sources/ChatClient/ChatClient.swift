import Foundation

public actor ChatClient {
    private let transport: NATSTransport
    private let account: String
    private let siteID: String
    private let timeout: Duration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var responseTask: Task<Void, Never>?
    private var pendingJobs: [String: CheckedContinuation<Data, Error>] = [:]

    public init(
        transport: NATSTransport,
        account: String,
        siteID: String,
        timeout: Duration = .seconds(10)
    ) {
        self.transport = transport
        self.account = account
        self.siteID = siteID
        self.timeout = timeout
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.encoder = enc
        self.decoder = dec
    }

    public func connect() async throws {
        guard responseTask == nil else { return }
        let stream = try await transport.subscribe(subject: Subjects.userResponses(account: account))
        responseTask = Task { [weak self] in
            do {
                for try await msg in stream {
                    await self?.dispatchJobReply(payload: msg.payload)
                }
                await self?.failAllPending(ChatError.transportClosed)
            } catch {
                await self?.failAllPending(error)
            }
        }
    }

    public func disconnect() {
        responseTask?.cancel()
        responseTask = nil
        failAllPending(CancellationError())
    }

    public func listRooms() async throws -> [Room] {
        let data = try await transport.request(
            subject: Subjects.roomsList(account: account),
            payload: Data("{}".utf8),
            timeout: timeout
        )
        try throwIfError(data)
        return try decode(ListRoomsResponse.self, from: data).rooms
    }

    public func sendMessage(
        roomID: String,
        content: String,
        threadParentMessageId: String? = nil,
        threadParentMessageCreatedAt: Date? = nil,
        quotedParentMessageId: String? = nil
    ) async throws -> Message {
        guard responseTask != nil else { throw ChatError.notConnected }
        let requestID = IDs.uuidV7()
        let req = SendMessageRequest(
            id: IDs.base62(length: 20),
            content: content,
            requestId: requestID,
            threadParentMessageId: threadParentMessageId,
            threadParentMessageCreatedAt: threadParentMessageCreatedAt,
            quotedParentMessageId: quotedParentMessageId
        )
        let payload = try encoder.encode(req)
        let subject = Subjects.messageSend(account: account, roomID: roomID, siteID: siteID)

        let transport = self.transport
        let data = try await awaitJobReply(requestID: requestID) {
            try await transport.publish(subject: subject, payload: payload)
        }
        try throwIfError(data)
        return try decode(Message.self, from: data)
    }

    public nonisolated func roomEvents(roomID: String) -> AsyncThrowingStream<RoomEvent, Error> {
        let transport = self.transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await transport.subscribe(subject: Subjects.roomAll(roomID: roomID))
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    for try await msg in stream {
                        if let event = try? decoder.decode(RoomEvent.self, from: msg.payload) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func awaitJobReply(
        requestID: String,
        trigger: @Sendable @escaping () async throws -> Void
    ) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                self.pendingJobs[requestID] = cont
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await trigger()
                    } catch {
                        await self.failPending(requestID: requestID, error: error)
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failPending(requestID: requestID, error: CancellationError())
            }
        }
    }

    private func dispatchJobReply(payload: Data) {
        guard let env = try? decoder.decode(JobReplyEnvelope.self, from: payload),
              let cont = pendingJobs.removeValue(forKey: env.requestId)
        else { return }
        cont.resume(returning: payload)
    }

    private func failPending(requestID: String, error: Error) {
        if let cont = pendingJobs.removeValue(forKey: requestID) {
            cont.resume(throwing: error)
        }
    }

    private func failAllPending(_ error: Error) {
        let pending = pendingJobs
        pendingJobs.removeAll()
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }

    private func throwIfError(_ data: Data) throws {
        if let env = try? decoder.decode(ErrorEnvelope.self, from: data) {
            throw ChatError.from(env)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ChatError.decoding(String(describing: error))
        }
    }
}
