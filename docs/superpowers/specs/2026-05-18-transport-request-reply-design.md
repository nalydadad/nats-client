# Transport: request/reply + headers — Design

**Status:** Draft
**Depends on:** none (extends the v1 design)
**Unblocks:** every §3 RPC domain (room, history, search, user) and async-job result delivery.

## 1. Goal

The v1 transport supports `publish` + a shared subscription. The §3 RPCs in the
chat API spec use **NATS request/reply** (`_INBOX.>` reply subjects), and the
async-job RPCs require **NATS message headers** (specifically `X-Request-ID`).
This spec extends `NATSTransport` with both, keeping the protocol chat-agnostic.

## 2. Public protocol changes

```swift
public protocol NATSTransport: Sendable {
    // existing
    func publish(subject: String, payload: Data) async throws
    func subscribe(subject: String) async throws -> NATSSubscription

    // new
    func publish(
        subject: String,
        payload: Data,
        headers: [String: String]
    ) async throws

    func request(
        subject: String,
        payload: Data,
        headers: [String: String],
        timeout: TimeInterval
    ) async throws -> NATSMessage
}

public struct NATSMessage: Sendable {
    public let subject: String
    public let payload: Data
    public let headers: [String: String]   // new; empty when absent
}
```

`request` is one-shot: the transport handles inbox subject generation, the
single-reply subscription, and timeout. It throws `ChatClientError.timeout` on
no reply, `.transport(_)` on connection failure.

Default-implementation rule for adapters that already do request/reply
natively (like `nats.swift`): forward directly. Mock transports get a hand-
rolled implementation for tests.

## 3. Headers

- `nats.swift` exposes headers as `NATSHeaderMap`. The adapter copies to/from
  `[String: String]`. Multi-value headers are not used by this API spec; if
  encountered on inbound messages, the adapter joins with `, ` (HTTP-style).
- The library never inspects header names; callers (e.g. room service) set
  `X-Request-ID` themselves.

## 4. Demo adapter changes

`NatsSwiftTransport` adds:

```swift
func request(subject: String, payload: Data,
             headers: [String: String],
             timeout: TimeInterval) async throws -> NATSMessage
```

Implemented via `NatsClient.request(subject:payload:headers:timeout:)` from
nats.swift. Connection lifecycle stays unchanged.

## 5. Mock transport changes

`MockTransport` gains:

- `requests: [(subject: String, payload: Data, headers: [String: String])]`
- `respond(toSubjectMatching: String, payload: Data)` — test helper that
  resolves the next pending `request(...)` whose subject matches.

The hand-rolled `request` records the call, suspends on a continuation, and
returns whatever payload the test injects (or times out via `Task.sleep`).

## 6. Errors

Same `ChatClientError` cases; no new variants. A `request` that times out
throws `.timeout(requestID:)` with a synthesised request ID
(`"req-<UUID short>"`) — used only for diagnostics.

## 7. Testing

1. Mock `request` round-trips: publish payload + headers captured; injected
   reply returned to caller.
2. Mock `request` timeout: no injection within `timeout` → throws `.timeout`.
3. Header round-trip on `publish` (no reply): captured exactly.
4. Existing `publish(subject:payload:)` still works (default-impl forwards
   to the new overload with empty headers).
5. Inbound message with no headers exposes `headers == [:]`.

## 8. Out of scope

- JetStream consumers (no client-side JetStream per the subject-naming doc).
- Multi-reply request patterns (the chat spec doesn't use them — async jobs
  reply once on the user wildcard, not on `_INBOX`).
- Header schema validation — left to callers.
