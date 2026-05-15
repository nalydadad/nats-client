enum Subjects {
    static func msgSend(account: String, roomID: String, siteID: String) -> String {
        "chat.user.\(account).room.\(roomID).\(siteID).msg.send"
    }

    static func userResponseWildcard(account: String) -> String {
        "chat.user.\(account).response.>"
    }

    /// Returns the trailing requestID token from a subject of shape
    /// `chat.user.{account}.response.{requestID}`. Returns nil for any other shape.
    static func parseRequestID(fromResponseSubject subject: String) -> String? {
        let parts = subject.split(separator: ".", omittingEmptySubsequences: false)
        // Expect exactly 5 segments: chat / user / {account} / response / {requestID}
        guard parts.count == 5,
              parts[0] == "chat",
              parts[1] == "user",
              parts[3] == "response",
              !parts[2].isEmpty,
              !parts[4].isEmpty,
              !parts[2].contains("*"), !parts[2].contains(">"),
              !parts[4].contains("*"), !parts[4].contains(">")
        else { return nil }
        return String(parts[4])
    }
}
