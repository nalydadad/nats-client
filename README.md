# NATSChatClient

Typed Swift client for the chat server's NATS request/reply API. v1 covers
`§4 message send + async response`.

## Library

```swift
import NATSChatClient

let client = ChatClient(transport: myTransport, auth: myAuthProvider)
try await client.start()
let sent = try await client.sendMessage(roomID: "R1", siteID: "S1", content: "hi")
print(sent.id, sent.createdAt)
```

Implement `NATSTransport` against your NATS library of choice. The package itself has zero NATS dependencies.

## Demo

`Sources/ChatClientDemo/` is a macOS SwiftUI app wired to `nats-io/nats.swift`. Edit `DemoConfig.swift` with your NATS URL, account, and JWT, then:

```bash
swift run ChatClientDemo
```

`DemoConfig.swift` ships with placeholder values. Do not commit real credentials. After editing, mark the file skip-worktree:

```bash
git update-index --skip-worktree Sources/ChatClientDemo/DemoConfig.swift
```

## Tests

```bash
swift test
```

All tests run against `MockTransport` — no live NATS required.

## Scope (v1)

In: §4 message send + async response.
Out: §3 req/reply services (room, history, search, user), event streams, HTTP `/auth`.
