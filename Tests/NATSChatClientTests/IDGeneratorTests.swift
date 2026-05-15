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
}
