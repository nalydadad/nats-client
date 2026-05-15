import XCTest
@testable import ChatClient

final class ChatClientTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testListRoomsDecodesSpecResponse() async throws {
        let transport = MockTransport()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = Room(
            id: "r1", name: "general", type: "channel",
            createdBy: "alice", siteId: "site-a", userCount: 3,
            lastMsgAt: now, lastMsgId: "m1",
            createdAt: now, updatedAt: now
        )
        let body = ListRoomsResponse(rooms: [expected])
        let data = try encoder.encode(body)
        transport.setRequestHandler { subject, _ in
            XCTAssertEqual(subject, "chat.user.alice.request.rooms.list")
            return data
        }

        let client = ChatClient(transport: transport, account: "alice", siteID: "site-a")
        let rooms = try await client.listRooms()
        XCTAssertEqual(rooms, [expected])
    }

    func testListRoomsThrowsOnErrorEnvelope() async throws {
        let transport = MockTransport()
        let data = try encoder.encode(ErrorEnvelope(error: "no access", code: "forbidden"))
        transport.setRequestHandler { _, _ in data }
        let client = ChatClient(transport: transport, account: "alice", siteID: "site-a")
        do {
            _ = try await client.listRooms()
            XCTFail("expected throw")
        } catch let ChatError.server(message, code) {
            XCTAssertEqual(message, "no access")
            XCTAssertEqual(code, "forbidden")
        }
    }

    func testSendMessageMatchesAsyncJobReplyByRequestID() async throws {
        let transport = MockTransport()
        let client = ChatClient(transport: transport, account: "alice", siteID: "site-a")
        try await client.connect()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        transport.setPublishHandler { subject, payload in
            XCTAssertEqual(subject, "chat.user.alice.room.r1.site-a.msg.send")
            struct Sent: Decodable { let id: String; let content: String; let requestId: String }
            let sent = try JSONDecoder().decode(Sent.self, from: payload)
            XCTAssertEqual(sent.content, "hi")
            XCTAssertEqual(sent.requestId.count, 36)

            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let reply = Message(
                id: sent.id, roomId: "r1", userId: "u1", userAccount: "alice",
                content: "hi", createdAt: now,
                threadParentMessageId: nil, quotedParentMessage: nil
            )
            var dict = try JSONSerialization.jsonObject(with: enc.encode(reply)) as! [String: Any]
            dict["requestId"] = sent.requestId
            let data = try JSONSerialization.data(withJSONObject: dict)
            transport.inject(subject: "chat.user.alice.response.\(sent.requestId)", payload: data)
        }

        let message = try await client.sendMessage(roomID: "r1", content: "hi")
        XCTAssertEqual(message.content, "hi")
        XCTAssertEqual(message.roomId, "r1")
    }

    func testSendMessageThrowsNotConnected() async throws {
        let client = ChatClient(transport: MockTransport(), account: "alice", siteID: "site-a")
        do {
            _ = try await client.sendMessage(roomID: "r1", content: "hi")
            XCTFail("expected throw")
        } catch ChatError.notConnected {
            // ok
        }
    }

    func testSendMessagePropagatesServerError() async throws {
        let transport = MockTransport()
        let client = ChatClient(transport: transport, account: "alice", siteID: "site-a")
        try await client.connect()

        transport.setPublishHandler { _, payload in
            struct Sent: Decodable { let requestId: String }
            let sent = try JSONDecoder().decode(Sent.self, from: payload)
            var dict: [String: Any] = ["error": "bad", "code": "bad_request", "requestId": sent.requestId]
            let data = try JSONSerialization.data(withJSONObject: dict)
            transport.inject(subject: "chat.user.alice.response.\(sent.requestId)", payload: data)
        }

        do {
            _ = try await client.sendMessage(roomID: "r1", content: "hi")
            XCTFail("expected throw")
        } catch let ChatError.server(message, code) {
            XCTAssertEqual(message, "bad")
            XCTAssertEqual(code, "bad_request")
        }
    }

    func testRoomEventsYieldsDecodedEvents() async throws {
        let transport = MockTransport()
        let client = ChatClient(transport: transport, account: "alice", siteID: "site-a")
        let stream = client.roomEvents(roomID: "r1")

        // Give the subscribe call a tick to register.
        try await Task.sleep(for: .milliseconds(10))

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let msg = Message(
            id: "m1", roomId: "r1", userId: "u1", userAccount: "alice",
            content: "hi", createdAt: now,
            threadParentMessageId: nil, quotedParentMessage: nil
        )
        let event = RoomEvent(
            type: "new_message", message: msg,
            messageId: nil, editedAt: nil, deletedAt: nil, content: nil
        )
        let data = try encoder.encode(event)
        transport.inject(subject: "chat.room.r1.event", payload: data)

        var iter = stream.makeAsyncIterator()
        let received = try await iter.next()
        XCTAssertEqual(received?.type, "new_message")
        XCTAssertEqual(received?.message?.id, "m1")
    }

    func testSubjectWildcardMatching() {
        XCTAssertTrue(MockTransport.matches(pattern: "chat.user.alice.response.>", subject: "chat.user.alice.response.abc"))
        XCTAssertFalse(MockTransport.matches(pattern: "chat.user.alice.response.>", subject: "chat.user.bob.response.abc"))
        XCTAssertTrue(MockTransport.matches(pattern: "chat.room.*.event", subject: "chat.room.r1.event"))
        XCTAssertFalse(MockTransport.matches(pattern: "chat.room.*.event", subject: "chat.room.r1.event.typing"))
    }
}
