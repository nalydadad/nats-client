# NATS Chat Client (Swift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Swift Package `NATSChatClient` that lets a caller send a chat message and `await` its server-confirmed reply over NATS, plus a SwiftUI demo target wired to `nats-io/nats.swift` for hands-on testing.

**Architecture:** A `ChatClient` actor owns one shared subscription to `chat.user.{account}.response.>` and demuxes replies by `requestID` to per-call `CheckedContinuation`s held in a `PendingRequests` actor. The NATS transport and the auth provider are injected behind `Sendable` protocols so the library is unit-testable with no live server. v1 covers only §4 (message send + async response) from the chat API spec.

**Tech Stack:** Swift 5.9, async/await, `actor`, `AsyncStream`, `Codable` / `JSONEncoder`/`JSONDecoder`, SwiftUI for the demo. Library has zero external deps; the demo target depends on `https://github.com/nats-io/nats.swift`.

**Spec:** `docs/superpowers/specs/2026-05-15-nats-chat-client-design.md`.

**Platform notes for the demo:** SwiftPM doesn't build native iOS `.app` bundles. The demo target in this plan is a **macOS SwiftUI executable**. The library target itself supports both iOS 15+ and macOS 12+; an iOS host app can wrap it later via an Xcode project.

---

## File map

**Library — `Sources/NATSChatClient/`**

| File | Responsibility |
|------|----------------|
| `NATSTransport.swift` | `NATSTransport` protocol, `NATSMessage`, `NATSSubscription` |
| `AuthProvider.swift` | `AuthProvider` protocol, `AuthIdentity` |
| `Subjects.swift` | Pure subject builders + reverse parser |
| `IDGenerator.swift` | `UUIDv7` generator (monotonic), `Base62` random ID |
| `PendingRequests.swift` | Actor mapping `requestID → CheckedContinuation`, with buffered-arrival support |
| `Responder.swift` | Long-running `Task` that reads the shared subscription and routes by requestID |
| `ChatClient.swift` | Public actor: `start()`, `stop()`, `sendMessage(...)` |
| `Models/SentMessage.swift` | Public success type |
| `Models/SendMessageRequest.swift` | Internal `Encodable` wire body |
| `Models/ChatClientError.swift` | Public typed error enum |

**Tests — `Tests/NATSChatClientTests/`**

| File | Responsibility |
|------|----------------|
| `IDGeneratorTests.swift` | UUIDv7 format/monotonicity, Base62 charset/length |
| `SubjectsTests.swift` | Subject builders + parser |
| `PendingRequestsTests.swift` | Register/deliver/buffer/fail/cancelAll |
| `ChatClientTests.swift` | Lifecycle, happy path, server error, timeout, concurrency |
| `Support/MockTransport.swift` | In-memory `NATSTransport` with reply injection |
| `Support/MockAuthProvider.swift` | Canned `AuthIdentity` |

**Demo — `Sources/ChatClientDemo/`**

| File | Responsibility |
|------|----------------|
| `ChatClientDemoApp.swift` | `@main`, constructs and starts `ChatClient` |
| `DemoConfig.swift` | Hard-coded NATS URL / account / JWT (placeholders) |
| `NatsSwiftTransport.swift` | `NATSTransport` adapter over `nats-io/nats.swift` |
| `StaticAuthProvider.swift` | `AuthProvider` returning `DemoConfig` values |
| `SendMessageView.swift` | Form: roomID, siteID, content, optional fields |
| `ResultView.swift` | Renders `SentMessage` or `ChatClientError` |

**Package — `Package.swift`** at repo root.

---

## Task 1: Initialize the Swift package skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/NATSChatClient/Placeholder.swift`
- Create: `Tests/NATSChatClientTests/PlaceholderTests.swift`
- Create: `.gitignore` additions for `.build/`, `.swiftpm/`, `*.xcodeproj/`

- [ ] **Step 1: Add SwiftPM build artifacts to `.gitignore`**

Append to `.gitignore`:

```
# Swift / SPM
.build/
.swiftpm/
Package.resolved
DerivedData/
*.xcodeproj/
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NATSChatClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "NATSChatClient", targets: ["NATSChatClient"]),
    ],
    targets: [
        .target(
            name: "NATSChatClient",
            path: "Sources/NATSChatClient"
        ),
        .testTarget(
            name: "NATSChatClientTests",
            dependencies: ["NATSChatClient"],
            path: "Tests/NATSChatClientTests"
        ),
    ]
)
```

- [ ] **Step 3: Add placeholder sources so the package compiles**

`Sources/NATSChatClient/Placeholder.swift`:

```swift
// Will be removed in Task 2.
internal enum _Placeholder {}
```

`Tests/NATSChatClientTests/PlaceholderTests.swift`:

```swift
import XCTest
@testable import NATSChatClient

final class PlaceholderTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertNotNil(_Placeholder.self)
    }
}
```

- [ ] **Step 4: Build and test**

Run: `swift build`
Expected: Build succeeds.

Run: `swift test`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ Tests/ .gitignore
git commit -m "feat: initialize NATSChatClient Swift package skeleton"
```

---

## Task 2: ID Generator — Base62

**Files:**
- Create: `Sources/NATSChatClient/IDGenerator.swift`
- Create: `Tests/NATSChatClientTests/IDGeneratorTests.swift`
- Delete: `Sources/NATSChatClient/Placeholder.swift` and `Tests/NATSChatClientTests/PlaceholderTests.swift`

- [ ] **Step 1: Write the failing Base62 tests**

Create `Tests/NATSChatClientTests/IDGeneratorTests.swift`:

```swift
import XCTest
@testable import NATSChatClient

final class IDGeneratorTests: XCTestCase {
    private let base62Charset = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    func test_base62_hasLength20() {
        let id = Base62.randomID(length: 20)
        XCTAssertEqual(id.count, 20)
    }

    func test_base62_onlyUsesAllowedCharacters() {
        let id = Base62.randomID(length: 20)
        XCTAssertTrue(id.allSatisfy { base62Charset.contains($0) },
                      "Found out-of-alphabet character in \(id)")
    }

