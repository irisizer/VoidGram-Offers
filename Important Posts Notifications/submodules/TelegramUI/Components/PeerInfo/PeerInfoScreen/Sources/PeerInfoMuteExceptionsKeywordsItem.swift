import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI

/// Демо-ролик: плейсхолдер поля скрыт, пока идёт набор слов.
private var conceptsDemoHidePlaceholder = false

// Локальные концепты: ячейка ключевых слов на экране исключений. Слова — фишки в одном поле,
// как получатели в поле «Кому»: ввод и Return (или запятая) добавляют слово, курсор остаётся
// в поле. Нажатие на фишку выделяет её, повторное нажатие или Backspace удаляют.

/// Плавный сдвиг узла на новое место пружиной (класс «вставка/сдвиг» из роликов Telegram: stiffness 325, damping 30).
private func demoSpringMove(_ node: ASDisplayNode, from oldFrame: CGRect, to newFrame: CGRect) {
    if oldFrame.origin == newFrame.origin || oldFrame.isEmpty {
        return
    }
    let animation = CASpringAnimation(keyPath: "position")
    animation.fromValue = NSValue(cgPoint: CGPoint(x: oldFrame.midX, y: oldFrame.midY))
    animation.toValue = NSValue(cgPoint: CGPoint(x: newFrame.midX, y: newFrame.midY))
    animation.mass = 1.0
    animation.stiffness = 325.0
    animation.damping = 30.0
    animation.duration = animation.settlingDuration
    node.layer.add(animation, forKey: "demoMove")
}

private let chipHeight: CGFloat = 28.0
private let chipSpacing: CGFloat = 6.0
private let chipHorizontalPadding: CGFloat = 10.0
private let minimumInputWidth: CGFloat = 90.0

final class PeerInfoMuteExceptionsKeywordsItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let keywords: [String]
    // Слова из поста, с которого открыт редактор: серые контурные фишки под полем ввода, нажатие добавляет слово.
    let suggestions: [String]
    let placeholder: String
    let isInputEnabled: Bool
    let sectionId: ItemListSectionId
    let add: (String) -> Bool
    let remove: (String) -> Void
    let addSuggestion: (String) -> Void

    init(presentationData: ItemListPresentationData, keywords: [String], suggestions: [String], placeholder: String, isInputEnabled: Bool, sectionId: ItemListSectionId, add: @escaping (String) -> Bool, remove: @escaping (String) -> Void, addSuggestion: @escaping (String) -> Void) {
        self.presentationData = presentationData
        self.suggestions = suggestions
        self.addSuggestion = addSuggestion
        self.keywords = keywords
        self.placeholder = placeholder
        self.isInputEnabled = isInputEnabled
        self.sectionId = sectionId
        self.add = add
        self.remove = remove
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = PeerInfoMuteExceptionsKeywordsItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? PeerInfoMuteExceptionsKeywordsItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

private final class KeywordChipNode: ASDisplayNode {
    let keyword: String
    private let backgroundNode = ASImageNode()
    private let selectedBackgroundNode = ASImageNode()
    private let titleNode = ImmediateTextNode()
    private let selectedTitleNode = ImmediateTextNode()
    private(set) var isSelected = false

    init(keyword: String) {
        self.keyword = keyword
        super.init()

        self.backgroundNode.displaysAsynchronously = false
        self.selectedBackgroundNode.displaysAsynchronously = false
        self.selectedBackgroundNode.alpha = 0.0
        self.selectedTitleNode.alpha = 0.0
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.selectedBackgroundNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.selectedTitleNode)
    }

    func update(theme: PresentationTheme, font: UIFont, size: CGSize) {
        self.backgroundNode.image = generateStretchableFilledCircleImage(diameter: chipHeight, color: theme.list.itemAccentColor.withAlphaComponent(0.12))
        self.selectedBackgroundNode.image = generateStretchableFilledCircleImage(diameter: chipHeight, color: theme.list.itemAccentColor)
        self.titleNode.attributedText = NSAttributedString(string: self.keyword, font: font, textColor: theme.list.itemAccentColor)
        self.selectedTitleNode.attributedText = NSAttributedString(string: self.keyword, font: font, textColor: theme.list.itemCheckColors.foregroundColor)

        let bounds = CGRect(origin: CGPoint(), size: size)
        self.backgroundNode.frame = bounds
        self.selectedBackgroundNode.frame = bounds
        for titleNode in [self.titleNode, self.selectedTitleNode] {
            let titleSize = titleNode.updateLayout(CGSize(width: size.width - chipHorizontalPadding * 2.0, height: size.height))
            titleNode.frame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: floor((size.height - titleSize.height) / 2.0)), size: titleSize)
        }
    }

    func setSelected(_ isSelected: Bool, animated: Bool) {
        guard self.isSelected != isSelected else {
            return
        }
        self.isSelected = isSelected
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        transition.updateAlpha(node: self.selectedBackgroundNode, alpha: isSelected ? 1.0 : 0.0)
        transition.updateAlpha(node: self.selectedTitleNode, alpha: isSelected ? 1.0 : 0.0)
        transition.updateAlpha(node: self.titleNode, alpha: isSelected ? 0.0 : 1.0)
    }
}

