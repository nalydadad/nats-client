import Foundation
import NATSChatClient
import SwiftUI

@main
struct ChatClientDemoApp: App {
    @State private var client: ChatClient?
    @State private var startError: String?

    var body: some Scene {
        WindowGroup("NATS Chat Client Demo") {
            Group {
                if let client = client {
                    SendMessageView(viewModel: SendMessageViewModel(client: client))
                } else if let startError = startError {
                    Text("Failed to start: \(startError)")
                        .padding()
                        .foregroundColor(.red)
                } else {
                    ProgressView("Connecting…")
                        .frame(minWidth: 420, minHeight: 200)
                }
            }
            .task {
                do {
                    guard let url = URL(string: DemoConfig.natsURL) else {
                        startError = "Invalid NATS URL in DemoConfig"
                        return
                    }
                    let transport = NatsSwiftTransport(url: url)
                    let auth = StaticAuthProvider(
                        account: DemoConfig.account,
                        natsJwt: DemoConfig.natsJwt
                    )
                    let chat = ChatClient(transport: transport, auth: auth)
                    try await chat.start()
                    self.client = chat
                } catch {
                    self.startError = String(describing: error)
                }
            }
        }
    }
}
