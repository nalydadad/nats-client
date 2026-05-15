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

    func test_parseRequestID_rejectsWildcardTokens() {
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: "chat.user.alice.response.>"))
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: "chat.user.alice.response.*"))
    }

    func test_parseRequestID_rejectsTrailingDotSubject() {
        XCTAssertNil(Subjects.parseRequestID(fromResponseSubject: "chat.user.alice.response."))
    }
}
