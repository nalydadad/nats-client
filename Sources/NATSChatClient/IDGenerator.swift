import Foundation

enum Base62 {
    private static let alphabet: [Character] = Array(
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

/// RFC 9562 §5.7 UUID Version 7 generator with millisecond + counter monotonicity.
enum UUIDv7 {
    private static let lock = NSLock()
    private static var lastUnixMs: UInt64 = 0
    /// 12-bit monotonic counter used when the timestamp has not advanced.
    private static var lastCounter: UInt16 = 0

    /// Returns a new UUIDv7 string in canonical 8-4-4-4-12 lowercase hex.
    static func next() -> String {
        // RNG draws happen outside the locked section.
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let candidate12 = UInt16.random(in: 0...0x0FFF)
        let rand64 = UInt64.random(in: 0...UInt64.max)

        let (unixMs, rand12) = nextTimestampAndCounter(
            nowMs: nowMs,
            candidate12: candidate12
        )

        // 62 random bits for the trailing portion.
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

    private static func nextTimestampAndCounter(
        nowMs: UInt64,
        candidate12: UInt16
    ) -> (unixMs: UInt64, counter: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        var unixMs = nowMs
        var counter: UInt16
        if nowMs > lastUnixMs {
            unixMs = nowMs
            counter = candidate12
        } else {
            // Same or earlier ms — keep the larger ms and bump counter.
            unixMs = lastUnixMs
            if lastCounter == 0x0FFF {
                // Counter would overflow; nudge the ms forward.
                // Restart counter at a random value to spread load across the new ms bucket.
                unixMs &+= 1
                counter = candidate12
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
