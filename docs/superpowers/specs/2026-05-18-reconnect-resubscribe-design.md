# Reconnect & resubscribe lifecycle — Design

**Status:** Draft
**Depends on:** Transport (existing) + Event subscriptions (Domain 2).

## 1. Goal

`nats.swift` reconnects automatically on dropped connections. Subscriptions
opened before a disconnect must be re-established so the event hub keeps
delivering. While disconnected, the client also misses fan-out events;
this spec defines how the library exposes the disconnect window so callers
can reconcile (e.g. via `loadNext` to catch up, or via
`mentionCountSinceLastSeen` from room metadata).

Per the subject-naming doc: clients never run JetStream consumers. We
re-establish core subscriptions only.

## 2. Architecture

```
NATSTransport ──connectivity events──► ConnectionMonitor (actor)
                                              │
                                              ▼
                                       ChatClient
                                       - re-opens user wildcard
                                       - re-opens per-room subs
                                       - emits ConnectionEvent
```

Transport gains an `AsyncStream<ConnectionEvent>`; the chat client owns the
re-subscription policy.

## 3. Public API

```swift
public protocol NATSTransport: Sendable {
    // existing methods …
    var connectionEvents: AsyncStream<ConnectionEvent> { get }
}

public enum ConnectionEvent: Sendable {
    case connected
    case disconnected(reason: String?)
    case reconnecting(attempt: Int)
    case reconnected(downtime: TimeInterval)
}

extension ChatClient {
    public var connectionEvents: AsyncStream<ConnectionEvent> { get }
}
```

`ChatClient.connectionEvents` is a re-broadcast of the transport stream,
*after* the client has finished re-establishing subscriptions on
`reconnected`. Callers observe a `.reconnected(downtime:)` only when the
hub is live again — this is the signal to run catch-up RPCs.

## 4. Re-subscription policy

On `.reconnected`:

1. Re-subscribe to `chat.user.{account}.>` (always required).
2. Re-subscribe to every room ID currently in the tracked set (from
   `subscribeToRoom(...)` history).
3. Drop any in-flight RPCs whose `request()` calls errored out during the
   disconnect — their continuations have already failed with `.transport`.
4. Pending §4 `sendMessage` continuations registered before the disconnect
   stay registered. When the connection returns, replies may still arrive
   on the user wildcard if the server kept them; if not, the existing
   timeout path triggers.
5. Emit `.reconnected(downtime:)` on `ChatClient.connectionEvents`.

If re-subscription itself fails (rare — nats.swift's reconnect won't fire
unless connected), the client re-enters a `.disconnected` state and waits
for the next transport reconnect.

## 5. Catch-up guidance (not enforced)

The library does **not** automatically call History on reconnect. The doc
records the recommended pattern:

```swift
for await event in client.connectionEvents {
    if case .reconnected = event {
        for room in trackedRooms {
            try? await catchUp(room)            // loadNext(after: lastSeen)
        }
    }
}
```

A README snippet in the chat-client docs demonstrates this.

## 6. Demo adapter

`NatsSwiftTransport` wires nats.swift's `ConnectionEventsStream` (or
equivalent) to a `ConnectionEvent` AsyncStream. The Mock transport gains
helpers:

```swift
func simulateDisconnect(reason: String?)
func simulateReconnect()
```

## 7. Errors and edges

| Case | Behaviour |
|------|-----------|
| Subscription open fails on reconnect | Client logs, retries once after 1s; further failures surface as `.disconnected` again |
| `stop()` during reconnect | Cancels the reconnection task; pending RPC continuations fail with `.transport(CancellationError)` |
| Multiple rapid disconnect/reconnect | Each emits; consumers should debounce if needed |
| `subscribeToRoom(...)` called while disconnected | Recorded in tracked set; subscription opens on next `.reconnected` |

## 8. Testing

1. Mock transport disconnect → `ChatClient.connectionEvents` emits
   `.disconnected`.
2. Mock reconnect → user wildcard + tracked rooms re-subscribed; assert
   subscribe calls observed.
3. `subscribeToRoom("X")` while disconnected → no subscribe call yet; on
   `.reconnected`, subscribe call happens.
4. Re-subscription failure → retry after 1s; assert two subscribe attempts.
5. `stop()` during a `.disconnected` window — pending sends fail, no
   crash.

## 9. Out of scope

- Persistent local message store / offline composer.
- Server-driven inbox replay (JetStream consumers — not a client concern
  per the subject-naming doc).
- Automated mention/unread badge recompute (the room-metadata events the
  caller reads from `subscriptionUpdates` already supply this).
