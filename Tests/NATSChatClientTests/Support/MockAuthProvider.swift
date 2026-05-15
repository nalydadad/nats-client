import Foundation
@testable import NATSChatClient

final class MockAuthProvider: AuthProvider {
    let identity: AuthIdentity
    init(account: String = "alice", natsJwt: String = "test-jwt") {
        self.identity = AuthIdentity(account: account, natsJwt: natsJwt)
    }
    func currentIdentity() async throws -> AuthIdentity { identity }
}
