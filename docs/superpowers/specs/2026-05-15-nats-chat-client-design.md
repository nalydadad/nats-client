# NATS Chat Client (Swift) — Design

**Status:** Approved (pending written review)
**Scope (v1):** §4 *Message Send + Async Response* from the chat API spec.
**Out of scope (v1):** §3 req/reply services (room, history, search, user), event/stream subscriptions, HTTP `/auth` (caller already handles it).

References:
- API spec: `github.com/hmchangw/chat/main/docs/client-api.md`
- Subject naming: `github.com/hmchangw/chat/main/docs/nats-subject-naming.md`

---

## 1. Goals

1. A Swift package that exposes a typed `sendMessage(...)` API for the chat server's §4 flow.
2. NATS transport injected behind a protocol so the package is unit-testable with no live server, and so a real `nats.swift` adapter lives at the app layer.
3. Auth (account + NATS JWT) injected behind a protocol; the package never talks HTTP itself.
4. A SwiftUI demo target in the same package that wires `ChatClient` to the official `nats-io/nats.swift` library for hands-on testing.

## 2. Architecture

```
┌──────────────────────────────────────────────────────────┐
│ Public                                                   │
│   ChatClient (actor)                                     │
│     .start() / .stop()                                   │
│     .sendMessage(roomID:, siteID:, content:, ...)        │
│       async throws -> SentMessage                        │
│                                                          │
│ Public types: SentMessage, ChatClientError, AuthIdentity,│
│               NATSMessage                                │
│ Public protocols: NATSTransport, NATSSubscription,       │
│                   AuthProvider                           │
├──────────────────────────────────────────────────────────┤
│ Internal                                                 │
│   Subjects        — pure subject builders                │
│   IDGenerator     — UUIDv7 + 20-char base62              │
│   PendingRequests — actor: [requestID → continuation]    │
│   Responder       — Task reading the shared sub stream   │
│   SendMessageRequest — internal Codable wire body        │
└──────────────────────────────────────────────────────────┘
```

**Platforms:** iOS 15+, macOS 12+ (async/await prerequisite).
**Dependencies:** library target — none beyond Foundation. Demo target — `github.com/nats-io/nats.swift`.

## 3. Public protocols

```swift
public protocol NATSTransport: Sendable {
    func publish(subject: String, payload: Data) async throws
    func subscribe(subject: String) async throws -> NATSSubscription
}

public struct NATSMessage: Sendable {
    public let subject: String
    public let payload: Data
}

public protocol NATSSubscription: Sendable {
    var messages: AsyncStream<NATSMessage> { get }
    func cancel() async
}

public protocol AuthProvider: Sendable {
    func currentIdentity() async throws -> AuthIdentity
}

public struct AuthIdentity: Sendable {
    public let account: String
    public let natsJwt: String
}
```

- `NATSTransport` is intentionally chat-agnostic: publish, subscribe, message envelope.
- `AuthIdentity` is consumed by `start()`. The client uses `account` for subject construction; `natsJwt` is carried for adapters that apply it during (re)connect. Connection lifecycle remains with the transport.
- All types are `Sendable` so the actor model holds.

## 4. Public API

```swift
public actor ChatClient {
    public init(
        transport: NATSTransport,
        auth: AuthProvider,
        defaultTimeout: TimeInterval = 10
    )

    /// Resolves identity, opens the shared response subscription,
    /// starts the demuxer. Idempotent.
    public func start() async throws

    /// Cancels the demuxer and unsubscribes; fails any pending continuations
    /// with `.transport`. Idempotent.
    public func stop() async

    public func sendMessage(
        roomID: String,
        siteID: String,
        content: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> SentMessage
}

public struct SentMessage: Sendable, Equatable {
    public let id: String                          // 20-char base62, client-generated
    public let requestID: String                   // UUIDv7, client-generated
    public let roomID: String
    public let userID: String
    public let userAccount: String
    public let content: String
    public let createdAt: String                   // RFC 3339, from server
    public let threadParentMessageID: String?
    public let threadParentMessageCreatedAt: Int64?
    public let quotedParentMessageID: String?
}

public enum ChatClientError: Error, Sendable {
    case notStarted
    case timeout(requestID: String)
    case server(code: String?, message: String)   // §5 envelope
    case transport(any Error)
    case invalidPayload(String)
}
```

Deliberate calls:
- `id` and `requestID` are surfaced on `SentMessage` so callers can match optimistic-UI rows to confirmed ones.
- `content` is **not** validated client-side against the 20 KiB / non-empty rules. Server is authoritative; rejection surfaces as `.server(...)`.
- `timeout` defaults to `defaultTimeout`; `.timeout` carries the `requestID` for debugging.
- `start()` / `stop()` are explicit so the first send doesn't race subscription setup.

