import Foundation
@testable import ChatClient

final class MockTransport: NATSTransport, @unchecked Sendable {
    typealias RequestHandler = @Sendable (String, Data) async throws -> Data
    typealias PublishHandler = @Sendable (String, Data) async throws -> Void

    private let lock = NSLock()
    private var subscriptions: [(pattern: String, continuation: AsyncThrowingStream<NATSMessage, Error>.Continuation)] = []
    private var _published: [(subject: String, payload: Data)] = []
    private var _requestHandler: RequestHandler?
    private var _publishHandler: PublishHandler?

    var published: [(subject: String, payload: Data)] {
        lock.lock(); defer { lock.unlock() }
        return _published
    }

    func setRequestHandler(_ handler: @escaping RequestHandler) {
        lock.lock(); _requestHandler = handler; lock.unlock()
    }

    func setPublishHandler(_ handler: @escaping PublishHandler) {
        lock.lock(); _publishHandler = handler; lock.unlock()
    }

    func publish(subject: String, payload: Data) async throws {
        lock.lock()
        _published.append((subject, payload))
        let handler = _publishHandler
        lock.unlock()
        if let handler { try await handler(subject, payload) }
    }

    func request(subject: String, payload: Data, timeout: Duration) async throws -> Data {
        lock.lock()
        let handler = _requestHandler
        lock.unlock()
        guard let handler else { throw MockError.noHandler }
        return try await handler(subject, payload)
    }

    func subscribe(subject: String) async throws -> AsyncThrowingStream<NATSMessage, Error> {
        let (stream, cont) = AsyncThrowingStream.makeStream(of: NATSMessage.self)
        lock.lock()
        subscriptions.append((subject, cont))
        lock.unlock()
        return stream
    }

    func inject(subject: String, payload: Data) {
        lock.lock()
        let matching = subscriptions.filter { Self.matches(pattern: $0.pattern, subject: subject) }
        lock.unlock()
        for s in matching {
            s.continuation.yield(NATSMessage(subject: subject, payload: payload))
        }
    }

    static func matches(pattern: String, subject: String) -> Bool {
        let p = pattern.split(separator: ".", omittingEmptySubsequences: false)
        let s = subject.split(separator: ".", omittingEmptySubsequences: false)
        var i = 0
        while i < p.count {
            if p[i] == ">" { return i < s.count }
            if i >= s.count { return false }
            if p[i] != "*" && p[i] != s[i] { return false }
            i += 1
        }
        return i == s.count
    }

    enum MockError: Error { case noHandler }
}
