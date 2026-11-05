import UIKit

private let px = TelegramGraphics.screenPixel

/// Text message bubble rendered with Telegram's own stretchable bubble image
/// (ChatMessageBubbleImages.swift geometry: 33pt template, ellipse-punched tail,
/// hairline stroke). Layout constants from ChatMessageItemCommon.swift:
/// content insets 11/6+px/6-px, edge inset 3+6, max width = width - 36.
final class TextMessageCell: UITableViewCell {
    static let reuseIdentifier = "TextMessageCell"

    private let bubbleImageView = UIImageView()
    private let bodyGuide = UILayoutGuide()
    private let messageLabel = UILabel()
    private let particleTextView = ParticleTextRevealView()
    private let timeLabel = UILabel()
    private let checkBack = UIImageView()   // full check
    private let checkFront = UIImageView()  // partial check

    private var bodyLeading: NSLayoutConstraint!
    private var bodyTrailing: NSLayoutConstraint!
    private var bodyTop: NSLayoutConstraint!
    private var bodyBottom: NSLayoutConstraint!
    private var imgLeading: NSLayoutConstraint!
    private var imgTrailing: NSLayoutConstraint!
    private var timeTrailing: NSLayoutConstraint!
    private var bodyWidth: NSLayoutConstraint!
    private var labelBottom: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        bubbleImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleImageView)
        contentView.addLayoutGuide(bodyGuide)

        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 17)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageLabel)

        particleTextView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(particleTextView)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeLabel)

        checkBack.image = TelegramGraphics.checkImage(partial: false, color: Theme.checkmark)
        checkFront.image = TelegramGraphics.checkImage(partial: true, color: Theme.checkmark)
        for check in [checkBack, checkFront] {
            check.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(check)
        }

        bodyLeading = bodyGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 9)
        bodyTrailing = bodyGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -9)
        bodyTop = bodyGuide.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2 + px)
        bodyBottom = bodyGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(2 + px))
        imgLeading = bubbleImageView.leadingAnchor.constraint(equalTo: bodyGuide.leadingAnchor, constant: -1)
        imgTrailing = bubbleImageView.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: 7)
        timeTrailing = timeLabel.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -10)
        // Bubble width is measured, not derived from the label: see configure.
        // Yields to the max-width cap below.
        bodyWidth = bodyGuide.widthAnchor.constraint(equalToConstant: 0)
        bodyWidth.priority = .required - 1
        labelBottom = messageLabel.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: -(6 - px))

        NSLayoutConstraint.activate([
            bodyTop, bodyBottom, bodyWidth, labelBottom,
            bodyGuide.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -53),

            imgLeading, imgTrailing,
            bubbleImageView.topAnchor.constraint(equalTo: bodyGuide.topAnchor, constant: -1),
            bubbleImageView.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: 1),

            messageLabel.leadingAnchor.constraint(equalTo: bodyGuide.leadingAnchor, constant: 11),
            messageLabel.topAnchor.constraint(equalTo: bodyGuide.topAnchor, constant: 6 + px),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: bodyGuide.trailingAnchor, constant: -11),

            particleTextView.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            particleTextView.topAnchor.constraint(equalTo: messageLabel.topAnchor),
            particleTextView.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
            particleTextView.bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor),

            timeTrailing,
            timeLabel.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: -4),

            // Double check: read (partial) at fill-5, sent (full) 6pt left of it.
            checkFront.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -5),
            checkFront.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            checkBack.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -11),
            checkBack.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with message: Message, isFirstInGroup: Bool, isLastInGroup: Bool,
                   availableWidth: CGFloat, particleHidden: Bool = false,
                   onParticleRevealChanged: ((Bool) -> Void)? = nil) {
        let text: String
        let usesParticles: Bool
        switch message.content {
        case let .text(value):
            text = value
            usesParticles = false
        case let .particleText(value):
            text = value
            usesParticles = true
        case .sticker:
            return
        }
        messageLabel.text = text
        timeLabel.text = message.timeString

        let neighbors: TelegramGraphics.BubbleNeighbors
        switch (isFirstInGroup, isLastInGroup) {
        case (true, true): neighbors = .none
        case (true, false): neighbors = .top
        case (false, false): neighbors = .both
        case (false, true): neighbors = .bottom
        }

        // Unmerged sides get 2+px spacing, merged sides 0.
        bodyTop.constant = isFirstInGroup ? (2 + px) : 0
        bodyBottom.constant = isLastInGroup ? -(2 + px) : 0

        let outgoing = message.isOutgoing
        bubbleImageView.image = TelegramGraphics.messageBubbleImage(
            incoming: !outgoing,
            fillColor: outgoing ? Theme.outgoingBubble : Theme.incomingBubble,
            strokeColor: Theme.bubbleStroke,
            neighbors: neighbors
        )
        messageLabel.textColor = outgoing ? Theme.outgoingText : Theme.incomingText
        messageLabel.alpha = usesParticles ? 0 : 1
        particleTextView.configure(
            text: text,
            font: messageLabel.font,
            color: messageLabel.textColor ?? Theme.incomingText,
            hidden: usesParticles && particleHidden,
            enabled: usesParticles,
            onRevealChanged: onParticleRevealChanged
        )
        timeLabel.textColor = outgoing ? Theme.outgoingTime : Theme.incomingTime
        checkBack.isHidden = !outgoing
        checkFront.isHidden = !outgoing
        timeTrailing.constant = outgoing ? -23 : -10
        imgLeading.constant = outgoing ? -1 : -7   // tail zone on the tail side
        imgTrailing.constant = outgoing ? 7 : 1

        // Telegram sizes a text bubble from the laid-out lines, not from the
        // label's frame: the width is the widest line plus insets, and it only
        // grows to fit the time when the LAST line would collide with it
        // (ChatMessageTextBubbleContentNode). Reserving the time slot next to
        // the widest line instead leaves a dead gap under short last lines.
        let maxBubble = availableWidth - 53
        let metrics = Self.lineMetrics(text: text, font: messageLabel.font, maxWidth: maxBubble - 22)
        let timeInset: CGFloat = outgoing ? 23 : 10
        let timeWidth = ceil(timeLabel.intrinsicContentSize.width)
        let textOnlyWidth = 11 + metrics.maxLine + 11
        let timeInlineWidth = 11 + metrics.lastLine + 6 + timeWidth + timeInset
        var width = max(textOnlyWidth, timeInlineWidth)
        var timeLineDrop: CGFloat = 0
        if width > maxBubble {
            // Time no longer fits after the last line: it drops onto its own
            // line at the bottom-right, as Telegram does.
            width = maxBubble
            timeLineDrop = ceil(timeLabel.font.lineHeight)
        }
        bodyWidth.constant = width
        labelBottom.constant = -(6 - px) - timeLineDrop

        if outgoing {
            bodyLeading.isActive = false
            bodyTrailing.isActive = true
        } else {
            bodyTrailing.isActive = false
            bodyLeading.isActive = true
        }
    }

    /// Widest and last line of the wrapped text, trailing whitespace excluded —
    /// the two numbers Telegram's text node reports back to the bubble layout.
    private static func lineMetrics(text: String, font: UIFont, maxWidth: CGFloat) -> (maxLine: CGFloat, lastLine: CGFloat) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else {
            return (maxWidth, maxWidth)
        }
        var maxLine: CGFloat = 0
        var lastLine: CGFloat = 0
        for (index, line) in lines.enumerated() {
            let typographic = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let lineWidth = typographic - CTLineGetTrailingWhitespaceWidth(line)
            maxLine = max(maxLine, lineWidth)
            if index == lines.count - 1 { lastLine = lineWidth }
        }
        return (ceil(maxLine), ceil(lastLine))
    }
}

