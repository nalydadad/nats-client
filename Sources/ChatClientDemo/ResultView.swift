import NATSChatClient
import SwiftUI

struct ResultView: View {
    let result: Result<SentMessage, ChatClientError>?

    var body: some View {
        Group {
            switch result {
            case .none:
                Text("No send yet.").foregroundColor(.secondary)
            case .success(let msg):
                successCard(msg)
            case .failure(let err):
                errorCard(err)
            }
        }
    }

    private func successCard(_ msg: SentMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sent").font(.headline).foregroundColor(.green)
            Text("id: \(msg.id)").font(.callout.monospaced())
            Text("requestID: \(msg.requestID)").font(.callout.monospaced())
            Text("createdAt: \(msg.createdAt)")
            Text("userAccount: \(msg.userAccount)")
            Text("content: \(msg.content)")
        }
        .padding()
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
    }

    private func errorCard(_ err: ChatClientError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Error").font(.headline).foregroundColor(.red)
            Text(String(describing: err))
        }
        .padding()
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}
