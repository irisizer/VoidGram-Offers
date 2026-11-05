import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ItemListUI

// Локальные концепты: кнопка «Remove All Exceptions» закреплена внизу экрана исключений с отступом снизу
// и не уезжает со скроллом списка.

final class PeerInfoMuteExceptionsFooterItem: ItemListControllerFooterItem {
    let theme: PresentationTheme
    let title: String
    let action: () -> Void
    
    init(theme: PresentationTheme, title: String, action: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.action = action
    }
    
    func isEqual(to: ItemListControllerFooterItem) -> Bool {
        if let item = to as? PeerInfoMuteExceptionsFooterItem {
            return self.theme === item.theme && self.title == item.title
        } else {
            return false
        }
    }
    
    func node(current: ItemListControllerFooterItemNode?) -> ItemListControllerFooterItemNode {
        if let current = current as? PeerInfoMuteExceptionsFooterItemNode {
            current.item = self
            return current
        } else {
            return PeerInfoMuteExceptionsFooterItemNode(item: self)
        }
    }
}

final class PeerInfoMuteExceptionsFooterItemNode: ItemListControllerFooterItemNode {
    private let backgroundNode = ASDisplayNode()
    private let titleNode = ImmediateTextNode()
    private let buttonNode = HighlightableButtonNode()
    private var validLayout: ContainerViewLayout?
    
    var item: PeerInfoMuteExceptionsFooterItem {
        didSet {
            self.updateItem()
            if let layout = self.validLayout {
                let _ = self.updateLayout(layout: layout, transition: .immediate)
            }
        }
    }
    
    init(item: PeerInfoMuteExceptionsFooterItem) {
        self.item = item
        super.init()
        self.backgroundNode.cornerRadius = 26.0
        self.backgroundNode.clipsToBounds = true
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.buttonNode)
        self.buttonNode.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
        self.buttonNode.highligthedChanged = { [weak self] highlighted in
            guard let self else {
                return
            }
            self.backgroundNode.alpha = highlighted ? 0.6 : 1.0
        }
        self.updateItem()
    }
    
    @objc private func pressed() {
        self.item.action()
    }
    
    private func updateItem() {
        self.backgroundNode.backgroundColor = self.item.theme.list.itemBlocksBackgroundColor
        self.titleNode.attributedText = NSAttributedString(string: self.item.title, font: Font.regular(17.0), textColor: self.item.theme.list.itemDestructiveColor)
    }
    
    override func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = layout
        let sideInset: CGFloat = 16.0 + layout.safeInsets.left
        let buttonHeight: CGFloat = 52.0
        let topInset: CGFloat = 8.0
        let bottomInset: CGFloat = max(layout.intrinsicInsets.bottom, 12.0) + 6.0
        let width = layout.size.width - sideInset * 2.0
        let titleSize = self.titleNode.updateLayout(CGSize(width: width - 24.0, height: buttonHeight))
        let panelHeight = topInset + buttonHeight + bottomInset
        let buttonFrame = CGRect(x: sideInset, y: layout.size.height - panelHeight + topInset, width: width, height: buttonHeight)
        transition.updateFrame(node: self.backgroundNode, frame: buttonFrame)
        transition.updateFrame(node: self.buttonNode, frame: buttonFrame)
        self.titleNode.frame = CGRect(origin: CGPoint(x: buttonFrame.minX + floor((buttonFrame.width - titleSize.width) / 2.0), y: buttonFrame.minY + floor((buttonFrame.height - titleSize.height) / 2.0)), size: titleSize)
        return panelHeight
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if self.backgroundNode.frame.contains(point) {
            return true
        } else {
            return false
        }
    }
}