/// Подсказка слова из поста: серый текст и серая контурная обводка.
private final class OutlineChipNode: ASDisplayNode {
    let word: String
    private let borderLayer = CAShapeLayer()
    private let titleNode = ImmediateTextNode()
    
    init(word: String) {
        self.word = word
        super.init()
        self.borderLayer.fillColor = nil
        self.borderLayer.lineWidth = 1.0
        self.borderLayer.lineDashPattern = [3.5, 2.5]
        self.borderLayer.lineCap = .round
        self.layer.addSublayer(self.borderLayer)
        self.addSubnode(self.titleNode)
    }
    
    func update(theme: PresentationTheme, font: UIFont, size: CGSize) {
        self.borderLayer.strokeColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.6).cgColor
        let borderRect = CGRect(origin: CGPoint(), size: size).insetBy(dx: 0.5, dy: 0.5)
        self.borderLayer.frame = CGRect(origin: CGPoint(), size: size)
        self.borderLayer.path = UIBezierPath(roundedRect: borderRect, cornerRadius: borderRect.height / 2.0).cgPath
        self.titleNode.attributedText = NSAttributedString(string: self.word, font: font, textColor: theme.list.itemSecondaryTextColor)
        let titleSize = self.titleNode.updateLayout(CGSize(width: size.width - chipHorizontalPadding * 2.0, height: size.height))
        self.titleNode.frame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: floor((size.height - titleSize.height) / 2.0)), size: titleSize)
    }
}