    func test_base62_producesDifferentValues() {
        let a = Base62.randomID(length: 20)
        let b = Base62.randomID(length: 20)
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Delete the placeholder files and run tests to confirm failure**

Delete `Sources/NATSChatClient/Placeholder.swift` and `Tests/NATSChatClientTests/PlaceholderTests.swift`:

```bash
rm Sources/NATSChatClient/Placeholder.swift Tests/NATSChatClientTests/PlaceholderTests.swift
```

Run: `swift test`
Expected: FAIL — `Base62` is undefined.

- [ ] **Step 3: Implement Base62**

Create `Sources/NATSChatClient/IDGenerator.swift`:

```swift
import Foundation

enum Base62 {
    static let alphabet: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    static func randomID(length: Int) -> String {
        precondition(length >= 0)
        var rng = SystemRandomNumberGenerator()
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            let idx = Int.random(in: 0..<alphabet.count, using: &rng)
            out.append(alphabet[idx])
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: 3 Base62 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NATSChatClient/IDGenerator.swift Tests/NATSChatClientTests/IDGeneratorTests.swift Sources/NATSChatClient/Placeholder.swift Tests/NATSChatClientTests/PlaceholderTests.swift
git commit -m "feat: add Base62 random ID generator"
```

---

## Task 3: ID Generator — UUIDv7 (monotonic)

**Files:**
- Modify: `Sources/NATSChatClient/IDGenerator.swift`
- Modify: `Tests/NATSChatClientTests/IDGeneratorTests.swift`

- [ ] **Step 1: Append failing UUIDv7 tests**

Append to `Tests/NATSChatClientTests/IDGeneratorTests.swift` (inside the class):

```swift
    // MARK: - UUIDv7

    func test_uuidv7_hasCorrectShape() {
        let s = UUIDv7.next()
        XCTAssertEqual(s.count, 36, "Should be 36 chars; got \(s)")
        let parts = s.split(separator: "-").map(String.init)
        XCTAssertEqual(parts.map(\.count), [8, 4, 4, 4, 12])
    }

    func test_uuidv7_versionNibbleIs7() {
        let s = UUIDv7.next()
        // 8-4-4-4-12: version nibble is the 1st char of the 3rd group
        let parts = s.split(separator: "-")
        XCTAssertEqual(parts[2].first, "7")
    }

    func test_uuidv7_variantBitsAre10() {
        let s = UUIDv7.next()
        // First char of the 4th group must be in {8,9,a,b}
        let parts = s.split(separator: "-")
        let variantChar = parts[3].first!
        XCTAssertTrue("89ab".contains(variantChar),
                      "Variant nibble was \(variantChar)")
    }

    func test_uuidv7_isHexAndLowercase() {
        let s = UUIDv7.next()
        let allowed = Set("0123456789abcdef-")
        XCTAssertTrue(s.allSatisfy { allowed.contains($0) },
                      "Found non-hex char in \(s)")
    }

    func test_uuidv7_isMonotonicAcrossRapidCalls() {
        var prev = UUIDv7.next()
        for _ in 0..<1000 {
            let next = UUIDv7.next()
            XCTAssertLessThan(prev, next,
                              "UUIDv7 not monotonic: \(prev) >= \(next)")
            prev = next
        }
    }
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test`
Expected: FAIL — `UUIDv7` undefined.

- [ ] **Step 3: Implement UUIDv7**

Append to `Sources/NATSChatClient/IDGenerator.swift`:

```swift
/// RFC 9562 §5.7 UUID Version 7 generator with millisecond + counter monotonicity.
enum UUIDv7 {
    private static let lock = NSLock()
    private static var lastUnixMs: UInt64 = 0
    /// 12-bit monotonic counter used when the timestamp has not advanced.
    private static var lastCounter: UInt16 = 0

    /// Returns a new UUIDv7 string in canonical 8-4-4-4-12 lowercase hex.
    static func next() -> String {
        var rng = SystemRandomNumberGenerator()
        let (unixMs, rand12) = nextTimestampAndRand12(rng: &rng)

        // 62 random bits for the trailing portion.
        let rand64 = UInt64.random(in: 0...UInt64.max, using: &rng)
        // Variant bits: top two bits of byte 8 must be 10.
        let rand62 = rand64 & 0x3FFF_FFFF_FFFF_FFFF
        let variantedHigh16 = UInt16((rand62 >> 48) & 0xFFFF) | 0x8000

        // Build the 16 bytes.
        var bytes = [UInt8](repeating: 0, count: 16)
        // 48-bit big-endian unix_ts_ms
        bytes[0] = UInt8((unixMs >> 40) & 0xFF)
        bytes[1] = UInt8((unixMs >> 32) & 0xFF)
        bytes[2] = UInt8((unixMs >> 24) & 0xFF)
        bytes[3] = UInt8((unixMs >> 16) & 0xFF)
        bytes[4] = UInt8((unixMs >> 8)  & 0xFF)
        bytes[5] = UInt8(unixMs & 0xFF)
        // Version (0x7) in high nibble of byte 6 + high 4 bits of rand12.
        bytes[6] = 0x70 | UInt8((rand12 >> 8) & 0x0F)
        bytes[7] = UInt8(rand12 & 0xFF)
        // Variant + top of rand62
        bytes[8]  = UInt8((variantedHigh16 >> 8) & 0xFF)
        bytes[9]  = UInt8(variantedHigh16 & 0xFF)
        bytes[10] = UInt8((rand62 >> 40) & 0xFF)
        bytes[11] = UInt8((rand62 >> 32) & 0xFF)
        bytes[12] = UInt8((rand62 >> 24) & 0xFF)
        bytes[13] = UInt8((rand62 >> 16) & 0xFF)
        bytes[14] = UInt8((rand62 >> 8)  & 0xFF)
        bytes[15] = UInt8(rand62 & 0xFF)

        return formatHex(bytes)
    }

    private static func nextTimestampAndRand12(
        rng: inout SystemRandomNumberGenerator
    ) -> (unixMs: UInt64, rand12: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        var unixMs = nowMs
        var counter: UInt16
        if nowMs > lastUnixMs {
            unixMs = nowMs
            counter = UInt16.random(in: 0...0x0FFF, using: &rng)
        } else {
            // Same or earlier ms — keep the larger ms and bump counter.
            unixMs = lastUnixMs
            if lastCounter == 0x0FFF {
                // Counter would overflow; nudge the ms forward.
                unixMs &+= 1
                counter = UInt16.random(in: 0...0x0FFF, using: &rng)
            } else {
                counter = lastCounter &+ 1
            }
        }
        lastUnixMs = unixMs
        lastCounter = counter
        return (unixMs, counter)
    }

    private static func formatHex(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        // Insert hyphens: 8-4-4-4-12
        let chars = Array(hex)
        return String(chars[0..<8])  + "-" +
               String(chars[8..<12]) + "-" +
               String(chars[12..<16]) + "-" +
               String(chars[16..<20]) + "-" +
               String(chars[20..<32])
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All ID generator tests pass (3 Base62 + 5 UUIDv7).

- [ ] **Step 5: Commit**

```bash
git add Sources/NATSChatClient/IDGenerator.swift Tests/NATSChatClientTests/IDGeneratorTests.swift
git commit -m "feat: add monotonic UUIDv7 generator"
```

---

## Task 4: Subjects builder

**Files:**
- Create: `Sources/NATSChatClient/Subjects.swift`
- Create: `Tests/NATSChatClientTests/SubjectsTests.swift`

- [ ] **Step 1: Write failing subject tests**

Create `Tests/NATSChatClientTests/SubjectsTests.swift`:

```swift
import XCTest
@testable import NATSChatClient

final class SubjectsTests: XCTestCase {
    func test_msgSend_substitutesAllPlaceholders() {
        let s = Subjects.msgSend(account: "alice", roomID: "ROOM1", siteID: "site-a")
        XCTAssertEqual(s, "chat.user.alice.room.ROOM1.site-a.msg.send")
    }

    func test_userResponseWildcard_isCorrect() {
        let s = Subjects.userResponseWildcard(account: "alice")
        XCTAssertEqual(s, "chat.user.alice.response.>")
    }

    func test_parseRequestID_extractsTrailingToken() {
        let subject = "chat.user.alice.response.018f8b0a-1234-7abc-9def-aabbccddeeff"
        XCTAssertEqual(
            Subjects.parseRequestID(fromResponseSubject: subject),
            "018f8b0a-1234-7abc-9def-aabbccddeeff"
        )
    }

    func test_parseRequestID_returnsNilForMalformedSubject() {
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: "chat.user.alice"))
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: "chat.user.alice.event.x"))
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: ""))
    }

    func test_parseRequestID_requiresAccountSegment() {
        // Wrong prefix: not chat.user.*.response.*
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: "chat.room.alice.response.id"))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test`
Expected: FAIL — `Subjects` undefined.

- [ ] **Step 3: Implement `Subjects`**

Create `Sources/NATSChatClient/Subjects.swift`:

```swift
import Foundation

enum Subjects {
    static func msgSend(account: String, roomID: String, siteID: String) -> String {
        "chat.user.\(account).room.\(roomID).\(siteID).msg.send"
    }

