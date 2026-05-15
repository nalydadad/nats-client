import NATSChatClient
import SwiftUI

@MainActor
final class SendMessageViewModel: ObservableObject {
    @Published var roomID: String = DemoConfig.defaultRoomID
    @Published var siteID: String = DemoConfig.defaultSiteID
    @Published var content: String = ""
    @Published var threadParentID: String = ""
    @Published var quotedParentID: String = ""
    @Published var isSending: Bool = false
    @Published var lastResult: Result<SentMessage, ChatClientError>?
    @Published var history: [Result<SentMessage, ChatClientError>] = []

    let client: ChatClient

    init(client: ChatClient) {
        self.client = client
    }

    func send() async {
        isSending = true
        defer { isSending = false }
        let outcome: Result<SentMessage, ChatClientError>
        do {
            let msg = try await client.sendMessage(
                roomID: roomID,
                siteID: siteID,
                content: content,
                threadParentMessageID: threadParentID.isEmpty ? nil : threadParentID,
                quotedParentMessageID: quotedParentID.isEmpty ? nil : quotedParentID
            )
            outcome = .success(msg)
        } catch let err as ChatClientError {
            outcome = .failure(err)
        } catch {
            outcome = .failure(.transport(error))
        }
        lastResult = outcome
        history.insert(outcome, at: 0)
    }
}

struct SendMessageView: View {
    @StateObject var viewModel: SendMessageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: "roomID", text: $viewModel.roomID)
            LabeledField(label: "siteID", text: $viewModel.siteID)
            LabeledField(label: "content", text: $viewModel.content)
            DisclosureGroup("Optional") {
                LabeledField(label: "threadParentMessageID", text: $viewModel.threadParentID)
                LabeledField(label: "quotedParentMessageID", text: $viewModel.quotedParentID)
            }

            Button(action: { Task { await viewModel.send() } }) {
                if viewModel.isSending {
                    ProgressView()
                } else {
                    Text("Send").bold()
                }
            }
            .disabled(viewModel.isSending || viewModel.content.isEmpty)

            ResultView(result: viewModel.lastResult)

            if !viewModel.history.isEmpty {
                Divider()
                Text("History").font(.headline)
                ScrollView {
                    ForEach(Array(viewModel.history.enumerated()), id: \.offset) { _, result in
                        ResultView(result: result).padding(.bottom, 4)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 480)
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
