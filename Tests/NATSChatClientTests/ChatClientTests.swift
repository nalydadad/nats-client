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
}