final class PeerInfoMuteExceptionsKeywordsItemNode: ListViewItemNode, UITextFieldDelegate, ItemListItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private let textNode: TextFieldNode
    private var chipNodes: [KeywordChipNode] = []
    private var suggestionNodes: [OutlineChipNode] = []
    private var demoTypingCount = 0
    private var demoChipOrigin: CGPoint?

    private var item: PeerInfoMuteExceptionsKeywordsItem?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()
        self.textNode = TextFieldNode()

        super.init(layerBacked: false)

        self.addSubnode(self.textNode)
        // Демо-ролик: «печатает» слово без клавиатуры, символы по очереди вырастают из левого нижнего угла.
        NotificationCenter.default.addObserver(self, selector: #selector(self.demoTypeWord(_:)), name: Notification.Name("ConceptsDemoTypeWord"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func demoTypeWord(_ notification: Notification) {
        guard let word = notification.userInfo?["word"] as? String, let item = self.item, !self.textNode.isHidden else {
            return
        }
        let textField = self.textNode.textField
        let font = textField.font ?? UIFont.systemFont(ofSize: 17.0)
        let color = item.presentationData.theme.list.itemPrimaryTextColor
        let origin = self.textNode.frame.origin
        let height = self.textNode.frame.height
        let container = UIView(frame: CGRect(origin: origin, size: CGSize(width: self.textNode.frame.width, height: height)))
        container.isUserInteractionEnabled = false
        self.view.addSubview(container)
        textField.isHidden = true
        self.demoTypingCount += 1
        // Плейсхолдер пропадает с началом набора и возвращается только после последнего слова.
        conceptsDemoHidePlaceholder = true
        let isLast = (notification.userInfo?["last"] as? Bool) ?? false
        // Точные позиции символов по раскладке текста (с кернингом), чтобы набор не «ехал» по трекингу.
        let storage = NSTextStorage(string: word, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: 10000.0, height: 1000.0))
        textContainer.lineFragmentPadding = 0.0
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        for (index, character) in word.enumerated() {
            let label = UILabel()
            label.font = font
            label.textColor = color
            label.text = String(character)
            label.sizeToFit()
            let x = layoutManager.location(forGlyphAt: index).x
            label.layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            label.frame = CGRect(x: x, y: floor((height - label.bounds.height) / 2.0), width: label.bounds.width, height: label.bounds.height)
            container.addSubview(label)
            let delay = 0.07 * Double(index)
            label.alpha = 1.0
            label.transform = .identity
            let bounce = CASpringAnimation(keyPath: "transform.scale")
            bounce.fromValue = 0.55
            bounce.toValue = 1.0
            bounce.mass = 1.0
            bounce.stiffness = 420.0
            // Заметный лёгкий перелёт (~10 %) у каждой буквы.
            bounce.damping = 18.0
            bounce.duration = bounce.settlingDuration
            bounce.beginTime = CACurrentMediaTime() + delay
            bounce.fillMode = .backwards
            label.layer.add(bounce, forKey: "charBounce")
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0.0
            appear.toValue = 1.0
            appear.duration = 0.2
            appear.beginTime = CACurrentMediaTime() + delay
            appear.fillMode = .backwards
            label.layer.add(appear, forKey: "charFade")
        }
        let total = 0.07 * Double(word.count) + 0.3
        // Слово превращается в чипс: набранный текст уходит (скейл вниз + прозрачность), а чипс появляется из скейла с отскоком.
        DispatchQueue.main.asyncAfter(deadline: .now() + total, execute: { [weak self, weak container] in
            if let container, let node = self {
                // Чипс вырастет из места, где только что стоял набранный текст.
                let textWidth = (word as NSString).size(withAttributes: [.font: container.subviews.first.flatMap { ($0 as? UILabel)?.font } ?? UIFont.systemFont(ofSize: 17.0)]).width
                node.demoChipOrigin = CGPoint(x: container.frame.minX + textWidth / 2.0, y: container.frame.midY)
            }
            if isLast {
                conceptsDemoHidePlaceholder = false
            }
            if let item = self?.item {
                _ = item.add(word)
            }
            if let container {
                UIView.animate(withDuration: 0.12, delay: 0.0, options: [.curveEaseIn], animations: {
                    container.alpha = 0.0
                }, completion: { [weak self] _ in
                    container.removeFromSuperview()
                    if let self {
                        self.demoTypingCount -= 1
                        if self.demoTypingCount <= 0 {
                            self.textNode.textField.isHidden = false
                        }
                    }
                })
            } else if let self {
                self.demoTypingCount -= 1
                if self.demoTypingCount <= 0 {
                    self.textNode.textField.isHidden = false
                }
            }
        })
    }

    override func didLoad() {
        super.didLoad()

        self.textNode.textField.delegate = self
        self.textNode.textField.autocorrectionType = .no
        self.textNode.textField.autocapitalizationType = .none
        self.textNode.textField.returnKeyType = .done
        self.textNode.textField.addTarget(self, action: #selector(self.textFieldChanged), for: .editingChanged)
        self.textNode.textField.didDeleteBackwardWhileEmpty = { [weak self] in
            self?.deleteBackwardWhileEmpty()
        }
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }

    func asyncLayout() -> (_ item: PeerInfoMuteExceptionsKeywordsItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item

        return { [weak self] item, params, neighbors in
            let themeUpdated = currentItem?.presentationData.theme !== item.presentationData.theme
            let font = Font.regular(item.presentationData.fontSize.itemListBaseFontSize)
            let chipFont = Font.regular(floor(item.presentationData.fontSize.itemListBaseFontSize * 15.0 / 17.0))

            let leftInset: CGFloat = 16.0 + params.leftInset
            let rightInset: CGFloat = 16.0 + params.rightInset
            let verticalInset: CGFloat = 10.0
            let availableWidth = params.width - leftInset - rightInset

            // Фишки раскладываются построчно; поле ввода встаёт после последней или на новую строку.
            var chipFrames: [CGRect] = []
            var offset = CGPoint(x: leftInset, y: verticalInset)
            for keyword in item.keywords {
                let textWidth = ceil((keyword as NSString).size(withAttributes: [.font: chipFont]).width)
                let width = min(availableWidth, textWidth + chipHorizontalPadding * 2.0)
                if offset.x > leftInset && offset.x + width > params.width - rightInset {
                    offset.x = leftInset
                    offset.y += chipHeight + chipSpacing
                }
                chipFrames.append(CGRect(origin: offset, size: CGSize(width: width, height: chipHeight)))
                offset.x += width + chipSpacing
            }

            var inputFrame: CGRect?
            if item.isInputEnabled {
                if offset.x > leftInset && params.width - rightInset - offset.x < minimumInputWidth {
                    offset.x = leftInset
                    offset.y += chipHeight + chipSpacing
                }
                inputFrame = CGRect(origin: CGPoint(x: offset.x + (offset.x > leftInset ? 2.0 : 0.0), y: offset.y), size: CGSize(width: params.width - rightInset - offset.x, height: chipHeight))
            }
            // Подсказки идут ниже поля ввода, отдельными строками.
            var suggestionFrames: [CGRect] = []
            let suggestionWords = item.isInputEnabled ? item.suggestions : []
            if !suggestionWords.isEmpty {
                offset.x = leftInset
                offset.y += chipHeight + chipSpacing
                for word in suggestionWords {
                    let textWidth = ceil((word as NSString).size(withAttributes: [.font: chipFont]).width)
                    let width = min(availableWidth, textWidth + chipHorizontalPadding * 2.0)
                    if offset.x > leftInset && offset.x + width > params.width - rightInset {
                        offset.x = leftInset
                        offset.y += chipHeight + chipSpacing
                    }
                    suggestionFrames.append(CGRect(origin: offset, size: CGSize(width: width, height: chipHeight)))
                    offset.x += width + chipSpacing
                }
            }
            let contentHeight = max(44.0, offset.y + chipHeight + verticalInset)

            let contentSize = CGSize(width: params.width, height: contentHeight)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let separatorHeight = UIScreenPixel

            return (layout, { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                let theme = item.presentationData.theme
                strongSelf.item = item

                if themeUpdated {
                    strongSelf.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                    strongSelf.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
                    strongSelf.textNode.textField.textColor = theme.list.itemPrimaryTextColor
                    strongSelf.textNode.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
                    strongSelf.textNode.textField.tintColor = theme.list.itemAccentColor
                }
                strongSelf.textNode.textField.font = font
                strongSelf.textNode.textField.typingAttributes = [NSAttributedString.Key.font: font]
                strongSelf.textNode.textField.attributedPlaceholder = NSAttributedString(string: conceptsDemoHidePlaceholder ? "" : item.placeholder, font: font, textColor: theme.list.itemPlaceholderTextColor)

                // Фишки сопоставляются по слову: новые появляются с анимацией, удалённые исчезают.
                var updatedChipNodes: [KeywordChipNode] = []
                for (index, keyword) in item.keywords.enumerated() {
                    let chipNode: KeywordChipNode
                    var animateIn = false
                    if let existing = strongSelf.chipNodes.first(where: { $0.keyword == keyword }) {
                        chipNode = existing
                    } else {
                        chipNode = KeywordChipNode(keyword: keyword)
                        strongSelf.addSubnode(chipNode)
                        animateIn = currentItem != nil
                    }
                    let frame = chipFrames[index]
                    let previousFrame = chipNode.frame
                    chipNode.frame = frame
                    if !animateIn {
                        demoSpringMove(chipNode, from: previousFrame, to: frame)
                    }
                    chipNode.update(theme: theme, font: chipFont, size: frame.size)
                    if animateIn {
                        chipNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.12)
                        // Фишка выскакивает с отскоком: небольшой перелёт за 1.0 и возврат.
                        let bounce = CASpringAnimation(keyPath: "transform.scale")
                        bounce.fromValue = 0.55
                        bounce.toValue = 1.0
                        bounce.mass = 1.0
                        bounce.stiffness = 330.0
                        bounce.damping = 17.0
                        bounce.initialVelocity = 0.0
                        bounce.duration = bounce.settlingDuration
                        chipNode.layer.add(bounce, forKey: "keywordBounce")
                        if let origin = strongSelf.demoChipOrigin {
                            strongSelf.demoChipOrigin = nil
                            let travel = CASpringAnimation(keyPath: "position")
                            travel.fromValue = NSValue(cgPoint: origin)
                            travel.toValue = NSValue(cgPoint: CGPoint(x: frame.midX, y: frame.midY))
                            travel.mass = 1.0
                            travel.stiffness = 380.0
                            travel.damping = 32.0
                            travel.duration = travel.settlingDuration
                            chipNode.layer.add(travel, forKey: "keywordTravel")
                        }
                    }
                    updatedChipNodes.append(chipNode)
                }
                for chipNode in strongSelf.chipNodes where !updatedChipNodes.contains(where: { $0 === chipNode }) {
                    chipNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak chipNode] _ in
                        chipNode?.removeFromSupernode()
                    })
                    chipNode.layer.animateScale(from: 1.0, to: 0.2, duration: 0.15, removeOnCompletion: false)
                }
                strongSelf.chipNodes = updatedChipNodes
                
                var updatedSuggestionNodes: [OutlineChipNode] = []
                for (index, word) in suggestionWords.enumerated() {
                    let node: OutlineChipNode
                    if let existing = strongSelf.suggestionNodes.first(where: { $0.word == word }) {
                        node = existing
                    } else {
                        node = OutlineChipNode(word: word)
                        strongSelf.addSubnode(node)
                        if currentItem != nil {
                            node.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        }
                    }
                    let frame = suggestionFrames[index]
                    let previousFrame = node.frame
                    node.frame = frame
                    demoSpringMove(node, from: previousFrame, to: frame)
                    node.update(theme: theme, font: chipFont, size: frame.size)
                    updatedSuggestionNodes.append(node)
                }
                for node in strongSelf.suggestionNodes where !updatedSuggestionNodes.contains(where: { $0 === node }) {
                    node.removeFromSupernode()
                }
                strongSelf.suggestionNodes = updatedSuggestionNodes

                if let inputFrame {
                    strongSelf.textNode.isHidden = false
                    strongSelf.textNode.frame = inputFrame
                } else {
                    strongSelf.textNode.isHidden = true
                    if strongSelf.textNode.textField.isFirstResponder {
                        strongSelf.textNode.textField.resignFirstResponder()
                    }
                }

                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                }
                if strongSelf.topStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                }
                if strongSelf.bottomStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                }
                if strongSelf.maskNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    strongSelf.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = leftInset
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }

                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.inset(by: UIEdgeInsets(top: 0.0, left: params.leftInset, bottom: 0.0, right: params.rightInset))
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - bottomStripeInset - params.rightInset - 16.0, height: separatorHeight))
            })
        }
    }

    // MARK: - Ввод

    /// Добавляет все завершённые слова из текста; незавершённый хвост остаётся в поле.
    private func commit(_ text: String, keepTail: Bool) {
        guard let item = self.item else {
            return
        }
        var parts = text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
        let tail = keepTail ? (parts.popLast() ?? "") : ""
        var rejected = false
        for part in parts {
            let keyword = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if keyword.isEmpty {
                continue
            }
            if !item.add(keyword) {
                rejected = true
            }
        }
        self.textNode.textField.text = tail
        if rejected {
            self.textNode.layer.addShakeAnimation()
            HapticFeedback().error()
        }
    }

    @objc private func textFieldChanged() {
        self.selectChip(nil)
        let text = self.textNode.textField.text ?? ""
        if text.contains(",") || text.contains("\n") {
            self.commit(text, keepTail: true)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            textField.resignFirstResponder()
        } else {
            self.commit(text + ",", keepTail: true)
        }
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newText = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        let longestPart = newText.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.count }.max() ?? 0
        if longestPart > 40 {
            self.textNode.layer.addShakeAnimation()
            return false
        }
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.selectChip(nil)
        if let text = textField.text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            self.commit(text + ",", keepTail: true)
        }
    }

    private func deleteBackwardWhileEmpty() {
        if let selected = self.chipNodes.first(where: { $0.isSelected }) {
            self.item?.remove(selected.keyword)
        } else if let last = self.chipNodes.last {
            self.selectChip(last.keyword)
        }
    }

    private func selectChip(_ keyword: String?) {
        for chipNode in self.chipNodes {
            chipNode.setSelected(chipNode.keyword == keyword, animated: true)
        }
    }

    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state else {
            return
        }
        let point = recognizer.location(in: self.view)
        if let node = self.suggestionNodes.first(where: { $0.frame.insetBy(dx: -2.0, dy: -3.0).contains(point) }) {
            self.item?.addSuggestion(node.word)
            return
        }
        if let chipNode = self.chipNodes.first(where: { $0.frame.insetBy(dx: -2.0, dy: -3.0).contains(point) }) {
            if chipNode.isSelected {
                self.item?.remove(chipNode.keyword)
            } else {
                self.selectChip(chipNode.keyword)
                if !self.textNode.isHidden && !self.textNode.textField.isFirstResponder {
                    self.textNode.textField.becomeFirstResponder()
                }
            }
        } else {
            self.selectChip(nil)
            if !self.textNode.isHidden {
                self.textNode.textField.becomeFirstResponder()
            }
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
