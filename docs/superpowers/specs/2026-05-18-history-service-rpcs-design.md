# History service RPCs (§3.2) — Design

**Status:** Draft
**Depends on:** Transport request/reply (Domain 1).
**Related:** Event subscriptions (Domain 2) — Edit/Delete also publish room events.

## 1. Scope

All `history-service` methods. Subject prefix: `chat.user.{account}.request.room.{roomID}.{siteID}.msg.`.

| Method | Subject suffix |
|--------|----------------|
| Load History | `history` |
| Load Next | `next` |
| Load Surrounding | `surrounding` |
| Get by ID | `get` |
| Edit | `edit` |
| Delete | `delete` |
| Get Thread | `thread` |
| Get Thread Parents | `thread.parent` |

All synchronous request/reply via `_INBOX.>`.

## 2. Public API

```swift
extension ChatClient {
    public func loadHistory(roomID: String, siteID: String,
                            before: Date? = nil, limit: Int)               async throws -> HistoryPage
    public func loadNext(roomID: String, siteID: String,
                         after: Date? = nil, limit: Int,
                         cursor: String = "")                              async throws -> ForwardPage
    public func loadSurrounding(roomID: String, siteID: String,
                                around messageID: String, limit: Int)     async throws -> SurroundingPage
    public func getMessage(roomID: String, siteID: String,
                           id: String)                                     async throws -> Message
    public func editMessage(roomID: String, siteID: String,
                            id: String, newContent: String)                async throws -> EditAck
    public func deleteMessage(roomID: String, siteID: String,
                              id: String)                                  async throws -> DeleteAck
    public func threadMessages(roomID: String, siteID: String,
                               threadMessageID: String, limit: Int,
                               cursor: String? = nil)                      async throws -> ThreadPage
    public func threadParents(roomID: String, siteID: String,
                              filter: ThreadFilter,
                              offset: Int, limit: Int)                     async throws -> ThreadParentsPage
}

public enum ThreadFilter: String, Codable { case all, following, unread }
```

## 3. Models (sketch)

```swift
public struct Message: Sendable, Decodable, Equatable {
    public let roomId: String
    public let messageId: String
    public let createdAt: String            // RFC 3339
    public let sender: Participant
    public let msg: String
    public let attachments: [Data]?
    public let mentions: [Participant]?
    public let threadParentId: String?
    public let threadParentCreatedAt: String?
    public let quotedParentMessage: QuotedParentMessage?
    public let editedAt: String?
    public let updatedAt: String?
    public let deleted: Bool?
    public let type: String?                // system-message type
    public let reactions: [String: [Participant]]?
}

public struct Participant: Sendable, Decodable, Equatable { ... }
public struct QuotedParentMessage: Sendable, Decodable, Equatable { ... }

public struct HistoryPage:    Sendable { public let messages: [Message]; public let minUserLastSeenAt: Int64? }
public struct ForwardPage:    Sendable { public let messages: [Message]; public let nextCursor: String?; public let hasNext: Bool }
public struct SurroundingPage:Sendable { public let messages: [Message]; public let moreBefore: Bool; public let moreAfter: Bool }
public struct ThreadPage:     Sendable { public let messages: [Message]; public let nextCursor: String?; public let hasNext: Bool }
public struct ThreadParentsPage: Sendable { public let parentMessages: [Message]; public let total: Int }
public struct EditAck:        Sendable { public let messageId: String; public let editedAt: Int64 }
public struct DeleteAck:      Sendable { public let messageId: String; public let deletedAt: Int64 }
```

Attachments arrive base64-encoded; we decode at the JSON boundary into
`Data`. `card.data` and `sysMsgData` are kept as raw `Data?` too.

## 4. Subjects

```swift
extension Subjects {
    static func msgHistory(account: String, roomID: String, siteID: String)      -> String
    static func msgNext(...)                                                     -> String
    static func msgSurrounding(...)                                              -> String
    static func msgGet(...)                                                      -> String
    static func msgEdit(...)                                                     -> String
    static func msgDelete(...)                                                   -> String
    static func msgThread(...)                                                   -> String
    static func msgThreadParent(...)                                             -> String
}
```

## 5. Date handling

Backend uses two conventions:
- **RFC 3339 strings** for stored fields (`createdAt`, `editedAt`, ...).
- **UnixMilli numbers** for query params (`before`, `after`) and event
  payloads.

Public API uses `Date` everywhere; an internal `DateCodec` converts to/from
RFC 3339 / UnixMilli as appropriate per field.

## 6. Errors

- All RPCs: error envelope → `.server(code:message:)`.
- Edit/Delete: server enforces sender-only — caller surfaces `.server` for
  the well-known messages (`"only the sender can edit"`, `"message not found"`).
- Pagination cursor opaque — never inspected client-side.

## 7. Testing

Per RPC: subject + body assertion, decoded model. Plus:

- Edit/Delete only invoke `request` (no event-stream coupling — that lives
  in Domain 2; an integration test there asserts the emitted room event).
- `before`/`after` encode to UnixMilli numbers.
- RFC 3339 round-trip on `createdAt`.
- System message (`type == "members_added"`) decodes with `msg` populated.

## 8. Out of scope

- Local cache / deduping across history + live events — caller-owned.
- Display-name resolution (call user-service or use subscription cache).