    static func userResponseWildcard(account: String) -> String {
        "chat.user.\(account).response.>"
    }

    /// Returns the trailing requestID token from a subject of shape
    /// `chat.user.{account}.response.{requestID}`. Returns nil for any other shape.
    static func parseRequestID(fromResponseSubject subject: String) -> String? {
        let parts = subject.split(separator: ".", omittingEmptySubsequences: false)
        // Expect exactly 5 segments: chat / user / {account} / response / {requestID}
        guard parts.count == 5,
              parts[0] == "chat",
              parts[1] == "user",
              parts[3] == "response",
              !parts[2].isEmpty,
              !parts[4].isEmpty
        else { return nil }
        return String(parts[4])
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All Subjects tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NATSChatClient/Subjects.swift Tests/NATSChatClientTests/SubjectsTests.swift
git commit -m "feat: add subject builders for §4 message-send + response"
```

---

## Task 5: Public protocols and models

**Files:**
- Create: `Sources/NATSChatClient/NATSTransport.swift`
- Create: `Sources/NATSChatClient/AuthProvider.swift`
- Create: `Sources/NATSChatClient/Models/SentMessage.swift`
- Create: `Sources/NATSChatClient/Models/SendMessageRequest.swift`
- Create: `Sources/NATSChatClient/Models/ChatClientError.swift`

- [ ] **Step 1: Create `NATSTransport.swift`**

```swift
import Foundation

public struct NATSMessage: Sendable, Equatable {
    public let subject: String
    public let payload: Data

    public init(subject: String, payload: Data) {
        self.subject = subject
        self.payload = payload
    }
}

public protocol NATSSubscription: Sendable {
    /// AsyncStream of inbound messages on this subscription.
    /// The stream finishes when `cancel()` is called or the transport tears it down.
    var messages: AsyncStream<NATSMessage> { get }
    func cancel() async
}

public protocol NATSTransport: Sendable {
    /// Publish a payload to `subject`.
    func publish(subject: String, payload: Data) async throws

    /// Subscribe to `subject`. The subject may contain wildcards (`*`, `>`).
    func subscribe(subject: String) async throws -> any NATSSubscription
}
```

- [ ] **Step 2: Create `AuthProvider.swift`**

```swift
import Foundation

public struct AuthIdentity: Sendable, Equatable {
    public let account: String
    public let natsJwt: String

    public init(account: String, natsJwt: String) {
        self.account = account
        self.natsJwt = natsJwt
    }
}

public protocol AuthProvider: Sendable {
    /// Returns the current authenticated identity. May refresh as needed.
    func currentIdentity() async throws -> AuthIdentity
}
```

- [ ] **Step 3: Create `Models/SentMessage.swift`**

```swift
import Foundation

public struct SentMessage: Sendable, Equatable {
    public let id: String                              // 20-char base62
    public let requestID: String                       // UUIDv7
    public let roomID: String
    public let userID: String
    public let userAccount: String
    public let content: String
    public let createdAt: String                       // RFC 3339
    public let threadParentMessageID: String?
    public let threadParentMessageCreatedAt: Int64?
    public let quotedParentMessageID: String?

    public init(
        id: String,
        requestID: String,
        roomID: String,
        userID: String,
        userAccount: String,
        content: String,
        createdAt: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.roomID = roomID
        self.userID = userID
        self.userAccount = userAccount
        self.content = content
        self.createdAt = createdAt
        self.threadParentMessageID = threadParentMessageID
        self.threadParentMessageCreatedAt = threadParentMessageCreatedAt
        self.quotedParentMessageID = quotedParentMessageID
    }
}

/// Internal: decodes server reply payload (success branch) into a SentMessage.
/// Server JSON keys are camelCase per the spec.
struct SentMessageDTO: Decodable {
    let id: String
    let roomId: String
    let userId: String
    let userAccount: String
    let content: String
    let createdAt: String
    let threadParentMessageId: String?
    let threadParentMessageCreatedAt: Int64?
    let quotedParentMessageId: String?

    func toModel(requestID: String) -> SentMessage {
        SentMessage(
            id: id,
            requestID: requestID,
            roomID: roomId,
            userID: userId,
            userAccount: userAccount,
            content: content,
            createdAt: createdAt,
            threadParentMessageID: threadParentMessageId,
            threadParentMessageCreatedAt: threadParentMessageCreatedAt,
            quotedParentMessageID: quotedParentMessageId
        )
    }
}

/// Internal: decodes server reply payload (error branch) per §5 envelope.
struct ErrorEnvelopeDTO: Decodable {
    let error: String
    let code: String?
}
```

- [ ] **Step 4: Create `Models/SendMessageRequest.swift`**

```swift
import Foundation

/// Wire body for `chat.user.{account}.room.{roomID}.{siteID}.msg.send`.
/// Optional fields are omitted entirely when nil (not encoded as JSON null).
struct SendMessageRequest: Encodable {
    let id: String
    let content: String
    let requestId: String
    let threadParentMessageId: String?
    let threadParentMessageCreatedAt: Int64?
    let quotedParentMessageId: String?

    private enum CodingKeys: String, CodingKey {
        case id, content, requestId
        case threadParentMessageId, threadParentMessageCreatedAt
        case quotedParentMessageId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(requestId, forKey: .requestId)
        try c.encodeIfPresent(threadParentMessageId, forKey: .threadParentMessageId)
        try c.encodeIfPresent(threadParentMessageCreatedAt, forKey: .threadParentMessageCreatedAt)
        try c.encodeIfPresent(quotedParentMessageId, forKey: .quotedParentMessageId)
    }
}
```

- [ ] **Step 5: Create `Models/ChatClientError.swift`**

```swift
import Foundation

public enum ChatClientError: Error, Sendable {
    case notStarted
    case timeout(requestID: String)
    case server(code: String?, message: String)
    case transport(any Error)
    case invalidPayload(String)
}

extension ChatClientError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notStarted:
            return "ChatClient has not been started. Call start() first."
        case .timeout(let id):
            return "Timed out waiting for response to request \(id)."
        case .server(let code, let message):
            return "Server error\(code.map { " [\($0)]" } ?? ""): \(message)"
        case .transport(let err):
            return "Transport error: \(err)"
        case .invalidPayload(let detail):
            return "Invalid payload: \(detail)"
        }
    }
}
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: Build succeeds (no new tests yet — exercised by later tasks).

- [ ] **Step 7: Commit**

```bash
git add Sources/NATSChatClient/
git commit -m "feat: add transport/auth protocols, models, and error type"
```

---

## Task 6: Mock test support — MockTransport and MockAuthProvider

**Files:**
- Create: `Tests/NATSChatClientTests/Support/MockTransport.swift`
- Create: `Tests/NATSChatClientTests/Support/MockAuthProvider.swift`

- [ ] **Step 1: Create `MockAuthProvider`**

`Tests/NATSChatClientTests/Support/MockAuthProvider.swift`:

```swift
import Foundation
@testable import NATSChatClient

final class MockAuthProvider: AuthProvider {
    let identity: AuthIdentity
    init(account: String = "alice", natsJwt: String = "test-jwt") {
        self.identity = AuthIdentity(account: account, natsJwt: natsJwt)
    }
    func currentIdentity() async throws -> AuthIdentity { identity }
}
```

- [ ] **Step 2: Create `MockTransport`**

`Tests/NATSChatClientTests/Support/MockTransport.swift`:

```swift
import Foundation
@testable import NATSChatClient

/// In-memory NATS transport for tests.
/// - Records every publish so assertions can verify subject/payload.
/// - Lets tests inject server replies onto active subscriptions via `deliver(...)`.
/// - Optional `publishError` lets tests simulate publish failures.
actor MockTransport: NATSTransport {

    struct PublishedMessage: Equatable {
        let subject: String
        let payload: Data
    }

    private(set) var published: [PublishedMessage] = []
    var publishError: (any Error)?

    // Active subscriptions keyed by their subject filter.
    private var subscriptions: [String: AsyncStream<NATSMessage>.Continuation] = [:]

    func setPublishError(_ err: (any Error)?) { self.publishError = err }

    // MARK: NATSTransport

    func publish(subject: String, payload: Data) async throws {
        if let e = publishError { throw e }
        published.append(PublishedMessage(subject: subject, payload: payload))
    }

    func subscribe(subject: String) async throws -> any NATSSubscription {
        var continuation: AsyncStream<NATSMessage>.Continuation!
        let stream = AsyncStream<NATSMessage> { continuation = $0 }
        subscriptions[subject] = continuation
        let weakSelf = self
        return MockSubscription(stream: stream, onCancel: { [subject] in
            await weakSelf.cancelSubscription(subject: subject)
        })
    }

    // MARK: Test helpers

    /// Deliver a message into every active subscription whose filter matches `subject`.
    /// Matching is wildcard-aware for the `>` suffix and bare prefix.
    func deliver(subject: String, payload: Data) {
        let msg = NATSMessage(subject: subject, payload: payload)
        for (filter, cont) in subscriptions where matches(filter: filter, subject: subject) {
            cont.yield(msg)
        }
    }

    private func cancelSubscription(subject: String) {
        if let cont = subscriptions.removeValue(forKey: subject) {
            cont.finish()
        }
    }

    private func matches(filter: String, subject: String) -> Bool {
        if filter == subject { return true }
        if filter.hasSuffix(".>") {
            let prefix = String(filter.dropLast(1)) // keep trailing dot
            return subject.hasPrefix(prefix)
        }
        return false
    }
}

private struct MockSubscription: NATSSubscription, @unchecked Sendable {
    let stream: AsyncStream<NATSMessage>
    let onCancel: @Sendable () async -> Void
    var messages: AsyncStream<NATSMessage> { stream }
    func cancel() async { await onCancel() }
}
```

- [ ] **Step 3: Build**

Run: `swift build --build-tests`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/NATSChatClientTests/Support/
git commit -m "test: add MockTransport and MockAuthProvider for unit tests"
```

---

## Task 7: PendingRequests actor

**Files:**
- Create: `Sources/NATSChatClient/PendingRequests.swift`
- Create: `Tests/NATSChatClientTests/PendingRequestsTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/NATSChatClientTests/PendingRequestsTests.swift`:

```swift
import XCTest
@testable import NATSChatClient

final class PendingRequestsTests: XCTestCase {

    func test_deliverBeforeWait_returnsBufferedPayload() async throws {
        let p = PendingRequests()
        await p.register("r1")

        let payload = Data("hello".utf8)
        await p.deliver("r1", payload: payload)

        let received = try await p.wait("r1")
        XCTAssertEqual(received, payload)
    }

    func test_waitThenDeliver_returnsPayload() async throws {
        let p = PendingRequests()
        await p.register("r2")

        async let received = p.wait("r2")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await p.deliver("r2", payload: Data("world".utf8))

        let value = try await received
        XCTAssertEqual(value, Data("world".utf8))
    }