## 5. Subjects (§4)

| Direction | Subject |
|-----------|---------|
| Publish (send) | `chat.user.{account}.room.{roomID}.{siteID}.msg.send` |
| Subscribe (shared, once at `start`) | `chat.user.{account}.response.>` |
| Reply (server publishes) | `chat.user.{account}.response.{requestID}` |

`Subjects` is a pure module of static functions:

```swift
enum Subjects {
    static func msgSend(account: String, roomID: String, siteID: String) -> String
    static func userResponseWildcard(account: String) -> String
    static func parseRequestID(fromResponseSubject subject: String) -> String?
}
```

## 6. Send flow

```
1. Ensure started; else throw .notStarted.
2. id        = Base62.random(length: 20)
3. requestId = UUIDv7.next()
4. subject   = Subjects.msgSend(account, roomID, siteID)
5. body      = JSON { id, content, requestId,
                      threadParentMessageId?,
                      threadParentMessageCreatedAt?,
                      quotedParentMessageId? }
6. await pendingRequests.register(requestId)   // installs a continuation
7. try await transport.publish(subject, body)
8. race:
     – pendingRequests.wait(requestId)         // resumed by demuxer
     – Task.sleep(timeout)                     // resumes with .timeout
9. on response data:
     – if JSON has "error": throw .server(code, error)
     – else decode SentMessage; attach id + requestId; return
10. defer: pendingRequests.discard(requestId)
```

Order matters: register the continuation *before* publish, so a very fast reply can't arrive before the demuxer has somewhere to deliver it.

## 7. Demuxer (Responder)

Started by `ChatClient.start()`:

```swift
let sub = try await transport.subscribe(Subjects.userResponseWildcard(account: account))
self.responderTask = Task {
    for await msg in sub.messages {
        let requestID = Subjects.parseRequestID(fromResponseSubject: msg.subject)
        await pendingRequests.deliver(requestID, payload: msg.payload)
    }
}
```

