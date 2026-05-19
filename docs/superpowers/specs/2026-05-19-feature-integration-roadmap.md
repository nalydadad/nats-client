# Feature Integration Roadmap — §3 Services + Streams

**Status:** Approved — decomposition only. Each sub-project owns its own design + plan + implementation cycle.
**Date:** 2026-05-19
**Predecessor:** `docs/superpowers/specs/2026-05-15-nats-chat-client-design.md` (v1 — §4 message send + async response).

## Why this document exists

v1 shipped the §4 send-message flow. The original design listed several deferred items; this roadmap covers two of them — **§3 typed req/reply services** and **event/stream subscriptions** — and decomposes them into sub-projects sized to be brainstormed, planned, and implemented one at a time.

Three deferred items are explicitly **not** in this roadmap and remain unplanned:

- HTTP `/auth` flow (caller still handles auth)
- Retry / backoff policy
- Logging / observability

Reopen those separately when needed.

## Out of scope for this document

This is a roadmap, not a design. It does NOT specify:

- Wire format / DTO fields per service (each sub-project will pull the canonical shape from `github.com/hmchangw/chat/main/docs/client-api.md` during its own brainstorm).
- Exact public method signatures on `ChatClient`.
- Test matrices.

It DOES specify: what each sub-project covers, what it depends on, and what order to do them in.

---

## Cross-cutting concerns inherited from v1

Pinned once here so individual sub-projects don't re-litigate them.

- **Decode-error policy.** Malformed JSON from the server surfaces as `ChatClientError.invalidPayload` (`ChatClient.swift:153–154`). Group A sub-projects MUST reuse this; Group B streams MUST surface decode errors to consumers without closing the stream (one bad frame ≠ stream death).
- **`ChatClient.stop()` semantics.** v1 cancels the demuxer, fails all `PendingRequests` waiters with `.transport(CancellationError)`, and unsubscribes (`ChatClient.swift:50–60`). Group A sub-projects inherit this unchanged. **Group B's `stop()` behavior is part of B0's scope** — pin it once there so B1–B4 don't each invent their own.
- **Reconnect / resubscribe is NOT addressed by any sub-project here.** v1 has no NATS reconnect story; neither does this roadmap. When a transport reconnect drops the response subscription or any Group B subscription, in-flight requests and live streams are left to whatever the transport adapter chooses. A future resilience roadmap (the deferred Group D / F work) owns this.

---

## Sub-projects

### Group A — §3 typed req/reply services

These reuse the existing `chat.user.{account}.response.>` subscription and the `PendingRequests` demuxer. They add typed methods on `ChatClient` and new entries in `Subjects`.

#### A0 — Req/reply infrastructure extraction

**Goal:** factor the request/wait/decode pattern currently inlined in `ChatClient.sendMessage` into an internal helper so A1–A4 do not duplicate it.

**Scope:**
- Internal `request<Req: Encodable, Rep: Decodable>(subject:body:timeout:) async throws -> Rep` on `ChatClient` (or a sibling actor).
- Handles: requestID generation, `PendingRequests.register` before publish, JSON encode, publish, race with timeout, error-envelope branch, decode.
- `sendMessage` is refactored to call it; its public behavior must not change.
- **Note on secondary identifiers:** v1's `sendMessage` generates two IDs — `requestID` (the demuxer key, owned by the helper) and `id` (a Base62 message ID embedded in the message body, sendMessage-specific). The generic helper only knows about `requestID`. Any §3 sub-project that needs a similar client-generated entity ID puts it in its own request body, not the helper signature.

**Depends on:** nothing (pure refactor of v1 code). References v1 §6–§8 (send flow / demuxer).

**Done when:** existing tests pass unchanged; new internal helper has its own unit tests covering the encode/decode/timeout path with a generic DTO.

#### A1 — Room service

**Goal:** typed methods for §3 room endpoints (create / get / list / update / leave — exact surface to be pinned during brainstorm against the chat API spec).

**Depends on:** A0.

**Done when:** each endpoint has a `ChatClient.room*(...)` method, a Subjects builder, request/reply DTOs, and happy-path + server-error + timeout tests against `MockTransport`.

#### A2 — History service

**Goal:** typed methods for room message history (pagination — before/after cursor, limit).

**Depends on:** A0. (Independent of A1.)

**Done when:** as A1, plus a test exercising paging boundary (empty page, partial page, oldest-first vs newest-first if the spec distinguishes).

#### A3 — Search service

**Goal:** typed methods for the §3 search endpoint(s).

**Depends on:** A0. (Independent of A1, A2.)

**Done when:** as A1, plus a test covering empty-result and large-result shapes.

#### A4 — User service

**Goal:** typed methods for §3 user endpoints (get / list / profile — exact surface pinned at brainstorm).

