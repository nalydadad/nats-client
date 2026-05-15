import Foundation

enum Subjects {
    static func roomsList(account: String) -> String {
        "chat.user.\(account).request.rooms.list"
    }

    static func messageSend(account: String, roomID: String, siteID: String) -> String {
        "chat.user.\(account).room.\(roomID).\(siteID).msg.send"
    }

    static func userResponses(account: String) -> String {
        "chat.user.\(account).response.>"
    }

    static func roomAll(roomID: String) -> String {
        "chat.room.\(roomID).>"
    }
}
