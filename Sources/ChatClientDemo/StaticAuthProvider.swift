import Foundation
import NATSChatClient

struct StaticAuthProvider: AuthProvider {
    let account: String
    let natsJwt: String

    func currentIdentity() async throws -> AuthIdentity {
        AuthIdentity(account: account, natsJwt: natsJwt)
    }
}
