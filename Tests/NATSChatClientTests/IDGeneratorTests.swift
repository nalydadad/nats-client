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
