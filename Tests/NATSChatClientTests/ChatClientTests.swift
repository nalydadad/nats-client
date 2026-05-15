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

    func test_startStop_canCycle() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider()
        let client = ChatClient(transport: transport, auth: auth)

        try await client.start()
        await client.stop()
        try await client.start()                // can restart cleanly
        await client.stop()
    }

    func test_sendMessage_publishesCorrectSubjectAndPayload() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth)
        try await client.start()

        // Run sendMessage concurrently; complete it via injected reply.
        let sendTask = Task { [client] in
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
            let all = await transport.snapshot()
            if let first = all.first { return first }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for publish")
        throw ChatClientError.timeout(requestID: "test-helper")
    }
}
