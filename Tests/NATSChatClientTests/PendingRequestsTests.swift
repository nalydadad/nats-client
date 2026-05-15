import XCTest
@testable import NATSChatClient

final class PendingRequestsTests: XCTestCase {

    func test_deliverBeforeWait_returnsBufferedPayload() async throws {
        let p = PendingRequests()
        await p.register("r1")

        let payload = Data("hello".utf8)
        await p.deliver("r1", payload: payload)

        let received = try await p.wait("r1")
        XCTAssertEqual(received, payload)
    }

    func test_waitThenDeliver_returnsPayload() async throws {
        let p = PendingRequests()
        await p.register("r2")

        async let received = p.wait("r2")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await p.deliver("r2", payload: Data("world".utf8))

        let value = try await received
        XCTAssertEqual(value, Data("world".utf8))
    }

    func test_fail_resumesPendingWaiter() async {
        let p = PendingRequests()
        await p.register("r3")

        async let result: Data = p.wait("r3")
        await p.fail("r3", error: ChatClientError.timeout(requestID: "r3"))

        do {
            _ = try await result
            XCTFail("Expected throw")
        } catch let err as ChatClientError {
            if case .timeout(let id) = err {
                XCTAssertEqual(id, "r3")
            } else {
                XCTFail("Wrong error case: \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_deliverUnknownID_isDroppedSilently() async throws {
        let p = PendingRequests()
        await p.deliver("unknown", payload: Data())
        // Nothing should crash; verify another flow still works.
        await p.register("r4")
        await p.deliver("r4", payload: Data("ok".utf8))
        let v = try await p.wait("r4")
        XCTAssertEqual(v, Data("ok".utf8))
    }

    func test_cancelAll_failsAllPendingWaiters() async {
        let p = PendingRequests()
        await p.register("a")
        await p.register("b")

        // Use Tasks instead of async let to avoid the "capturing async let is unsupported" error.
        let ta = Task<Data, Error> { try await p.wait("a") }
        let tb = Task<Data, Error> { try await p.wait("b") }
        try? await Task.sleep(nanoseconds: 5_000_000)

        await p.cancelAll()

        await assertThrowsCancellation { _ = try await ta.value }
        await assertThrowsCancellation { _ = try await tb.value }
    }

    func test_discard_removesEntry() async throws {
        let p = PendingRequests()
        await p.register("r5")
        await p.discard("r5")
        // After discard, a deliver should be dropped.
        await p.deliver("r5", payload: Data("late".utf8))
        // Re-register works fresh:
        await p.register("r5")
        async let v: Data = p.wait("r5")
        await p.deliver("r5", payload: Data("fresh".utf8))
        let got = try await v
        XCTAssertEqual(got, Data("fresh".utf8))
    }

    func test_discardPendingWaiter_resumesWithCancellationError() async {
        let p = PendingRequests()
        await p.register("rDiscard")

        let task = Task<Data, Error> { try await p.wait("rDiscard") }

        // Give the waiter time to suspend on the continuation.
        try? await Task.sleep(nanoseconds: 5_000_000)

        await p.discard("rDiscard")

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: helpers

    private func assertThrowsCancellation(
        _ block: () async throws -> Void,
        file: StaticString = #file, line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("Expected CancellationError", file: file, line: line)
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)", file: file, line: line)
        }
    }
}
