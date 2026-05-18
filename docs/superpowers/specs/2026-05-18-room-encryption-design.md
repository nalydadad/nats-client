# Room encryption (§5.1) — Design

**Status:** Draft
**Depends on:** Event subscriptions (Domain 2) for `RoomKeyEvent` and channel
`RoomEvent.encryptedMessage` delivery.

## 1. Goal

Channel-room `new_message` and `message_edited` events ship as
`encryptedMessage` (a `roomcrypto.EncryptedMessage v3` blob). To surface
plaintext to consumers, the client must:

1. Persist per-room private keys keyed by `(roomId, version)`.
2. Use the `version` stamped in the ciphertext to pick the key.
3. Decrypt and replace `encryptedMessage` with a plaintext `Message` on the
   `roomEvents` stream — or alternatively expose a separate decrypted
   stream.

## 2. Architecture

```
RoomKeyEvent stream ──► KeyStore (actor)
                          ▲
                          │ lookup(roomID, version)
                          │
roomEvents stream  ──► Decryptor (Task) ──► AsyncStream<DecryptedRoomEvent>
                                          (failures stay on raw stream
                                           with `.decryptionFailed`)
```

The existing `roomEvents` stream stays as-is (raw, server-provided shape).
A new derived stream `decryptedRoomEvents` runs the events through the
decryptor.

## 3. Public API

```swift
extension ChatClient {
    public var decryptedRoomEvents: AsyncStream<DecryptedRoomEvent> { get }

    /// Optional: caller can seed the keystore from disk on launch.
    public func preloadRoomKey(roomID: String, version: Int, privateKey: Data) async
}

public enum DecryptedRoomEvent: Sendable {
    case message(RoomEvent, plaintext: Message)
    case nonEncrypted(RoomEvent)                        // DM, edit-on-DM
    case decryptionFailed(RoomEvent, reason: DecryptError)
}

public enum DecryptError: Error, Sendable {
    case missingKey(roomID: String, version: Int)
    case malformedCiphertext
    case authenticationFailed
}
```

## 4. KeyStore

```swift
actor KeyStore {
    private var keys: [String: [Int: Data]] = [:]       // roomID → version → key
    func store(roomID: String, version: Int, key: Data)
    func get(roomID: String, version: Int)              -> Data?
    func purgeOlderThan(grace: TimeInterval)            // optional GC
}
```

Old versions are retained indefinitely in v1 (history scrolling can hit
arbitrarily old keys). Optional GC is exposed but not invoked
automatically.

## 5. Ciphertext format

Per the spec: `EncryptedMessage v3` with `v`, `ciphertext` (base64),
`nonce` (base64). Per `roomcrypto`:

- Symmetric AES-256-GCM with a key derived from the P-256 private key.
- Nonce is 12 bytes (96 bits).
- Authenticated payload = the canonical JSON of the underlying `Message`.

The Swift implementation uses CryptoKit:
- Derive AES key with HKDF-SHA256 from the 32-byte P-256 scalar (salt
  empty, info `"roomcrypto/v3/key"`).
- `AES.GCM.SealedBox(nonce:ciphertext:tag:)` — note the spec's
  `ciphertext` already includes the 16-byte tag at the end.

If the exact KDF differs from the server, the implementation plan should
verify against a known-vector fixture before the rest of the work
proceeds.

## 6. Decryption flow

1. Event arrives on `roomEvents`.
2. If `encryptedMessage` is nil → emit `.nonEncrypted(event)`.
3. Else look up key by `(roomId, version)`.
4. Missing key → `.decryptionFailed(event, .missingKey(...))`. (Callers may
   subsequently buffer events and retry after the matching key arrives —
   see §7.)
5. Decrypt; decode plaintext JSON into `Message` → `.message(event, plaintext:)`.
6. Auth/decode failure → `.decryptionFailed`.

## 7. Out-of-order key vs. message

A key for a future version can arrive before the message that needs it,
or vice versa. Tracking & retry adds complexity; v1 keeps it simple:

- No buffering on the decryptor side. A late key does **not** retry past
  events — the caller can re-request via History (`getMessage`).
- The keystore stores keys as they arrive, regardless of order.

## 8. Testing

1. `RoomKeyEvent` → keystore retains key.
2. `encryptedMessage` with matching key → decrypted to `Message`.
3. `encryptedMessage` with unknown version → `.decryptionFailed(.missingKey)`.
4. Corrupted ciphertext → `.authenticationFailed`.
5. DM event with `message` set → `.nonEncrypted`.
6. Test vector: hard-coded ciphertext + key + expected plaintext from a
   server-supplied fixture (must be obtained before implementation).

## 9. Out of scope

- Sending encrypted messages (server side encrypts; client only decrypts).
- Persisting keys across app launches (caller's job — `preloadRoomKey`
  exposes the hook).
- Decrypting historical messages fetched via History service (out of
  band — caller can run them through a public `decrypt(roomID:event:)`
  helper if needed; if desired, add as a small follow-up).
