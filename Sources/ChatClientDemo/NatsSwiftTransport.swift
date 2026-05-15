import Foundation
import NATSChatClient
import Nats

/// Adapter from `nats-io/nats.swift` to the `NATSTransport` protocol.
///
/// Lazily connects on first use. The injected `jwt` is unused in this minimal demo;
/// real deployments should supply credentials via `credentialsFile`, `nkey`, etc.
actor NatsSwiftTransport: NATSTransport {
    private let url: URL
    private var client: NatsClient?

    init(url: URL) {
        self.url = url
    }

    private func connectedClient() async throws -> NatsClient {
        if let client = client { return client }
        let client = NatsClientOptions().url(url).build()
        try await client.connect()
        self.client = client
        return client
    }

    func publish(subject: String, payload: Data) async throws {
        let client = try await connectedClient()
        try await client.publish(payload, subject: subject)
    }

    func subscribe(subject: String) async throws -> any NATSSubscription {
        let client = try await connectedClient()
        let underlying = try await client.subscribe(subject: subject)
        let (stream, continuation) = AsyncStream<NATSMessage>.makeStream()
        let pump = Task {
            do {
                for try await msg in underlying {
                    continuation.yield(NATSMessage(subject: msg.subject, payload: msg.payload ?? Data()))
                }
            } catch {
                // Iterator errors end the stream cleanly.
            }
            continuation.finish()
        }
        return NatsSwiftSubscription(
            stream: stream,
            onCancel: {
                pump.cancel()
                try? await underlying.unsubscribe()
                continuation.finish()
            }
        )
    }
}

private struct NatsSwiftSubscription: NATSSubscription {
    let stream: AsyncStream<NATSMessage>
    let onCancel: @Sendable () async -> Void

    var messages: AsyncStream<NATSMessage> { stream }

    func cancel() async { await onCancel() }
}
