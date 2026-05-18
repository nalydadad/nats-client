# Server-pushed event subscriptions — Design

**Status:** Draft
**Depends on:** v1 transport (subscribe). Does **not** require request/reply.
**Unblocks:** room/history triggered events, encryption keys, notifications, async-job results.

## 1. Goal

The chat backend pushes several event streams to authorised user/room
subjects (§3 triggered events, §4 fan-out, §5 server-pushed). v1 already
subscribes to `chat.user.{account}.>` for `.response.{requestID}`; this spec
broadens the same subscription into a typed event hub that consumers can
observe via `AsyncStream`, without each domain re-implementing demuxing.

## 2. Architecture

```
                       ┌─────────────────────────────────┐
chat.user.{a}.>  ──►   │ EventHub (actor)                │
chat.room.{r}.event ──►│   classifies subject            │
                       │   fans out to typed streams     │
                       └────────────┬────────────────────┘
                                    │
            ┌───────────────────────┼──────────────────────┐
            ▼                       ▼                      ▼
  AsyncStream<RoomEvent>   AsyncStream<SubscriptionUpdate>  AsyncStream<RoomKeyEvent>
  AsyncStream<Notification>                                 AsyncStream<AsyncJobResult>
```

The existing `Responder` keeps routing `response.{requestID}` to pending
RPCs. EventHub consumes the **same** user-wildcard subscription stream
(split at the `ChatClient` level) and additionally manages per-room
subscriptions opened on demand.

## 3. Public API

```swift
extension ChatClient {
    public func subscribeToRoom(roomID: String) async throws
    public func unsubscribeFromRoom(roomID: String) async

    public var roomEvents:           AsyncStream<RoomEvent>          { get }
    public var subscriptionUpdates:  AsyncStream<SubscriptionUpdate> { get }
    public var roomKeyEvents:        AsyncStream<RoomKeyEvent>       { get }
    public var notifications:        AsyncStream<NotificationEvent>  { get }
}
```

Streams are multicast: each property returns a new stream backed by the
same hub. Cancelling an iterator detaches that consumer; the hub keeps
running until `ChatClient.stop()`.

## 4. Subject → type mapping

| Subject | Decoded as |
|---------|-----------|
| `chat.user.{a}.response.{requestID}` | reserved for RPC demuxer (existing) |
| `chat.user.{a}.event.subscription.update` | `SubscriptionUpdate` |
| `chat.user.{a}.event.room.key` | `RoomKeyEvent` |
| `chat.user.{a}.event.room` | `RoomEvent` (DM new_message) |
| `chat.user.{a}.notification` | `NotificationEvent` |
| `chat.room.{roomID}.event` | `RoomEvent` (channel new_message, edited, deleted) |

Subject classification lives in `Subjects.classify(_:) -> SubjectKind`.
Unknown subjects are dropped silently (logged in debug builds).

## 5. Models (sketch)

```swift
public struct RoomEvent: Sendable, Decodable {
    public let type: String          // "new_message", "message_edited", ...
    public let roomId: String
    public let timestamp: Int64
    public let lastMsgId: String?
    public let mentionAll: Bool?
    public let hasMention: Bool?
    public let message: Message?
    public let encryptedMessage: EncryptedMessage?
}

public struct SubscriptionUpdate: Sendable, Decodable { ... }
public struct RoomKeyEvent: Sendable, Decodable { ... }
public struct NotificationEvent: Sendable, Decodable { ... }
public struct AsyncJobResult: Sendable, Decodable { ... }   // §3 async jobs
```

`Message`, `EncryptedMessage`, `Participant` live in the History domain spec
but are re-used here.

## 6. Async job results

The §3 async-job RPCs reply on `chat.user.{a}.response.{requestID}` (same
shape as §4 replies). Domain 3 (Room) decides at call time whether to:
- await a continuation (when `X-Request-ID` is set), or
- only consume the synchronous reply.

EventHub itself stays out of this — it just hands `AsyncJobResult` payloads
to the RPC layer through the existing `PendingRequests` registry, which is
extended to optionally hold a *second* continuation per request (sync reply
+ async result). See Room spec §5.

## 7. Errors and edge cases

| Case | Behaviour |
|------|-----------|
| Decode failure | drop, log; the hub does not propagate decoding errors to consumers (would break the stream) |
| Subscriber backpressure | each `AsyncStream` uses `.bufferingOldest(256)`; oldest dropped on overflow |
| Per-room subscribe called twice | idempotent; second call is a no-op |
| `stop()` mid-stream | all streams finish |

## 8. Testing

1. Inject a `subscription.update` payload → arrives on `subscriptionUpdates`.
2. Inject a channel `new_message` on `chat.room.X.event` after
   `subscribeToRoom("X")` → arrives on `roomEvents`.
3. Unknown subject is dropped (no stream emits).
4. Two consumers on `roomEvents` both receive the same event.
5. Cancelling one iterator does not affect the others.
6. `stop()` finishes all streams.

## 9. Out of scope

- Per-room *history* catch-up (covered in History domain).
- Decryption of `encryptedMessage` (covered in Room encryption domain).
- Mention/unread badge derivation (covered in Reconnect domain).