/// Photo message bubble: Telegram bubble image as backdrop, photo inset 2pt,
/// photo corner radius 15 (mainRadius - 1), 18pt time pill (radius 9) inset
/// 6/6 from the photo corner with white checks.
final class PhotoMessageCell: UITableViewCell {
    static let reuseIdentifier = "PhotoMessageCell"

    private let bubbleImageView = UIImageView()
    private let bodyGuide = UILayoutGuide()
    private let photoView = UIImageView()
    private let captionLabel = UILabel()
    private let timeBadge = UIView()
    private let timeLabel = UILabel()
    private let checkBack = UIImageView()
    private let checkFront = UIImageView()
    // With a caption, the date/status renders in the caption zone like a text
    // bubble (green), not in the media pill (ChatMessageBubbleItemNode).
    private let captionTimeLabel = UILabel()
    private let captionCheckBack = UIImageView()
    private let captionCheckFront = UIImageView()

    private var bodyLeading: NSLayoutConstraint!
    private var bodyTrailing: NSLayoutConstraint!
    private var imgLeading: NSLayoutConstraint!
    private var imgTrailing: NSLayoutConstraint!
    private var captionBottomConstraint: NSLayoutConstraint!
    private var photoBottomConstraint: NSLayoutConstraint!
    private var timeTrailing: NSLayoutConstraint!
    private var captionTimeTrailing: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        bubbleImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleImageView)
        contentView.addLayoutGuide(bodyGuide)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.layer.cornerRadius = 15.0 // mainRadius 16 - imageInset 1
        photoView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photoView)

        captionLabel.numberOfLines = 0
        captionLabel.font = .systemFont(ofSize: 17)
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(captionLabel)

        timeBadge.backgroundColor = Theme.mediaTimePillFill
        timeBadge.layer.cornerRadius = 9
        timeBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeBadge)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = Theme.mediaTimeText
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeBadge.addSubview(timeLabel)

        checkBack.image = TelegramGraphics.checkImage(partial: false, color: Theme.mediaTimeText)
        checkFront.image = TelegramGraphics.checkImage(partial: true, color: Theme.mediaTimeText)
        for check in [checkBack, checkFront] {
            check.translatesAutoresizingMaskIntoConstraints = false
            timeBadge.addSubview(check)
        }

        // Caption-mode date/status (green, like a text bubble).
        captionTimeLabel.font = .systemFont(ofSize: 11)
        captionTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(captionTimeLabel)
        captionCheckBack.image = TelegramGraphics.checkImage(partial: false, color: Theme.checkmark)
        captionCheckFront.image = TelegramGraphics.checkImage(partial: true, color: Theme.checkmark)
        for check in [captionCheckBack, captionCheckFront] {
            check.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(check)
        }

        bodyLeading = bodyGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 9)
        bodyTrailing = bodyGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -9)
        imgLeading = bubbleImageView.leadingAnchor.constraint(equalTo: bodyGuide.leadingAnchor, constant: -1)
        imgTrailing = bubbleImageView.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: 7)
        captionBottomConstraint = captionLabel.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: -(6 - px))
        photoBottomConstraint = photoView.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: -2)
        timeTrailing = timeLabel.trailingAnchor.constraint(equalTo: timeBadge.trailingAnchor, constant: -7)
        captionTimeTrailing = captionTimeLabel.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -23)

        NSLayoutConstraint.activate([
            bodyGuide.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2 + px),
            bodyGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(2 + px)),

            imgLeading, imgTrailing,
            bubbleImageView.topAnchor.constraint(equalTo: bodyGuide.topAnchor, constant: -1),
            bubbleImageView.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: 1),

            // Photo inset 2pt inside the bubble body, max media size 300x380.
            photoView.topAnchor.constraint(equalTo: bodyGuide.topAnchor, constant: 2),
            photoView.leadingAnchor.constraint(equalTo: bodyGuide.leadingAnchor, constant: 2),
            photoView.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -2),
            photoView.widthAnchor.constraint(equalToConstant: 300),
            photoView.heightAnchor.constraint(equalToConstant: 300),

            captionLabel.leadingAnchor.constraint(equalTo: bodyGuide.leadingAnchor, constant: 11),
            captionLabel.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -11),
            captionLabel.topAnchor.constraint(equalTo: photoView.bottomAnchor, constant: 6),

            timeBadge.trailingAnchor.constraint(equalTo: photoView.trailingAnchor, constant: -6),
            timeBadge.bottomAnchor.constraint(equalTo: photoView.bottomAnchor, constant: -6),
            timeBadge.heightAnchor.constraint(equalToConstant: 18),

            timeLabel.leadingAnchor.constraint(equalTo: timeBadge.leadingAnchor, constant: 7),
            timeTrailing,
            timeLabel.centerYAnchor.constraint(equalTo: timeBadge.centerYAnchor),

            captionTimeTrailing,
            captionTimeLabel.bottomAnchor.constraint(equalTo: bodyGuide.bottomAnchor, constant: -4),
            captionCheckFront.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -5),
            captionCheckFront.centerYAnchor.constraint(equalTo: captionTimeLabel.centerYAnchor),
            captionCheckBack.trailingAnchor.constraint(equalTo: bodyGuide.trailingAnchor, constant: -11),
            captionCheckBack.centerYAnchor.constraint(equalTo: captionTimeLabel.centerYAnchor),

            checkFront.trailingAnchor.constraint(equalTo: timeBadge.trailingAnchor, constant: -2),
            checkFront.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            checkBack.trailingAnchor.constraint(equalTo: timeBadge.trailingAnchor, constant: -8),
            checkBack.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with message: Message, isFirstInGroup: Bool, isLastInGroup: Bool) {
        // Retained only as an unused legacy renderer while the fork preserves
        // its original source layout; the active data source never registers it.
        guard case let .sticker(asset) = message.content, let image = asset.staticImage else { return }
        let caption: String? = nil
        photoView.image = image
        timeLabel.text = message.timeString
        captionLabel.text = caption

        let hasCaption = (caption?.isEmpty == false)
        captionLabel.isHidden = !hasCaption
        captionBottomConstraint.isActive = hasCaption
        photoBottomConstraint.isActive = !hasCaption

        let neighbors: TelegramGraphics.BubbleNeighbors
        switch (isFirstInGroup, isLastInGroup) {
        case (true, true): neighbors = .none
        case (true, false): neighbors = .top
        case (false, false): neighbors = .both
        case (false, true): neighbors = .bottom
        }

        let outgoing = message.isOutgoing
        bubbleImageView.image = TelegramGraphics.messageBubbleImage(
            incoming: !outgoing,
            fillColor: outgoing ? Theme.outgoingBubble : Theme.incomingBubble,
            strokeColor: Theme.bubbleStroke,
            neighbors: neighbors
        )
        captionLabel.textColor = outgoing ? Theme.outgoingText : Theme.incomingText
        imgLeading.constant = outgoing ? -1 : -7
        imgTrailing.constant = outgoing ? 7 : 1

        // With a caption the photo's bottom corners are SQUARE
        // (mergedWithAnotherContentRadius = 0, ChatMessageBubbleContentCalclulateImageCorners)
        // and the date/status moves into the caption zone (green, like text) —
        // the black media pill only exists for captionless photos.
        photoView.layer.maskedCorners = hasCaption
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        timeBadge.isHidden = hasCaption
        timeLabel.isHidden = hasCaption
        checkBack.isHidden = hasCaption || !outgoing
        checkFront.isHidden = hasCaption || !outgoing
        timeTrailing.constant = outgoing ? -20 : -7

        captionTimeLabel.isHidden = !hasCaption
        captionTimeLabel.text = message.timeString
        captionTimeLabel.textColor = outgoing ? Theme.outgoingTime : Theme.incomingTime
        captionCheckBack.isHidden = !hasCaption || !outgoing
        captionCheckFront.isHidden = !hasCaption || !outgoing
        captionTimeTrailing.constant = outgoing ? -23 : -10

        if outgoing {
            bodyLeading.isActive = false
            bodyTrailing.isActive = true
        } else {
            bodyTrailing.isActive = false
            bodyLeading.isActive = true
        }
    }
}

