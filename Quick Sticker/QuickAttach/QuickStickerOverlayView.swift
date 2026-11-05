import UIKit

/// Full-screen long-press surface for the quick-sticker gesture. Cards are
/// launched from the sticker icon on independent X/Y springs so their path bends
/// naturally instead of travelling in a straight line.
final class QuickStickerOverlayView: UIView {
    var onTap: ((CGPoint) -> Void)?
    private let dimView = UIView()
    private var itemViews: [StickerPreviewView] = []
    private var itemFrames: [CGRect] = []
    private var sourceRect: CGRect = .zero
    private var highlightedIndex: Int?
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

    private let itemSpacing: CGFloat = 5
    private let stripBottomGap: CGFloat = 16
    private let hitSlop: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        dimView.frame = bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Keep the conversation readable: the fan needs just enough contrast,
        // not a modal blur that hides the chat context.
        dimView.backgroundColor = UIColor(white: 0, alpha: 0.04)
        dimView.alpha = 0
        addSubview(dimView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?(recognizer.location(in: self))
    }

    func present(stickers: [StickerAsset], from sourceRect: CGRect) {
        guard !stickers.isEmpty else { return }
        self.sourceRect = sourceRect
        impactHaptic.impactOccurred()
        selectionHaptic.prepare()

        // Keep the source aspect ratio for every item. A square preview frame
        // made rectangular stickers look as if the app had painted a backing
        // card underneath them.
        let maximumEdge: CGFloat = 80
        let unscaledSizes = stickers.map { sticker -> CGSize in
            let ratio = max(0.2, sticker.aspectRatio)
            if ratio >= 1 {
                return CGSize(width: maximumEdge, height: maximumEdge / ratio)
            } else {
                return CGSize(width: maximumEdge * ratio, height: maximumEdge)
            }
        }
        let availableWidth = bounds.width - 16 - itemSpacing * CGFloat(stickers.count - 1)
        let unscaledWidth = unscaledSizes.reduce(0) { $0 + $1.width }
        let scale = min(1, availableWidth / max(1, unscaledWidth))
        let itemSizes = unscaledSizes.map { CGSize(width: $0.width * scale, height: $0.height * scale) }
        let stripWidth = itemSizes.reduce(0) { $0 + $1.width } + itemSpacing * CGFloat(stickers.count - 1)
        let maxHeight = itemSizes.map(\.height).max() ?? maximumEdge
        let rightmostWidth = itemSizes.last?.width ?? 0
        let x = max(8, min(sourceRect.midX - stripWidth + rightmostWidth / 2, bounds.width - 8 - stripWidth))
        let y = max(safeAreaInsets.top + 8, sourceRect.minY - stripBottomGap - maxHeight)
        var nextX = x
        itemFrames = itemSizes.map { size in
            defer { nextX += size.width + itemSpacing }
            return CGRect(x: nextX, y: y + (maxHeight - size.height) / 2, width: size.width, height: size.height)
        }

        itemViews = zip(stickers, itemFrames).map { sticker, frame in
            let view = StickerPreviewView(cornerRadius: 20)
            view.configure(with: sticker)
            view.frame = frame
            view.alpha = 0
            view.setCornerRadius(20)
            view.layer.cornerCurve = .continuous
            view.layer.allowsEdgeAntialiasing = true
            addSubview(view)
            return view
        }

        UIView.animate(withDuration: 0.12) {
            self.dimView.alpha = 1
        }

        let tuning = FanTuning.shared
        let source = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        for (index, view) in itemViews.enumerated() {
            let destination = view.center
            let begin = CACurrentMediaTime() + Double(index) * Double(tuning.staggerMs) / 1000
            let yDamping = max(0.2, tuning.yDamping - CGFloat(index) * tuning.yOvershootStep)
            view.layer.add(spring("position.x", from: source.x, to: destination.x, stiffness: tuning.xStiffness, dampingRatio: tuning.xDamping, begin: begin), forKey: "flightX")
            view.layer.add(spring("position.y", from: source.y, to: destination.y, stiffness: tuning.yStiffness, dampingRatio: yDamping, begin: begin), forKey: "flightY")
            view.layer.add(spring("transform.scale", from: tuning.birthScale, to: 1, stiffness: tuning.xStiffness, dampingRatio: tuning.xDamping, begin: begin), forKey: "flightScale")
            view.setCornerRadius(20)
            UIView.animate(withDuration: 0.15, delay: max(0, begin - CACurrentMediaTime()), options: .curveEaseOut) {
                view.alpha = 1
            }
        }
    }

