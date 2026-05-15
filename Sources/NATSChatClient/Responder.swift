import Foundation

/// Reads inbound messages from the shared response subscription and routes
/// them to `PendingRequests` keyed by the trailing `requestID` token.
struct Responder {
    let subscription: any NATSSubscription
    let pending: PendingRequests

    func run() async {
        for await msg in subscription.messages {
            let id = Subjects.parseRequestID(fromResponseSubject: msg.subject)
            await pending.deliver(id, payload: msg.payload)
        }
    }
}
