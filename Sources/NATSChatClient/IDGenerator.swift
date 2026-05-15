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
