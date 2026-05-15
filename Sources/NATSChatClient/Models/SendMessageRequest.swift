/// Wire body for `chat.user.{account}.room.{roomID}.{siteID}.msg.send`.
/// Optional fields are omitted entirely when nil (not encoded as JSON null).
struct SendMessageRequest: Encodable {
    let id: String
    let content: String
    let requestId: String
    let threadParentMessageId: String?
    let threadParentMessageCreatedAt: Int64?
    let quotedParentMessageId: String?

    private enum CodingKeys: String, CodingKey {
        case id, content, requestId
        case threadParentMessageId, threadParentMessageCreatedAt
        case quotedParentMessageId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(requestId, forKey: .requestId)
        try c.encodeIfPresent(threadParentMessageId, forKey: .threadParentMessageId)
        try c.encodeIfPresent(threadParentMessageCreatedAt, forKey: .threadParentMessageCreatedAt)
        try c.encodeIfPresent(quotedParentMessageId, forKey: .quotedParentMessageId)
    }
}