/// A sticker has no coloured chat bubble: its transparent artwork sits directly
/// on the wallpaper, with a small delivery-time pill in the lower corner.
final class StickerMessageCell: UITableViewCell {
    static let reuseIdentifier = "StickerMessageCell"

    private let stickerView = StickerPreviewView(cornerRadius: 20)
    private let timeBadge = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let timeLabel = UILabel()
    private let checkBack = UIImageView()
    private let checkFront = UIImageView()
    private var stickerWidth: NSLayoutConstraint!
    private var stickerHeight: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        stickerWidth = stickerView.widthAnchor.constraint(equalToConstant: 132)
        stickerHeight = stickerView.heightAnchor.constraint(equalToConstant: 132)

        stickerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stickerView)

        timeBadge.layer.cornerRadius = 9
        timeBadge.clipsToBounds = true
        timeBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeBadge)
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .white
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeBadge.contentView.addSubview(timeLabel)
        checkBack.image = TelegramGraphics.checkImage(partial: false, color: .white)
        checkFront.image = TelegramGraphics.checkImage(partial: true, color: .white)
        for check in [checkBack, checkFront] {
            check.translatesAutoresizingMaskIntoConstraints = false
            timeBadge.contentView.addSubview(check)
        }

        NSLayoutConstraint.activate([
            stickerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stickerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            stickerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            stickerWidth,
            stickerHeight,
            timeBadge.trailingAnchor.constraint(equalTo: stickerView.trailingAnchor, constant: -2),
            timeBadge.bottomAnchor.constraint(equalTo: stickerView.bottomAnchor, constant: -5),
            timeBadge.heightAnchor.constraint(equalToConstant: 18),
            timeLabel.leadingAnchor.constraint(equalTo: timeBadge.contentView.leadingAnchor, constant: 7),
            timeLabel.centerYAnchor.constraint(equalTo: timeBadge.contentView.centerYAnchor),
            checkFront.trailingAnchor.constraint(equalTo: timeBadge.contentView.trailingAnchor, constant: -2),
            checkFront.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            checkBack.trailingAnchor.constraint(equalTo: timeBadge.contentView.trailingAnchor, constant: -8),
            checkBack.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: checkBack.leadingAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with message: Message) {
        guard case let .sticker(asset) = message.content else { return }
        let maximumSide: CGFloat = 132
        let aspectRatio = max(0.1, asset.aspectRatio)
        if aspectRatio >= 1 {
            stickerWidth.constant = maximumSide
            stickerHeight.constant = maximumSide / aspectRatio
        } else {
            stickerWidth.constant = maximumSide * aspectRatio
            stickerHeight.constant = maximumSide
        }
        stickerView.configure(with: asset)
        timeLabel.text = message.timeString
    }

    func stickerFrame(in view: UIView) -> CGRect {
        stickerView.convert(stickerView.bounds, to: view)
    }
}
