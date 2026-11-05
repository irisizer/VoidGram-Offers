import UIKit

struct Message {
    enum Content {
        case text(String)
        case particleText(String)
        case sticker(StickerAsset)
    }

    let content: Content
    let isOutgoing: Bool
    let date: Date

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var timeString: String {
        Message.timeFormatter.string(from: date)
    }
}
