public enum ChatClientError: Error, Sendable {
    case notStarted
    case timeout(requestID: String)
    case server(code: String?, message: String)
    case transport(any Error)
    case invalidPayload(String)
}

extension ChatClientError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notStarted:
            return "ChatClient has not been started. Call start() first."
        case .timeout(let id):
            return "Timed out waiting for response to request \(id)."
        case .server(let code, let message):
            return "Server error\(code.map { " [\($0)]" } ?? ""): \(message)"
        case .transport(let err):
            return "Transport error: \(err)"
        case .invalidPayload(let detail):
            return "Invalid payload: \(detail)"
        }
    }
}