**Depends on:** A0. (Independent of A1–A3.)

**Done when:** as A1.

### Group B — event / stream subscriptions

These introduce a second subscription model: long-lived, per-key (per-room or per-user), public `AsyncStream`-based, with explicit lifetime managed by the caller.

#### B0 — Subscription lifecycle infrastructure

**Goal:** an internal subscription manager that opens a NATS subscription on demand, multiplexes it to one or more `AsyncStream` consumers, and tears down when the last consumer disappears.

**Scope:**
- Generic over subject key (e.g. `roomID`, or composite).
- Holds at most one underlying `NATSSubscription` per key.
- Cancels and unsubscribes when no consumers remain.
- Surfaces decode errors to consumers without killing the stream (one bad frame must not silently close all consumers).
- **Pins `ChatClient.stop()` semantics for streams** — what happens to active consumer iterators when `stop()` is called (terminate cleanly? throw?). B1–B4 inherit whatever B0 decides; don't redecide per stream.

**Depends on:** nothing — orthogonal to Group A.

**Done when:** unit tests cover (a) two consumers on the same key share one underlying subscription, (b) closing one consumer leaves the other intact, (c) closing the last consumer unsubscribes, (d) opening again after full close creates a fresh subscription.

#### B1 — Room event stream

**Goal:** public API `func roomEvents(roomID: String) -> AsyncStream<RoomEvent>` on `ChatClient`, backed by a subscription to `chat.room.{roomID}.event`.

**Depends on:** B0.

**Done when:** Subjects entry, `RoomEvent` decoder, public method, tests for: subscribe → inject frame → consumer receives; cancel iterator → underlying subscription torn down (when no other consumers); two consumers on same room share one sub.

#### B2 — User notification stream

**Goal:** public `func notifications() -> AsyncStream<UserNotification>`, backed by `chat.user.{account}.notification`.

**Depends on:** B0. (Independent of B1.)

**Done when:** as B1, scoped to the user account established at `start()`.

#### B3 — Presence

**Goal:** public API for online/offline state. Could be a stream of presence events or a queryable snapshot — pin at brainstorm against the chat spec.

**Depends on:** B0. (Independent of B1, B2.)

**Done when:** as B1, plus whatever symmetric publish (if presence requires the client to announce itself) is also exercised.

**Escape hatch:** if brainstorm reveals presence needs a roster/cache layer (online users in a room, last-seen, etc.), split into B3-a (raw event stream) and B3-b (roster cache) before writing the plan.

#### B4 — Typing indicator

**Goal:** public API for typing start/stop — bidirectional (subscribe to others' typing + publish own typing).

**Depends on:** B0. (Independent of B1–B3.)

**Done when:** subscribe and publish paths both covered; tests confirm publish does not echo into local stream unless the server does so.

**Escape hatch:** if brainstorm reveals typing needs debounce/throttle on the publish side, split into B4-a (subscribe) and B4-b (publish with rate limit) before writing the plan.

---

## Recommended order

```
A0
 ├── A1, A2, A3, A4   (independent; pick any order or run in parallel)
B0
 ├── B1, B2, B3, B4   (independent; pick any order or run in parallel)
```

**Rationale:**
- A0 first — every A* sub-project depends on it, and it's a pure refactor with no public-API change, so it lands cheaply.
- A1–A4 are independent once A0 lands. Order by user-visible value or by which surface the chat API spec documents most clearly. Room (A1) is usually the natural first because history (A2) and search (A3) read against rooms.
- B0 before any B* for the same reason as A0.
- B1–B4 are independent and can be parallelized.
- Group A before Group B is a soft preference, not a hard dependency. They share no code beyond what already exists in v1. Swap if streams unblock something more important.

## How to use this document

For each sub-project, when its turn comes:

1. Run `/superpowers:brainstorming <sub-project>` to produce a design doc under `docs/superpowers/specs/`.
2. Run `superpowers:writing-plans` against that design to produce a plan under `docs/superpowers/plans/`.
3. Implement the plan; on completion check the sub-project off in this document with a link to its design + plan.

## Status table

| # | Sub-project | Blocked by | Design | Plan | Done |
|---|-------------|------------|--------|------|------|
| A0 | Req/reply infra extraction | — | — | — | ☐ |
| A1 | Room service | A0 | — | — | ☐ |
| A2 | History service | A0 | — | — | ☐ |
| A3 | Search service | A0 | — | — | ☐ |
| A4 | User service | A0 | — | — | ☐ |
| B0 | Subscription lifecycle infra | — | — | — | ☐ |
| B1 | Room event stream | B0 | — | — | ☐ |
| B2 | User notification stream | B0 | — | — | ☐ |
| B3 | Presence | B0 | — | — | ☐ |
| B4 | Typing indicator | B0 | — | — | ☐ |
