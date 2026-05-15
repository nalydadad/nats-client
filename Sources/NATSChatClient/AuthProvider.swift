public struct AuthIdentity: Sendable, Equatable {
    public let account: String
    public let natsJwt: String

    public init(account: String, natsJwt: String) {
        self.account = account
        self.natsJwt = natsJwt
    }
}

public protocol AuthProvider: Sendable {
    /// Returns the current authenticated identity. May refresh as needed.
    func currentIdentity() async throws -> AuthIdentity
}