`pendingRequests.deliver` looks up the continuation by `requestID`; if found, resumes with the payload and removes the entry; if not (no match, or `requestID == nil` because the subject didn't match the expected `chat.user.{account}.response.{requestID}` shape), drops the message (late reply after timeout, or unknown sender).

## 8. Concurrency model

- `ChatClient` is an `actor` — serializes start/stop and config access.
- `PendingRequests` is an `actor` wrapping `[String: CheckedContinuation<Data, Error>]`.
- The demuxer is a long-running `Task` owned by `ChatClient`, cancelled by `stop()`.
- Race between reply and timeout is resolved by whichever calls `deliver` / `fail` first; the loser is a no-op because the table entry is gone.

## 9. Errors and edge cases

| Situation | Behavior |
|-----------|----------|
| `sendMessage` before `start()` | throws `.notStarted` |
| Reply arrives after timeout | dropped silently |
| `stop()` mid-flight | pending continuations fail with `.transport(CancellationError)` |
| `transport.publish` throws | continuation discarded, error rethrown as `.transport` |
| Reply has `"error"` field | `.server(code: payload.code, message: payload.error)` |
| Reply is malformed JSON | `.invalidPayload(description)` |
| Reply on unknown requestID | dropped |
| Multiple concurrent sends | each routed by `requestID`, order-independent |

## 10. ID generation

- **`requestId`** — UUIDv7 (RFC 9562). 36-char hyphenated string. Implemented in-package: 48-bit ms timestamp + 12 random bits + version/variant bits + 62 random bits.
- **`id`** — 20-character base62 (`0-9A-Za-z`) generated from `SystemRandomNumberGenerator`. Matches the spec's "new message id" format.

Both internal to the package; tests verify length, charset, version nibble, and monotonicity (for UUIDv7).

## 11. Testing

All tests are unit tests against a `MockTransport` and `MockAuthProvider`. No live NATS in CI.

```swift
final class MockTransport: NATSTransport {
    private(set) var published: [(subject: String, payload: Data)] = []
    func publish(...)   { … records … }
    func subscribe(...) { … returns an AsyncStream whose continuation is captured … }
    func deliver(subject: String, payload: Data)   // test helper: inject a "server" reply
}
```

Cases:
1. **Subject construction** — every placeholder substituted correctly for representative account/room/site values.
2. **ID generators** — `requestId` is 36 chars, version nibble == 7, monotonic across rapid calls; `id` is 20 chars from `[0-9A-Za-z]`.
3. **Happy path** — `sendMessage` publishes the correct subject and JSON body; injected reply on `chat.user.{account}.response.{requestId}` resolves to a decoded `SentMessage` with matching `id`/`requestID`.
4. **Server error** — reply `{"error":"forbidden","code":"forbidden"}` → throws `.server(code: "forbidden", message: "forbidden")`.
5. **Timeout** — no reply within timeout → throws `.timeout(requestID:)`; late reply afterward is dropped without crashing.
6. **Concurrent in-flight requests** — three sends with different requestIDs; replies delivered out of order, each call gets its own.
7. **Unknown requestID on the wire** — dropped, no effect on pending calls.
8. **Lifecycle** — sending before `start()` throws `.notStarted`; `stop()` mid-flight fails pending continuations cleanly; `start()`/`stop()` are idempotent.
9. **Optional fields** — thread/quoted fields appear in the published payload only when supplied; absent otherwise.

## 12. Package layout

```
Package.swift                          # iOS 15, macOS 12
Sources/
  NATSChatClient/
    ChatClient.swift                   # actor + public API
    NATSTransport.swift                # protocol + NATSMessage / NATSSubscription
    AuthProvider.swift                 # protocol + AuthIdentity
    Subjects.swift                     # pure subject builders
    IDGenerator.swift                  # UUIDv7 + Base62
    PendingRequests.swift              # actor
    Responder.swift                    # demuxer task wrapper
    Models/
      SentMessage.swift
      SendMessageRequest.swift         # internal Codable wire body
      ChatClientError.swift
  ChatClientDemo/                      # SwiftUI app target
    ChatClientDemoApp.swift            # @main
    DemoConfig.swift                   # hard-coded constants (see below)
    NatsSwiftTransport.swift           # NATSTransport over nats-io/nats.swift
    StaticAuthProvider.swift           # AuthProvider returning DemoConfig values
    SendMessageView.swift              # form
    ResultView.swift                   # success / error renderers
Tests/
  NATSChatClientTests/
    ChatClientTests.swift              # happy/error/timeout/concurrent/lifecycle
    SubjectsTests.swift
    IDGeneratorTests.swift
    Support/
      MockTransport.swift
      MockAuthProvider.swift
```

## 13. Demo app

Same Swift package, separate target.

**Targets:** iOS and macOS via SwiftUI. The demo target depends on `github.com/nats-io/nats.swift` (the library target does not).

**Wiring at startup:**

```swift
@main
struct ChatClientDemoApp: App {
    let client: ChatClient = {
        let transport = NatsSwiftTransport(url: DemoConfig.natsURL,
                                           jwt:  DemoConfig.natsJwt)
        let auth = StaticAuthProvider(account: DemoConfig.account,
                                      jwt:     DemoConfig.natsJwt)
        return ChatClient(transport: transport, auth: auth)
    }()
    // ... starts client in .task, shows SendMessageView ...
}
```

**UI:**
- Text fields: `roomID`, `siteID`, `content`.
- Disclosure for optional fields: `threadParentMessageID`, `threadParentMessageCreatedAt`, `quotedParentMessageID`.
- "Send" button calls `client.sendMessage(...)`, disables while in flight.
- Result panel renders:
  - **success**: `id`, `requestID`, `createdAt`, `userAccount`, `content`.
  - **`.timeout`**: red banner with the requestID.
  - **`.server`**: red banner with `code` + `message`.
  - **`.transport` / `.invalidPayload`**: error description.
- In-memory scrollable history of recent sends for quick eyeballing.

**Config:** `DemoConfig.swift` is committed with placeholder values:

```swift
enum DemoConfig {
    static let natsURL  = "nats://localhost:4222"
    static let account  = "your-account"
    static let natsJwt  = "REPLACE_ME"
    static let defaultRoomID = ""
    static let defaultSiteID = ""
}
```

Add `Sources/ChatClientDemo/DemoConfig.swift` to `.gitignore` after first edit (or maintain a `DemoConfig.local.swift` pattern) so real credentials don't leak. README in the demo target documents this.

**Smoke-test checklist (run after build):**
1. Send a message to a real room → success, returned `SentMessage` has non-empty `id`/`requestID` and a server `createdAt`.
2. Send to a non-existent room → `.server(code: ..., message: ...)`.
3. Cut the network (airplane mode / disable Wi-Fi) → `.timeout(requestID:)`.
4. Tap Send twice in rapid succession → both replies decoded to the correct calls.

## 14. Out of scope (deferred)

- §3 req/reply (room, history, search, user services). The `Subjects` module and the demuxer pattern generalize; future work adds typed methods on `ChatClient` and reuses the same response subscription.
- Event/stream subscriptions (`chat.room.{roomID}.event`, `chat.user.{account}.notification`, presence, typing).
- HTTP `/auth` flow — caller already handles it.
- Retry/backoff — not added in v1; caller decides on retry. The server-side dedupe on `requestID` would make retries safe to add later.
- Logging/observability — not exposed in v1. Caller can wrap the transport to capture wire traffic if needed.
