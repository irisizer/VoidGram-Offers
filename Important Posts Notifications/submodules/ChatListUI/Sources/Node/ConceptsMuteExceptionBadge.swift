import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AppBundle
import TelegramPresentationData

// Локальные концепты: посты из исключений канала без звука в списке чатов. Счётчик
// непрочитанных — активный, как у чата со звуком, рядом — отдельная иконка колокольчика
// в цвет бейджей, как у упоминаний и реакций (Chat List/MentionBadgeIcon и т. п.).

private let conceptsMuteExceptionImages = Atomic<[String: UIImage]>(value: [:])

func conceptsMuteExceptionBadgeIcon(theme: PresentationTheme, diameter: CGFloat) -> UIImage? {
    let color = theme.chatList.unreadBadgeActiveBackgroundColor
    let key = "bell-\(diameter)-\(color.description)"
    if let image = conceptsMuteExceptionImages.with({ $0[key] }) {
        return image
    }
    // Картинка бейджа прозрачная и нужна только для размера: сам колокольчик рисует векторный слой CAShapeLayer (conceptsBellPath),
    // чтобы он оставался чётким во время скейла и качания.
    let size = CGSize(width: diameter, height: diameter)
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in }
    let _ = conceptsMuteExceptionImages.modify { images in
        var images = images
        images[key] = image
        return images
    }
    return image
}

func conceptsMuteExceptionApplyCounts(entries: [ChatListNodeEntry], unseen: [EnginePeer.Id: [EngineMessage.Index]]) -> [ChatListNodeEntry] {
    if unseen.isEmpty {
        return entries
    }
    return entries.map { entry in
        guard case var .PeerEntry(peerEntry) = entry, let indices = unseen[peerEntry.peer.peerId] else {
            return entry
        }
        peerEntry.conceptsMuteExceptionCount = conceptsMuteExceptionUnreadIndices(indices, readCounters: peerEntry.readState).count
        return .PeerEntry(peerEntry)
    }
}


/// Контур колокольчика в квадрате diameter × diameter (линия lineWidth(diameter) со скруглёнными концами).
func conceptsBellPath(diameter: CGFloat) -> CGPath {
    let factor = diameter * 0.9 / 16.0
    var transform = CGAffineTransform(translationX: (diameter - 16.0 * factor) / 2.0, y: (diameter - 14.6 * factor) / 2.0).scaledBy(x: factor, y: factor)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 1.3, y: 11.2))
    path.addCurve(to: CGPoint(x: 4.1, y: 5.2), control1: CGPoint(x: 3.1, y: 9.6), control2: CGPoint(x: 3.7, y: 7.4))
    path.addCurve(to: CGPoint(x: 11.9, y: 5.2), control1: CGPoint(x: 4.5, y: 1.4), control2: CGPoint(x: 11.5, y: 1.4))
    path.addCurve(to: CGPoint(x: 14.7, y: 11.2), control1: CGPoint(x: 12.3, y: 7.4), control2: CGPoint(x: 12.9, y: 9.6))
    path.closeSubpath()
    path.move(to: CGPoint(x: 8.0, y: 1.0))
    path.addLine(to: CGPoint(x: 8.0, y: 2.0))
    path.move(to: CGPoint(x: 6.0, y: 12.7))
    path.addArc(center: CGPoint(x: 8.0, y: 12.7), radius: 2.0, startAngle: CGFloat.pi, endAngle: 0.0, clockwise: true)
    return path.copy(using: &transform) ?? path
}

func conceptsBellLineWidth(diameter: CGFloat) -> CGFloat {
    return 1.55 * diameter * 0.9 / 16.0
}
