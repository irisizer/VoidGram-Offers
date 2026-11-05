import UIKit

enum StickerAsset {
    case image(name: String)
    case video(resource: String, fileExtension: String, aspectRatio: CGFloat)

    var staticImage: UIImage? {
        guard case let .image(name) = self else { return nil }
        return UIImage(named: name)
    }

    /// The source aspect ratio is preserved in the chat rather than forcing
    /// every sticker into the old square message frame.
    var aspectRatio: CGFloat {
        switch self {
        case let .image(name):
            guard let image = UIImage(named: name), image.size.height > 0 else { return 1 }
            return image.size.width / image.size.height
        case let .video(_, _, aspectRatio):
            return aspectRatio
        }
    }
}