    func updateTracking(location: CGPoint) {
        let next = itemIndex(at: location)
        guard next != highlightedIndex else { return }
        if next != nil { selectionHaptic.selectionChanged() }
        highlightedIndex = next
        for (index, view) in itemViews.enumerated() {
            let isHighlighted = index == next
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.4, options: .allowUserInteraction) {
                view.transform = isHighlighted ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity
                view.alpha = next == nil || isHighlighted ? 1 : 0.8
            }
            if isHighlighted {
                bringSubviewToFront(view)
            }
        }
    }

    func finishTracking(location: CGPoint) -> Int? { itemIndex(at: location) }

    func dismiss(selectedIndex: Int?, targetRect: CGRect?, completion: @escaping () -> Void) {
        for view in itemViews { bakePresentationState(into: view) }
        UIView.animate(withDuration: 0.18) {
            self.dimView.alpha = 0
        }

        if let selectedIndex, let targetRect, itemViews.indices.contains(selectedIndex) {
            for (index, view) in itemViews.enumerated() where index != selectedIndex {
                UIView.animate(withDuration: 0.12, delay: 0, options: .curveEaseOut) {
                    view.alpha = 0
                    view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                }
            }
            let selected = itemViews[selectedIndex]
            bringSubviewToFront(selected)
            UIView.animate(withDuration: 0.30, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.35) {
                selected.transform = .identity
                selected.frame = targetRect
                selected.layer.shadowOpacity = 0
            } completion: { _ in
                self.removeFromSuperview()
                completion()
            }
            return
        }

        let tuning = FanTuning.shared
        let target = CGPoint(x: sourceRect.midX, y: sourceRect.midY + tuning.birthYOffset)
        for (index, view) in itemViews.enumerated() {
            let reverseOrder = Double(itemViews.count - 1 - index) * Double(tuning.staggerMs) / 1000
            let begin = CACurrentMediaTime() + reverseOrder
            let yDamping = max(0.2, tuning.yDamping - CGFloat(index) * tuning.yOvershootStep)
            let fromPosition = view.layer.position
            let fromScale = view.transform.a
            view.layer.position = target
            view.transform = CGAffineTransform(scaleX: tuning.birthScale, y: tuning.birthScale)
            view.layer.add(spring("position.x", from: fromPosition.x, to: target.x, stiffness: tuning.yStiffness, dampingRatio: yDamping, begin: begin), forKey: "foldX")
            view.layer.add(spring("position.y", from: fromPosition.y, to: target.y, stiffness: tuning.xStiffness, dampingRatio: tuning.xDamping, begin: begin), forKey: "foldY")
            view.layer.add(spring("transform.scale", from: fromScale, to: tuning.birthScale, stiffness: tuning.xStiffness, dampingRatio: tuning.xDamping, begin: begin), forKey: "foldScale")
            UIView.animate(withDuration: 0.10, delay: max(0, begin - CACurrentMediaTime()), options: .curveEaseOut) { view.alpha = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            self.removeFromSuperview()
            completion()
        }
    }

    private func itemIndex(at location: CGPoint) -> Int? {
        itemFrames.firstIndex { $0.insetBy(dx: -hitSlop, dy: -hitSlop * 2).contains(location) }
    }

    private func spring(_ keyPath: String, from: CGFloat, to: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat, begin: CFTimeInterval) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.mass = 1
        animation.stiffness = stiffness
        animation.damping = dampingRatio * 2 * sqrt(stiffness)
        animation.duration = animation.settlingDuration
        animation.beginTime = begin
        animation.fillMode = .backwards
        return animation
    }

    private func bakePresentationState(into view: UIView) {
        guard let presentation = view.layer.presentation() else { return }
        let scale = (presentation.value(forKeyPath: "transform.scale.x") as? CGFloat) ?? 1
        view.layer.removeAllAnimations()
        view.layer.position = presentation.position
        view.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}
