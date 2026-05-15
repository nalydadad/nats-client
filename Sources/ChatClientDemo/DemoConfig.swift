import Foundation

/// Hard-coded demo configuration. Replace placeholder values before running.
///
/// ⚠️ Do NOT commit real credentials. After editing, mark the file skip-worktree:
///
///     git update-index --skip-worktree Sources/ChatClientDemo/DemoConfig.swift
enum DemoConfig {
    static let natsURL  = "nats://localhost:4222"
    static let account  = "REPLACE_ME_ACCOUNT"
    static let natsJwt  = "REPLACE_ME_JWT"
    static let defaultRoomID = "REPLACE_ME_ROOM"
    static let defaultSiteID = "REPLACE_ME_SITE"
}
