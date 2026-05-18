# User service RPCs (§3.4) — Design

**Status:** Draft
**Depends on:** Transport request/reply (Domain 1).
**Note:** Backend is a dev-only mock today; subjects and shapes are declared stable.

## 1. Scope

12 endpoints under `chat.user.{account}.request.user.{siteID}.`:

| # | Suffix | Verb |
|---|--------|------|
| 1 | `status.getByName` | get |
| 2 | `status.set` | set |
| 3 | `profile.getByName` | get |
| 4 | `subscription.getCurrent` | list |
| 5 | `subscription.getRooms` | list |
| 6 | `subscription.getChannels` | list |
| 7 | `subscription.getDM` | get one |
| 8 | `subscription.getApps` | list |
| 9 | `subscription.subscribeApp` | set |
| 10 | `subscription.unsubscribeApp` | set |
| 11 | `room.{roomID}.subscription.get` | get one |
| 12 | `apps.list` | list |

All synchronous request/reply.

## 2. Public API

```swift
extension ChatClient {
    public func getUserStatus(name: String, siteID: String)                     async throws -> UserStatus
    public func setUserStatus(text: String, isShow: Bool, siteID: String)       async throws

    public func getUserProfile(name: String, siteID: String)                    async throws -> UserProfile

    public func subscriptionsCurrent(siteID: String,
                                     favorite: Bool? = nil,
                                     membersContain: [String]? = nil,
                                     accountNames: [String]? = nil)             async throws -> SubscriptionsPage
    public func subscriptionRooms(siteID: String, ...)                          async throws -> SubscriptionsPage
    public func subscriptionChannels(siteID: String, ...)                       async throws -> SubscriptionsPage
    public func subscriptionDM(siteID: String, targetAccount: String)           async throws -> Subscription
    public func subscriptionApps(siteID: String, favorite: Bool? = nil)         async throws -> SubscriptionsPage
    public func subscribeApp(siteID: String, appID: String)                     async throws
    public func unsubscribeApp(siteID: String, appID: String)                   async throws

    public func roomSubscription(siteID: String, roomID: String)                async throws -> Subscription
    public func listApps(siteID: String)                                        async throws -> AppsPage
}
```

Each takes `siteID` explicitly so multi-site deployments can hit different
mocks. The library does not maintain a default site.

## 3. Models (sketch)

```swift
public struct UserStatus: Sendable, Decodable {
    public let name: String
    public let statusText: String
    public let statusIsShow: Bool
}

public struct UserProfile: Sendable, Decodable {
    public let name: String
    public let displayName: String
    public let email: String
}

public struct Subscription:        Sendable, Decodable, Equatable { ... }
public struct App:                 Sendable, Decodable, Equatable { ... }
public struct SubscriptionsPage:   Sendable, Decodable { public let subscriptions: [Subscription]; public let total: Int }
public struct AppsPage:            Sendable, Decodable { public let apps: [App]; public let total: Int }
```

Set-style endpoints (`status.set`, `subscribe/unsubscribeApp`) decode the
mock's `{"success": true}` reply, treat `success == false` as
`.server(code: nil, message: "operation rejected")`, and otherwise return
`Void`.

## 4. Subjects

One builder per endpoint, mirroring the table in §1.

```swift
extension Subjects {
    static func userStatusGetByName(account: String, siteID: String)            -> String
    static func userStatusSet(account: String, siteID: String)                  -> String
    static func userProfileGetByName(account: String, siteID: String)           -> String
    static func userSubscriptionGetCurrent(account: String, siteID: String)     -> String
    static func userSubscriptionGetRooms(account: String, siteID: String)       -> String
    static func userSubscriptionGetChannels(account: String, siteID: String)    -> String
    static func userSubscriptionGetDM(account: String, siteID: String)          -> String
    static func userSubscriptionGetApps(account: String, siteID: String)        -> String
    static func userSubscriptionSubscribeApp(account: String, siteID: String)   -> String
    static func userSubscriptionUnsubscribeApp(account: String, siteID: String) -> String
    static func userRoomSubscriptionGet(account: String, siteID: String, roomID: String) -> String
    static func userAppsList(account: String, siteID: String)                   -> String
}
```

## 5. Errors

Only documented mock error: `{"error": "unknown site", "code": "not_found"}`
→ `.server(code: "not_found", message: "unknown site")`.

## 6. Testing

- Subject-builder tests for all 12.
- One happy-path round-trip per endpoint (decode mock fixture).
- One `unknown site` error test against any endpoint (decoder is shared).
- The mock ignores filter fields — tests pass `favorite: true` and assert
  the field is serialised to JSON even though the response is invariant.

## 7. Out of scope

- Caching the responses (caller's job).
- Switching to a non-mock backend — API contract claims this is stable, so
  no client-side change anticipated.
