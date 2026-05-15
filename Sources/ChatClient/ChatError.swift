import Foundation

public enum ChatError: Error, Sendable, Equatable {
    case server(message: String, code: String?)
    case decoding(String)
    case notConnected
    case timeout
    case transportClosed

    static func from(_ envelope: ErrorEnvelope) -> ChatError {
        .server(message: envelope.error, code: envelope.code)
    }
}
