# Search service RPCs (§3.3) — Design

**Status:** Draft
**Depends on:** Transport request/reply (Domain 1).

## 1. Scope

Four sync request/reply endpoints under `chat.user.{account}.request.search.`:

| Method | Subject suffix |
|--------|----------------|
| Search Messages | `messages` |
| Search Rooms | `rooms` |
| Search Apps | `apps` |
| Search Users | `users` |

## 2. Public API

```swift
extension ChatClient {
    public func searchMessages(query: String,
                               roomIDs: [String]? = nil,
                               size: Int = 25, offset: Int = 0)            async throws -> SearchMessagesResult

    public func searchRooms(query: String,
                            roomType: RoomTypeFilter = .all,
                            size: Int = 25, offset: Int = 0)               async throws -> [SearchRoom]

    public func searchApps(query: String,
                           assistantEnabled: Bool? = nil,
                           size: Int = 25, offset: Int = 0)                async throws -> [SearchApp]

    public func searchUsers(query: String)                                 async throws -> [SearchUser]
}

public enum RoomTypeFilter: String, Codable { case all, channel, dm }
```

## 3. Models

```swift
public struct SearchMessagesResult: Sendable, Decodable {
    public let messages: [SearchMessage]
    public let total: Int
}

public struct SearchMessage: Sendable, Decodable {
    public let messageId: String
    public let roomId: String
    public let siteId: String
    public let userAccount: String
    public let content: String
    public let createdAt: String               // RFC 3339
    public let editedAt: String?
    public let updatedAt: String?
    public let threadParentMessageId: String?
    public let threadParentMessageCreatedAt: String?
}

public struct SearchRoom: Sendable, Decodable {
    public let roomId: String
    public let name: String
    public let roomType: String?
}

public struct SearchApp:  Sendable, Decodable { ... }   // id, name, description, assistant, sponsors
public struct SearchUser: Sendable, Decodable { ... }   // account, engName, chineseName
```

## 4. Wire quirks

- **Search Users** returns a **raw JSON array** with no envelope. The
  decoder accepts that shape directly (`JSONDecoder().decode([SearchUser].self, ...)`).
- **Search Messages**: never includes display fields — caller resolves
  user/room names elsewhere.
- All endpoints reject whitespace-only `query` with `bad_request`.

## 5. Subjects

```swift
extension Subjects {
    static func searchMessages(account: String) -> String
    static func searchRooms(account: String)    -> String
    static func searchApps(account: String)     -> String
    static func searchUsers(account: String)    -> String
}
```

## 6. Errors

| `code` | Behaviour |
|--------|-----------|
| `bad_request` | `.server(code: "bad_request", message:)` |
| `internal` | `.server(code: "internal", message:)` |

## 7. Testing

Per endpoint: 1 happy-path with subject + body assertion + decoded model;
1 `bad_request` envelope decoded to `.server(code: "bad_request", ...)`.

Plus: Search Users decodes a top-level array; Search Messages decodes a
record with `editedAt` omitted when never edited.

## 8. Out of scope

- Re-ranking, client-side filtering, highlighting.
- Subscription-scoped re-filtering once the server `$lookup` lands (no
  client work needed — server change only).
