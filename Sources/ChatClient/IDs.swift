import Foundation

enum IDs {
    static func uuidV7() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        bytes[0] = UInt8((ms >> 40) & 0xFF)
        bytes[1] = UInt8((ms >> 32) & 0xFF)
        bytes[2] = UInt8((ms >> 24) & 0xFF)
        bytes[3] = UInt8((ms >> 16) & 0xFF)
        bytes[4] = UInt8((ms >> 8) & 0xFF)
        bytes[5] = UInt8(ms & 0xFF)
        for i in 6..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return format(bytes)
    }

    static func base62(length: Int) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            out.append(alphabet.randomElement()!)
        }
        return out
    }

    private static func format(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let idx = hex.index
        return [
            String(hex[idx(hex.startIndex, offsetBy: 0)..<idx(hex.startIndex, offsetBy: 8)]),
            String(hex[idx(hex.startIndex, offsetBy: 8)..<idx(hex.startIndex, offsetBy: 12)]),
            String(hex[idx(hex.startIndex, offsetBy: 12)..<idx(hex.startIndex, offsetBy: 16)]),
            String(hex[idx(hex.startIndex, offsetBy: 16)..<idx(hex.startIndex, offsetBy: 20)]),
            String(hex[idx(hex.startIndex, offsetBy: 20)..<idx(hex.startIndex, offsetBy: 32)]),
        ].joined(separator: "-")
    }
}
