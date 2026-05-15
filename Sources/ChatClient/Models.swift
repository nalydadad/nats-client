import Foundation

public struct Room: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: String
    public let createdBy: String
    public let siteId: String
    public let userCount: Int
    public let lastMsgAt: Date?
    public let lastMsgId: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct Message: Codable, Sendable, Equatable {
    public let id: String
    public let roomId: String
    public let userId: String?
    public let userAccount: String
    public let content: String
    public let createdAt: Date
    public let threadParentMessageId: String?
    public let quotedParentMessage: QuotedMessage?
}

public struct QuotedMessage: Codable, Sendable, Equatable {
    public let id: String
    public let content: String
    public let userAccount: String
}

public struct RoomEvent: Codable, Sendable {
    public let type: String
    public let message: Message?
    public let messageId: String?
    public let editedAt: Date?
    public let deletedAt: Date?
    public let content: String?
}

struct SendMessageRequest: Codable {
    let id: String
    let content: String
    let requestId: String
    let threadParentMessageId: String?
    let threadParentMessageCreatedAt: Date?
    let quotedParentMessageId: String?
}

struct ListRoomsResponse: Codable {
    let rooms: [Room]
}

struct AcceptedResponse: Codable {
    let status: String
}

struct ErrorEnvelope: Codable {
    let error: String
    let code: String?
}

struct JobReplyEnvelope: Codable {
    let requestId: String
}
