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

    func test_sendMessage_timeout_throwsTimeoutWithoutHanging() async throws {
        let transport = MockTransport()
        let auth = MockAuthProvider(account: "alice")
        let client = ChatClient(transport: transport, auth: auth, defaultTimeout: 0.05)
        try await client.start()

        let started = Date()
        do {
            _ = try await client.sendMessage(roomID: "R", siteID: "S", content: "x")
            XCTFail("Expected .timeout")
        } catch let ChatClientError.timeout(id) {
            XCTAssertFalse(id.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 1.0, "sendMessage hung past the timeout (took \(elapsed)s)")
    }

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