    func test_fail_resumesPendingWaiter() async {
        let p = PendingRequests()
        await p.register("r3")

        async let result: Data = p.wait("r3")
        await p.fail("r3", error: ChatClientError.timeout(requestID: "r3"))

        do {
            _ = try await result
            XCTFail("Expected throw")
        } catch let err as ChatClientError {
            if case .timeout(let id) = err {
                XCTAssertEqual(id, "r3")
            } else {
                XCTFail("Wrong error case: \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_deliverUnknownID_isDroppedSilently() async throws {
        let p = PendingRequests()
        await p.deliver("unknown", payload: Data())
        // Nothing should crash; verify another flow still works.
        await p.register("r4")
        await p.deliver("r4", payload: Data("ok".utf8))
        let v = try await p.wait("r4")
        XCTAssertEqual(v, Data("ok".utf8))
    }

    func test_cancelAll_failsAllPendingWaiters() async {
        let p = PendingRequests()
        await p.register("a")
        await p.register("b")

        async let ra: Data = p.wait("a")
        async let rb: Data = p.wait("b")
        try? await Task.sleep(nanoseconds: 5_000_000)

        await p.cancelAll()

        await assertThrowsCancellation { _ = try await ra }
        await assertThrowsCancellation { _ = try await rb }
    }

    func test_discard_removesEntry() async throws {
        let p = PendingRequests()
        await p.register("r5")
        await p.discard("r5")
        // After discard, a deliver should be dropped.
        await p.deliver("r5", payload: Data("late".utf8))
        // Re-register works fresh:
        await p.register("r5")
        async let v: Data = p.wait("r5")
        await p.deliver("r5", payload: Data("fresh".utf8))
        let got = try await v
        XCTAssertEqual(got, Data("fresh".utf8))
    }

    // MARK: helpers

    private func assertThrowsCancellation(
        _ block: () async throws -> Void,
        file: StaticString = #file, line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("Expected CancellationError", file: file, line: line)
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)", file: file, line: line)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test`
Expected: FAIL — `PendingRequests` undefined.

- [ ] **Step 3: Implement `PendingRequests`**

`Sources/NATSChatClient/PendingRequests.swift`:

```swift
import Foundation

/// Routes server replies to per-request awaiters by `requestID`.
///
/// Slots track each registered request so that a reply arriving before the
/// caller suspends in `wait(_:)` is buffered rather than dropped.
actor PendingRequests {

    private enum Slot {
        case expecting                                            // registered, no waiter yet
        case pending(CheckedContinuation<Data, any Error>)        // suspended waiter
        case buffered(Data)                                       // reply arrived before wait
        case failed(any Error)                                    // fail before wait
    }

    private var slots: [String: Slot] = [:]

    /// Pre-registers a request so a fast reply can be buffered.
    func register(_ id: String) {
        // Idempotent — re-registering is a no-op if already expecting / pending.
        if slots[id] == nil {
            slots[id] = .expecting
        }
    }

    /// Suspends until the reply (or failure) for `id` is available.
    func wait(_ id: String) async throws -> Data {
        switch slots[id] {
        case .buffered(let data):
            slots.removeValue(forKey: id)
            return data
        case .failed(let err):
            slots.removeValue(forKey: id)
            throw err
        case .pending:
            // Should never happen in practice — caller shouldn't double-wait.
            fatalError("PendingRequests.wait called twice for \(id)")
        case .expecting, .none:
            return try await withCheckedThrowingContinuation { cont in
                slots[id] = .pending(cont)
            }
        }
    }

    /// Routes a reply payload to the waiter (or buffers it).
    func deliver(_ id: String?, payload: Data) {
        guard let id = id else { return }
        switch slots[id] {
        case .pending(let cont):
            slots.removeValue(forKey: id)
            cont.resume(returning: payload)
        case .expecting:
            slots[id] = .buffered(payload)
        case .none, .buffered, .failed:
            return                                                 // unknown or already done
        }
    }

    /// Fails a registered request.
    func fail(_ id: String, error: any Error) {
        switch slots[id] {
        case .pending(let cont):
            slots.removeValue(forKey: id)
            cont.resume(throwing: error)
        case .expecting:
            slots[id] = .failed(error)
        case .none, .buffered, .failed:
            return
        }
    }

    /// Drops the slot — used by senders on cleanup after success or after timeout.
    func discard(_ id: String) {
        slots.removeValue(forKey: id)
    }

    /// Fails every pending waiter with `CancellationError()` and clears all slots.
    func cancelAll() {
        for (_, slot) in slots {
            if case .pending(let cont) = slot {
                cont.resume(throwing: CancellationError())
            }
        }
        slots.removeAll()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All `PendingRequestsTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NATSChatClient/PendingRequests.swift Tests/NATSChatClientTests/PendingRequestsTests.swift
git commit -m "feat: add PendingRequests actor for requestID → continuation routing"
```

---

## Task 8: ChatClient skeleton — start/stop lifecycle and the demuxer

**Files:**
- Create: `Sources/NATSChatClient/ChatClient.swift`
- Create: `Tests/NATSChatClientTests/ChatClientTests.swift`

- [ ] **Step 1: Write failing lifecycle tests**

`Tests/NATSChatClientTests/ChatClientTests.swift`:

```swift
import XCTest
@testable import NATSChatClient

final class ChatClientTests: XCTestCase {

    func test_sendBeforeStart_throwsNotStarted() async {
        let transport = MockTransport()
        let auth = MockAuthProvider()
        let client = ChatClient(transport: transport, auth: auth)

        do {
            _ = try await client.sendMessage(
                roomID: "R1", siteID: "S1", content: "hi"
            )
            XCTFail("Expected ChatClientError.notStarted")
        } catch ChatClientError.notStarted {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_startStop_areIdempotent() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider()
        let client = ChatClient(transport: transport, auth: auth)

        try await client.start()
        try await client.start()             // idempotent
        await client.stop()
        await client.stop()                  // idempotent

        // After stop, sending should throw .notStarted again.
        do {
            _ = try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
            XCTFail("Expected .notStarted")
        } catch ChatClientError.notStarted {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test`
Expected: FAIL — `ChatClient` undefined.

- [ ] **Step 3: Create `Responder.swift`**

`Sources/NATSChatClient/Responder.swift`:

```swift
import Foundation

/// Reads inbound messages from the shared response subscription and routes
/// them to `PendingRequests` keyed by the trailing `requestID` token.
struct Responder {
    let subscription: any NATSSubscription
    let pending: PendingRequests

    func run() async {
        for await msg in subscription.messages {
            let id = Subjects.parseRequestID(fromResponseSubject: msg.subject)
            await pending.deliver(id, payload: msg.payload)
        }
    }
}
```

- [ ] **Step 4: Create `ChatClient.swift` with skeleton**

`Sources/NATSChatClient/ChatClient.swift`:

```swift
import Foundation

public actor ChatClient {

    private let transport: any NATSTransport
    private let auth: any AuthProvider
    private let defaultTimeout: TimeInterval
    private let pending = PendingRequests()

    // Lifecycle state
    private var account: String?
    private var subscription: (any NATSSubscription)?
    private var responderTask: Task<Void, Never>?

    public init(
        transport: any NATSTransport,
        auth: any AuthProvider,
        defaultTimeout: TimeInterval = 10
    ) {
        self.transport = transport
        self.auth = auth
        self.defaultTimeout = defaultTimeout
    }

    /// Resolves identity, opens the shared response subscription, starts the demuxer.
    /// Idempotent — safe to call multiple times.
    public func start() async throws {
        if responderTask != nil { return }
        let identity = try await auth.currentIdentity()
        let subject = Subjects.userResponseWildcard(account: identity.account)
        let sub = try await transport.subscribe(subject: subject)
        self.account = identity.account
        self.subscription = sub
        let responder = Responder(subscription: sub, pending: pending)
        self.responderTask = Task { await responder.run() }
    }

    /// Cancels the demuxer, fails pending waiters, unsubscribes. Idempotent.
    public func stop() async {
        responderTask?.cancel()
        responderTask = nil
        await pending.cancelAll()
        if let sub = subscription {
            await sub.cancel()
        }
        subscription = nil
        account = nil
    }

    // sendMessage(...) is added in Task 9.
    public func sendMessage(
        roomID: String,
        siteID: String,
        content: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> SentMessage {
        guard account != nil else { throw ChatClientError.notStarted }
        // Filled in by Task 9.
        throw ChatClientError.notStarted
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter ChatClientTests`
Expected: Both lifecycle tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/NATSChatClient/ChatClient.swift Sources/NATSChatClient/Responder.swift Tests/NATSChatClientTests/ChatClientTests.swift
git commit -m "feat: add ChatClient skeleton with start/stop and Responder"
```

---

## Task 9: ChatClient — sendMessage happy path

**Files:**
- Modify: `Sources/NATSChatClient/ChatClient.swift`
- Modify: `Tests/NATSChatClientTests/ChatClientTests.swift`

- [ ] **Step 1: Append failing happy-path test**

Append to `ChatClientTests` class:

```swift
    func test_sendMessage_publishesCorrectSubjectAndPayload() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        // Run sendMessage concurrently; complete it via injected reply.
        let sendTask = Task { [transport] in
            try await client.sendMessage(roomID: "R1", siteID: "S1", content: "hi")
        }

        // Wait until the publish lands, then read the requestId to craft the reply.
        let published = try await waitForPublish(in: transport)
        let req = try JSONDecoder().decode(SentBodyJSON.self, from: published.payload)
        XCTAssertEqual(published.subject, "chat.user.alice.room.R1.S1.msg.send")
        XCTAssertEqual(req.content, "hi")
        XCTAssertEqual(req.id.count, 20)
        XCTAssertEqual(req.requestId.count, 36)

        // Inject a successful server reply on the response subject.
        let reply = """
        {"id":"\(req.id)","roomId":"R1","userId":"u-1","userAccount":"alice","content":"hi","createdAt":"2026-05-15T00:00:00Z"}
        """.data(using: .utf8)!
        await transport.deliver(subject: "chat.user.alice.response.\(req.requestId)", payload: reply)

        let result = try await sendTask.value
        XCTAssertEqual(result.id, req.id)
        XCTAssertEqual(result.requestID, req.requestId)
        XCTAssertEqual(result.roomID, "R1")
        XCTAssertEqual(result.userID, "u-1")
        XCTAssertEqual(result.userAccount, "alice")
        XCTAssertEqual(result.content, "hi")
        XCTAssertEqual(result.createdAt, "2026-05-15T00:00:00Z")
    }

    // MARK: helpers

    private struct SentBodyJSON: Decodable {
        let id: String
        let content: String
        let requestId: String
        let threadParentMessageId: String?
        let threadParentMessageCreatedAt: Int64?
        let quotedParentMessageId: String?
    }

    /// Polls the mock transport until one publish has been recorded.
    private func waitForPublish(
        in transport: MockTransport,
        timeoutMs: Int = 1000
    ) async throws -> MockTransport.PublishedMessage {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            let all = await transport.published
            if let first = all.first { return first }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for publish")
        throw ChatClientError.timeout(requestID: "test-helper")
    }
```

Note: `transport.published` is `private(set)`; for tests we read it via `await`. If the test target can't see the storage, expose a tiny `func snapshot() -> [PublishedMessage]` on `MockTransport`. Add this method:

In `Tests/NATSChatClientTests/Support/MockTransport.swift`, replace `private(set) var published: [PublishedMessage] = []` with:

```swift
    private(set) var published: [PublishedMessage] = []
    func snapshot() -> [PublishedMessage] { published }
```

…and update `waitForPublish` to use `await transport.snapshot()`.

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter test_sendMessage_publishesCorrectSubjectAndPayload`
Expected: FAIL — current `sendMessage` always throws `.notStarted`.

- [ ] **Step 3: Implement `sendMessage`**

Replace the placeholder `sendMessage` in `ChatClient.swift` with:

```swift
    public func sendMessage(
        roomID: String,
        siteID: String,
        content: String,
        threadParentMessageID: String? = nil,
        threadParentMessageCreatedAt: Int64? = nil,
        quotedParentMessageID: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> SentMessage {
        guard let account = account else { throw ChatClientError.notStarted }

        let id = Base62.randomID(length: 20)
        let requestID = UUIDv7.next()
        let subject = Subjects.msgSend(account: account, roomID: roomID, siteID: siteID)

        let body = SendMessageRequest(
            id: id,
            content: content,
            requestId: requestID,
            threadParentMessageId: threadParentMessageID,
            threadParentMessageCreatedAt: threadParentMessageCreatedAt,
            quotedParentMessageId: quotedParentMessageID
        )

        let encoder = JSONEncoder()
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw ChatClientError.invalidPayload("encode failed: \(error)")
        }

        await pending.register(requestID)
        defer { Task { [pending] in await pending.discard(requestID) } }

        do {
            try await transport.publish(subject: subject, payload: payload)
        } catch {
            throw ChatClientError.transport(error)
        }

        let effectiveTimeout = timeout ?? defaultTimeout
        let data = try await raceWaitVsTimeout(
            requestID: requestID,
            seconds: effectiveTimeout
        )

        return try decodeReply(data, requestID: requestID)
    }

    private func raceWaitVsTimeout(
        requestID: String,
        seconds: TimeInterval
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            let p = self.pending
            group.addTask { try await p.wait(requestID) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ChatClientError.timeout(requestID: requestID)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func decodeReply(_ data: Data, requestID: String) throws -> SentMessage {
        let decoder = JSONDecoder()
        // Error branch first.
        if let env = try? decoder.decode(ErrorEnvelopeDTO.self, from: data),
           !env.error.isEmpty {
            throw ChatClientError.server(code: env.code, message: env.error)
        }
        do {
            let dto = try decoder.decode(SentMessageDTO.self, from: data)
            return dto.toModel(requestID: requestID)
        } catch {
            throw ChatClientError.invalidPayload("decode failed: \(error)")
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ChatClientTests`
Expected: All ChatClient tests so far pass (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/NATSChatClient/ChatClient.swift Tests/NATSChatClientTests/
git commit -m "feat: implement ChatClient.sendMessage happy path"
```

---

## Task 10: ChatClient — server error, timeout, concurrent, edge cases

**Files:**
- Modify: `Tests/NATSChatClientTests/ChatClientTests.swift`

- [ ] **Step 1: Append all remaining tests**

Append inside the `ChatClientTests` class:

```swift
    func test_sendMessage_serverErrorReply_throwsServerError() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        let task = Task { [client] in
            try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
        }
        let pub = try await waitForPublish(in: transport)
        let req = try JSONDecoder().decode(SentBodyJSON.self, from: pub.payload)

        let reply = #"{"error":"forbidden","code":"forbidden"}"#.data(using: .utf8)!
        await transport.deliver(subject: "chat.user.alice.response.\(req.requestId)", payload: reply)

        do {
            _ = try await task.value
            XCTFail("Expected throw")
        } catch let ChatClientError.server(code, message) {
            XCTAssertEqual(code, "forbidden")
            XCTAssertEqual(message, "forbidden")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_sendMessage_timeout_throwsTimeoutAndDropsLateReply() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth, defaultTimeout: 0.05)
        try await client.start()

        let task = Task { [client] in
            try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
        }
        let pub = try await waitForPublish(in: transport)
        let req = try JSONDecoder().decode(SentBodyJSON.self, from: pub.payload)

        do {
            _ = try await task.value
            XCTFail("Expected timeout")
        } catch let ChatClientError.timeout(id) {
            XCTAssertEqual(id, req.requestId)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        // Late reply must not crash and must be silently dropped.
        let reply = """
        {"id":"\(req.id)","roomId":"R","userId":"u","userAccount":"alice","content":"x","createdAt":"now"}
        """.data(using: .utf8)!
        await transport.deliver(subject: "chat.user.alice.response.\(req.requestId)", payload: reply)
        // Give the actor a moment to process — and assert we still pass.
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func test_sendMessage_concurrentSends_areDemuxedByRequestID() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        async let a: SentMessage = client.sendMessage(roomID: "R", siteID: "S", content: "A")
        async let b: SentMessage = client.sendMessage(roomID: "R", siteID: "S", content: "B")
        async let c: SentMessage = client.sendMessage(roomID: "R", siteID: "S", content: "C")

        // Wait until three publishes are recorded.
        let deadline = Date().addingTimeInterval(1.0)
        var pubs: [MockTransport.PublishedMessage] = []
        while pubs.count < 3, Date() < deadline {
            pubs = await transport.snapshot()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(pubs.count, 3)

        // Parse requestIDs and reply OUT OF ORDER.
        let reqs = try pubs.map { try JSONDecoder().decode(SentBodyJSON.self, from: $0.payload) }
        let order = [2, 0, 1]
        for i in order {
            let r = reqs[i]
            let reply = """
            {"id":"\(r.id)","roomId":"R","userId":"u","userAccount":"alice","content":"\(r.content)","createdAt":"t"}
            """.data(using: .utf8)!
            await transport.deliver(subject: "chat.user.alice.response.\(r.requestId)", payload: reply)
        }

        let results = try await [a, b, c]
        XCTAssertEqual(results.map(\.content), ["A", "B", "C"])
        XCTAssertEqual(results.map(\.requestID), reqs.map(\.requestId))
    }

    func test_sendMessage_invalidJSON_throwsInvalidPayload() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        let task = Task { [client] in
            try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
        }
        let pub = try await waitForPublish(in: transport)
        let req = try JSONDecoder().decode(SentBodyJSON.self, from: pub.payload)

        await transport.deliver(
            subject: "chat.user.alice.response.\(req.requestId)",
            payload: Data("not json".utf8)
        )

        do {
            _ = try await task.value
            XCTFail("Expected throw")
        } catch ChatClientError.invalidPayload {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_sendMessage_publishFailure_throwsTransport() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        struct Boom: Error {}
        await transport.setPublishError(Boom())

        do {
            _ = try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
            XCTFail("Expected throw")
        } catch ChatClientError.transport {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_sendMessage_optionalFields_areOmittedWhenNil() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        let task = Task { [client] in
            try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
        }
        let pub = try await waitForPublish(in: transport)
        let json = try JSONSerialization.jsonObject(with: pub.payload) as! [String: Any]
        XCTAssertNil(json["threadParentMessageId"])
        XCTAssertNil(json["threadParentMessageCreatedAt"])
        XCTAssertNil(json["quotedParentMessageId"])

        // Reply to let sendMessage complete cleanly.
        let req = try JSONDecoder().decode(SentBodyJSON.self, from: pub.payload)
        let reply = """
        {"id":"\(req.id)","roomId":"R","userId":"u","userAccount":"alice","content":"x","createdAt":"t"}
        """.data(using: .utf8)!
        await transport.deliver(subject: "chat.user.alice.response.\(req.requestId)", payload: reply)
        _ = try await task.value
    }

    func test_sendMessage_optionalFields_areEncodedWhenProvided() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        let task = Task { [client] in
            try await client.sendMessage(
                roomID: "R", siteID: "S", content: "x",
                threadParentMessageID: "p1",
                threadParentMessageCreatedAt: 1_700_000_000_000,
                quotedParentMessageID: "q1"
            )
        }
        let pub = try await waitForPublish(in: transport)
        let json = try JSONSerialization.jsonObject(with: pub.payload) as! [String: Any]
        XCTAssertEqual(json["threadParentMessageId"] as? String, "p1")
        XCTAssertEqual(json["threadParentMessageCreatedAt"] as? Int64, 1_700_000_000_000)
        XCTAssertEqual(json["quotedParentMessageId"] as? String, "q1")

        let req = try JSONDecoder().decode(SentBodyJSON.self, from: pub.payload)
        let reply = """
        {"id":"\(req.id)","roomId":"R","userId":"u","userAccount":"alice","content":"x","createdAt":"t","threadParentMessageId":"p1","threadParentMessageCreatedAt":1700000000000,"quotedParentMessageId":"q1"}
        """.data(using: .utf8)!
        await transport.deliver(subject: "chat.user.alice.response.\(req.requestId)", payload: reply)
        let result = try await task.value
        XCTAssertEqual(result.threadParentMessageID, "p1")
        XCTAssertEqual(result.threadParentMessageCreatedAt, 1_700_000_000_000)
        XCTAssertEqual(result.quotedParentMessageID, "q1")
    }

    func test_unknownRequestID_onResponseSubject_isDropped() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth, defaultTimeout: 0.05)
        try await client.start()

        // No registered requests — random reply must not crash anything.
        await transport.deliver(
            subject: "chat.user.alice.response.does-not-exist",
            payload: Data(#"{"id":"x"}"#.utf8)
        )

        // Subsequent normal send still works.
        let task = Task { [client] in
            try? await client.sendMessage(roomID: "R", siteID: "S", content: "x")
        }
        let pub = try await waitForPublish(in: transport)
        let req = try JSONDecoder().decode(SentBodyJSON.self, from: pub.payload)
        let reply = """
        {"id":"\(req.id)","roomId":"R","userId":"u","userAccount":"alice","content":"x","createdAt":"t"}
        """.data(using: .utf8)!
        await transport.deliver(subject: "chat.user.alice.response.\(req.requestId)", payload: reply)
        let result = await task.value
        XCTAssertNotNil(result)
    }
```

- [ ] **Step 2: Run tests**

Run: `swift test`
Expected: All ChatClient tests pass (lifecycle + happy path + 8 new edge cases).

- [ ] **Step 3: Commit**

```bash
git add Tests/NATSChatClientTests/ChatClientTests.swift
git commit -m "test: cover server error, timeout, concurrency, edge cases"
```

---

## Task 11: Demo target — Package.swift wiring + DemoConfig + auth provider

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ChatClientDemo/DemoConfig.swift`
- Create: `Sources/ChatClientDemo/StaticAuthProvider.swift`

- [ ] **Step 1: Update `Package.swift` to add demo target and nats.swift dependency**

Replace the package contents with:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NATSChatClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "NATSChatClient", targets: ["NATSChatClient"]),
        .executable(name: "ChatClientDemo", targets: ["ChatClientDemo"]),
    ],
    dependencies: [
        // Pin to a specific tag once verified against the repo's released versions.
        .package(url: "https://github.com/nats-io/nats.swift.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "NATSChatClient",
            path: "Sources/NATSChatClient"
        ),
        .executableTarget(
            name: "ChatClientDemo",
            dependencies: [
                "NATSChatClient",
                .product(name: "Nats", package: "nats.swift"),
            ],
            path: "Sources/ChatClientDemo"
        ),
        .testTarget(
            name: "NATSChatClientTests",
            dependencies: ["NATSChatClient"],
            path: "Tests/NATSChatClientTests"
        ),
    ]
)
```

Note on the product name: if `swift package show-dependencies` reports a product name other than `Nats`, update the `.product(name:)` argument accordingly. Common alternatives: `NatsSwift`, `nats-swift`. Resolve via:

Run: `swift package resolve`
Then: `swift package show-dependencies --format json | grep -i nats`

Pick the actual product name and update the `Package.swift` line.

- [ ] **Step 2: Create `DemoConfig.swift`**

`Sources/ChatClientDemo/DemoConfig.swift`:

```swift
import Foundation

/// Hard-coded demo configuration. Replace placeholder values before running.
///
/// ⚠️ Do NOT commit real credentials. After editing, either:
///   - keep this file out of git (`git update-index --skip-worktree Sources/ChatClientDemo/DemoConfig.swift`), or
///   - move secrets to a local untracked file.
enum DemoConfig {
    static let natsURL  = "nats://localhost:4222"
    static let account  = "REPLACE_ME_ACCOUNT"
    static let natsJwt  = "REPLACE_ME_JWT"
    static let defaultRoomID = "REPLACE_ME_ROOM"
    static let defaultSiteID = "REPLACE_ME_SITE"
}
```

- [ ] **Step 3: Create `StaticAuthProvider.swift`**

`Sources/ChatClientDemo/StaticAuthProvider.swift`:

```swift
import Foundation
import NATSChatClient

struct StaticAuthProvider: AuthProvider {
    let account: String
    let natsJwt: String

    func currentIdentity() async throws -> AuthIdentity {
        AuthIdentity(account: account, natsJwt: natsJwt)
    }
}
```

- [ ] **Step 4: Resolve dependencies**

Run: `swift package resolve`
Expected: Resolves `nats.swift` from main. (If this fails because of nats.swift's own platform requirements bumping the macOS minimum, raise `.macOS(.v13)` further per the resolver's error message.)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ChatClientDemo/DemoConfig.swift Sources/ChatClientDemo/StaticAuthProvider.swift
git commit -m "feat(demo): add demo target wiring, DemoConfig, and StaticAuthProvider"
```

---

## Task 12: Demo target — NatsSwiftTransport adapter

**Files:**
- Create: `Sources/ChatClientDemo/NatsSwiftTransport.swift`

- [ ] **Step 1: Create the adapter**

`Sources/ChatClientDemo/NatsSwiftTransport.swift`:

```swift
import Foundation
import NATSChatClient
import Nats   // If the product name differs, update both this import and Package.swift.

/// Adapts `nats-io/nats.swift` to the `NATSTransport` protocol.
///
/// Notes for the implementer:
/// - `nats.swift`'s exact API surface may have evolved since this file was written.
///   The body uses the names from the public README at the time of authoring:
///   `NatsClientOptions`, `connect()`, `publish(_:to:)`, `subscribe(_:)`.
///   Adjust to match the actual API after running `swift package resolve`.
/// - The natsJwt is supplied to the client builder when present.
actor NatsSwiftTransport: NATSTransport {
    private let url: String
    private let jwt: String?
    private var client: NatsClient?

    init(url: String, jwt: String?) {
        self.url = url
        self.jwt = jwt
    }

    private func connectedClient() async throws -> NatsClient {
        if let c = client { return c }
        // The exact builder/init below is the one to adjust against the resolved nats.swift API.
        var options = NatsClientOptions()
        options.url = url
        if let jwt = jwt, !jwt.isEmpty {
            options.jwt = jwt
        }
        let c = NatsClient(options: options)
        try await c.connect()
        self.client = c
        return c
    }

    // MARK: NATSTransport

    func publish(subject: String, payload: Data) async throws {
        let c = try await connectedClient()
        try await c.publish(payload, to: subject)
    }

    func subscribe(subject: String) async throws -> any NATSSubscription {
        let c = try await connectedClient()
        let underlying = try await c.subscribe(to: subject)
        let (stream, continuation) = AsyncStream<NATSMessage>.makeStream()
        let task = Task {
            for await msg in underlying.messages {
                continuation.yield(NATSMessage(subject: msg.subject, payload: msg.payload))
            }
            continuation.finish()
        }
        return NatsSwiftSubscription(stream: stream, onCancel: {
            task.cancel()
            await underlying.unsubscribe()
            continuation.finish()
        })
    }
}

private struct NatsSwiftSubscription: NATSSubscription, @unchecked Sendable {
    let stream: AsyncStream<NATSMessage>
    let onCancel: @Sendable () async -> Void
    var messages: AsyncStream<NATSMessage> { stream }
    func cancel() async { await onCancel() }
}
```

- [ ] **Step 2: Build and pin against the real API**

Run: `swift build`
Expected: May fail with "no such type `NatsClient`" or similar. **This is expected** — `nats.swift`'s API may not match exactly. Adjust:

  - The `import Nats` line (replace `Nats` with the real module name).
  - `NatsClient`, `NatsClientOptions`, `connect()`, `publish(_:to:)`, `subscribe(to:)`, `underlying.messages`, `underlying.unsubscribe()` — replace each call with the equivalent from the resolved `nats.swift` version. Check `.build/checkouts/nats.swift/` for the public types.
  - Re-run `swift build` after each adjustment until it succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ChatClientDemo/NatsSwiftTransport.swift Package.swift
git commit -m "feat(demo): add nats-io/nats.swift transport adapter"
```

---

## Task 13: Demo target — SwiftUI views and app entry point

**Files:**
- Create: `Sources/ChatClientDemo/ChatClientDemoApp.swift`
- Create: `Sources/ChatClientDemo/SendMessageView.swift`
- Create: `Sources/ChatClientDemo/ResultView.swift`

- [ ] **Step 1: Create `ResultView.swift`**

`Sources/ChatClientDemo/ResultView.swift`:

```swift
import SwiftUI
import NATSChatClient

struct ResultView: View {
    let result: Result<SentMessage, ChatClientError>?

    var body: some View {
        Group {
            switch result {
            case .none:
                Text("No send yet.").foregroundColor(.secondary)
            case .success(let msg):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sent ✓").font(.headline).foregroundColor(.green)
                    Text("id: \(msg.id)").font(.callout.monospaced())
                    Text("requestID: \(msg.requestID)").font(.callout.monospaced())
                    Text("createdAt: \(msg.createdAt)")
                    Text("userAccount: \(msg.userAccount)")
                    Text("content: \(msg.content)")
                }
                .padding()
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
            case .failure(let err):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error ✗").font(.headline).foregroundColor(.red)
                    Text(String(describing: err))
                }
                .padding()
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }
        }
    }
}
```

- [ ] **Step 2: Create `SendMessageView.swift`**

`Sources/ChatClientDemo/SendMessageView.swift`:

```swift
import SwiftUI
import NATSChatClient

@MainActor
final class SendMessageViewModel: ObservableObject {
    @Published var roomID: String = DemoConfig.defaultRoomID
    @Published var siteID: String = DemoConfig.defaultSiteID
    @Published var content: String = ""
    @Published var threadParentID: String = ""
    @Published var quotedParentID: String = ""
    @Published var isSending: Bool = false
    @Published var lastResult: Result<SentMessage, ChatClientError>?
    @Published var history: [Result<SentMessage, ChatClientError>] = []

    let client: ChatClient
    init(client: ChatClient) { self.client = client }

    func send() async {
        isSending = true
        defer { isSending = false }
        let outcome: Result<SentMessage, ChatClientError>
        do {
            let msg = try await client.sendMessage(
                roomID: roomID,
                siteID: siteID,
                content: content,
                threadParentMessageID: threadParentID.isEmpty ? nil : threadParentID,
                quotedParentMessageID: quotedParentID.isEmpty ? nil : quotedParentID
            )
            outcome = .success(msg)
        } catch let err as ChatClientError {
            outcome = .failure(err)
        } catch {
            outcome = .failure(.transport(error))
        }
        lastResult = outcome
        history.insert(outcome, at: 0)
    }
}

struct SendMessageView: View {
    @StateObject var vm: SendMessageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                LabeledField(label: "roomID",  text: $vm.roomID)
                LabeledField(label: "siteID",  text: $vm.siteID)
                LabeledField(label: "content", text: $vm.content)
                DisclosureGroup("Optional") {
                    LabeledField(label: "threadParentMessageID", text: $vm.threadParentID)
                    LabeledField(label: "quotedParentMessageID", text: $vm.quotedParentID)
                }
            }
            Button(action: { Task { await vm.send() } }) {
                if vm.isSending { ProgressView() } else { Text("Send").bold() }
            }
            .disabled(vm.isSending || vm.content.isEmpty)

            ResultView(result: vm.lastResult)

            if !vm.history.isEmpty {
                Divider()
                Text("History").font(.headline)
                ScrollView {
                    ForEach(Array(vm.history.enumerated()), id: \.offset) { _, r in
                        ResultView(result: r).padding(.bottom, 4)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 480)
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
```

- [ ] **Step 3: Create `ChatClientDemoApp.swift`**

`Sources/ChatClientDemo/ChatClientDemoApp.swift`:

```swift
import SwiftUI
import NATSChatClient

@main
struct ChatClientDemoApp: App {
    @State private var client: ChatClient?
    @State private var startError: String?

    var body: some Scene {
        WindowGroup("NATS Chat Client Demo") {
            Group {
                if let client = client {
                    SendMessageView(vm: SendMessageViewModel(client: client))
                } else if let startError = startError {
                    Text("Failed to start: \(startError)")
                        .padding()
                        .foregroundColor(.red)
                } else {
                    ProgressView("Connecting…")
                        .frame(minWidth: 420, minHeight: 200)
                }
            }
            .task {
                do {
                    let transport = NatsSwiftTransport(
                        url: DemoConfig.natsURL,
                        jwt: DemoConfig.natsJwt
                    )
                    let auth = StaticAuthProvider(
                        account: DemoConfig.account,
                        natsJwt: DemoConfig.natsJwt
                    )
                    let c = ChatClient(transport: transport, auth: auth)
                    try await c.start()
                    self.client = c
                } catch {
                    self.startError = String(describing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build the demo**

Run: `swift build --target ChatClientDemo`
Expected: Builds successfully. (If `Nats` symbols still fail, return to Task 12 step 2 and adjust further.)

- [ ] **Step 5: Run the demo (smoke check, optional — needs server)**

Run: `swift run ChatClientDemo`

Manual checks (require a live chat NATS server reachable from the dev machine):

1. UI opens with `roomID`/`siteID`/`content` fields. Enter a real room and site, type content, click Send → green "Sent ✓" box with returned `id`, `requestID`, `createdAt`.
2. Set `roomID` to a non-existent value → red error box with `.server(code: ..., message: ...)`.
3. Disable network → red error box with `.timeout(requestID: ...)` after ~10s.
4. Click Send twice rapidly → both end up in history with matching content + requestIDs.

If a server isn't available, this step is documentation-only and the manual checks are deferred.

- [ ] **Step 6: Commit**

```bash
git add Sources/ChatClientDemo/
git commit -m "feat(demo): add SwiftUI views and app entry point"
```

---

## Task 14: README and final spec self-test

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

```markdown
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
```

- [ ] **Step 2: Final full-suite test run**

Run: `swift test`
Expected: All tests pass.

Run: `swift build --target ChatClientDemo`
Expected: Demo builds.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Done

The branch should now contain:

- `Package.swift` with `NATSChatClient` library + `ChatClientDemo` executable + tests.
- ~10 library source files implementing the §4 send/response flow with full unit coverage.
- A SwiftUI demo wired to `nats-io/nats.swift` via a `NatsSwiftTransport` adapter.
- A README documenting usage, the demo, and v1 scope.

Push the branch and open (or update) the existing PR.
