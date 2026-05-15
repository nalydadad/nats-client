import Foundation

public struct NATSMessage: Sendable {
    public let subject: String
    public let payload: Data
    public let headers: [String: String]

    public init(subject: String, payload: Data, headers: [String: String] = [:]) {
        self.subject = subject
        self.payload = payload
        self.headers = headers
    }
}

public protocol NATSTransport: Sendable {
    func publish(subject: String, payload: Data) async throws
    func request(subject: String, payload: Data, timeout: Duration) async throws -> Data
    func subscribe(subject: String) async throws -> AsyncThrowingStream<NATSMessage, Error>
}
