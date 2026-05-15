public struct SentMessage: Sendable, Equatable {
    public let id: String                              // 20-char base62
    public let requestID: String                       // UUIDv7
    public let roomID: String
    public let userID: String
    public let userAccount: String
    public let content: String
    public let createdAt: String                       // RFC 3339
    public let threadParentMessageID: String?
    public let threadParentMessageCreatedAt: Int64?
    public let quotedParentMessageID: String?

    public init(
        id: String,
        requestID: String,
        roomID: String,
        userID: String,
        userAccount: String,
        content: String,
        createdAt: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.roomID = roomID
        self.userID = userID
        self.userAccount = userAccount
        self.content = content
        self.createdAt = createdAt
        self.threadParentMessageID = threadParentMessageID
        self.threadParentMessageCreatedAt = threadParentMessageCreatedAt
        self.quotedParentMessageID = quotedParentMessageID
    }
}

/// Internal: decodes server reply payload (success branch) into a SentMessage.
/// Server JSON keys are camelCase per the spec.
struct SentMessageDTO: Decodable {
    let id: String
    let roomId: String
    let userId: String
    let userAccount: String
    let content: String
    let createdAt: String
    let threadParentMessageId: String?
    let threadParentMessageCreatedAt: Int64?
    let quotedParentMessageId: String?

    func toModel(requestID: String) -> SentMessage {
        SentMessage(
            id: id,
            requestID: requestID,
            roomID: roomId,
            userID: userId,
            userAccount: userAccount,
            content: content,
            createdAt: createdAt,
            threadParentMessageID: threadParentMessageId,
            threadParentMessageCreatedAt: threadParentMessageCreatedAt,
            quotedParentMessageID: quotedParentMessageId
        )
    }
}

/// Internal: decodes server reply payload (error branch) per §5 envelope.
struct ErrorEnvelopeDTO: Decodable {
    let error: String
    let code: String?
}
