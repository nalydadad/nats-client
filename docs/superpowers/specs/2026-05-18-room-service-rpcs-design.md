# Room service RPCs (§3.1) — Design

**Status:** Draft
**Depends on:** Transport request/reply (Domain 1), Event subscriptions (Domain 2).

## 1. Scope

All `room-service` methods from the API spec:

| Method | Subject suffix | Pattern |
|--------|----------------|---------|
| Create Room | `request.rooms.create` | sync req/reply |
| List Rooms | `request.rooms.list` | sync req/reply |
| Get Room | `request.rooms.get.{roomID}` | sync req/reply |
| Add Members | `request.room.{roomID}.{siteID}.member.add` | **async job** |
| Remove Member | `request.room.{roomID}.{siteID}.member.remove` | **async job** |
| Update Role | `request.room.{roomID}.{siteID}.member.role-update` | async (no result event) |
| List Members | `request.room.{roomID}.{siteID}.member.list` | sync req/reply |
| Mark Read | `request.room.{roomID}.{siteID}.message.read` | sync req/reply |
| Read Receipts | `request.room.{roomID}.{siteID}.message.read-receipt` | sync req/reply |
| List Org Members | `request.orgs.{orgID}.members` | sync req/reply |

All under `chat.user.{account}.`.

## 2. Public API

```swift
extension ChatClient {
    // sync RPCs
    public func createRoom(_ req: CreateRoomRequest)                       async throws -> Room
    public func listRooms()                                                async throws -> [Room]
    public func getRoom(id: String)                                        async throws -> Room
    public func listMembers(roomID: String, siteID: String,
                            limit: Int? = nil, offset: Int? = nil,
                            enrich: Bool = false)                          async throws -> [RoomMember]
    public func markRead(roomID: String, siteID: String)                   async throws
    public func readReceipts(roomID: String, siteID: String,
                             messageID: String)                            async throws -> [ReadReceiptEntry]
    public func listOrgMembers(orgID: String)                              async throws -> [OrgMember]

    // async-job RPCs
    public func addMembers(roomID: String, siteID: String,
                           _ req: AddMembersRequest)                       async throws -> AsyncJobHandle
    public func removeMember(roomID: String, siteID: String,
                             _ req: RemoveMemberRequest)                   async throws -> AsyncJobHandle
    public func updateRole(roomID: String, siteID: String,
                           account: String, newRole: RoomRole)             async throws // no handle
}

public struct AsyncJobHandle: Sendable {
    public let requestID: String
    public func result(timeout: TimeInterval) async throws -> AsyncJobResult
}
```

## 3. Models (sketch)

```swift
public struct Room: Sendable, Decodable, Equatable {
    public let id: String
    public let name: String
    public let type: String           // "channel" | "dm" | "botDM" | "discussion"
    public let createdBy: String
    public let siteId: String
    public let userCount: Int
    public let lastMsgAt: String?
    public let lastMsgId: String?
    public let createdAt: String
    public let updatedAt: String
    public let restricted: Bool?
    public let uids: [String]?
    public let accounts: [String]?
}

public struct RoomMember: Sendable, Decodable { ... }
public struct ReadReceiptEntry: Sendable, Decodable { ... }
public struct OrgMember: Sendable, Decodable { ... }
public enum RoomRole: String, Sendable, Codable { case owner, member }
```

`AsyncJobResult` is defined in the Event subscriptions spec.

## 4. Subjects

```swift
extension Subjects {
    static func roomsCreate(account: String)                  -> String
    static func roomsList(account: String)                    -> String
    static func roomsGet(account: String, roomID: String)     -> String
    static func memberAdd(account: String, roomID: String, siteID: String)        -> String
    static func memberRemove(account: String, roomID: String, siteID: String)     -> String
    static func memberRoleUpdate(account: String, roomID: String, siteID: String) -> String
    static func memberList(account: String, roomID: String, siteID: String)       -> String
    static func messageRead(account: String, roomID: String, siteID: String)      -> String
    static func messageReadReceipt(account: String, roomID: String, siteID: String) -> String
    static func orgMembers(account: String, orgID: String)    -> String
}
```

## 5. Async-job result flow

1. Caller invokes e.g. `addMembers(...)`.
2. Client generates a `requestID` (UUIDv7), registers a *result continuation*
   in `PendingRequests` (separate from sync-reply slot).
3. Client calls `transport.request(subject, body, headers: ["X-Request-ID": requestID], timeout)`.
4. On `{"status":"accepted"}`, returns `AsyncJobHandle(requestID: ...)`.
5. The user-wildcard demuxer (Event hub) routes any future
   `chat.user.{a}.response.{requestID}` payload decoded as `AsyncJobResult`
   to the result continuation.
6. `handle.result(timeout:)` awaits that continuation.

If the sync reply is an error envelope, throw `.server(...)` and discard
the registered result slot.

Update Role has no result event — the API returns no `AsyncJobHandle`;
callers observe outcome via `subscriptionUpdates` from Domain 2.

## 6. Errors

- All sync RPCs: error envelope → `.server(code:message:)`.
- Add/Remove async-job failure: `AsyncJobResult.success == false` → callers
  decide; not thrown.
- Timeout on sync: `.timeout(requestID:)`.
- Timeout on async result: same.

## 7. Testing

For each RPC: 1 happy-path (subject + body assertion, decoded model) and 1
error-envelope test. Additionally:

- Add/Remove: `X-Request-ID` header present; async result delivered via
  injected response on `chat.user.{a}.response.{reqID}` resolves the handle.
- Update Role: no handle returned; verify subscription update event arrives
  on the Domain-2 stream (assert in event spec tests).

## 8. Out of scope

- The `subscription.update` event itself — delivered through Domain 2.
- Federation outbox semantics — server-side concern.
