import UIKit

/// Telegram-style composer kept intentionally small for the sticker prototype:
/// the attachment button remains visual-only, while the sticker accessory owns
/// the long-press quick-selection gesture.
final class ChatInputPanelView: UIView {
    let attachButton = HitSlopButton(type: .custom)
    let stickerButton = HitSlopButton(type: .custom)

    private let attachGlass = GlassSurfaceView(style: .regular, interactive: true)
    private let attachIcon = UIImageView()
    private let fieldBackground = GlassSurfaceView(style: .regular, interactive: true, cornerRadius: 20)
    private let textField = UITextField()
    private let stickerIcon = UIImageView()
    private let micButton = UIButton(type: .custom)
    private let micGlass = GlassSurfaceView(style: .regular, interactive: true)
    private let micIcon = UIImageView()
    private let sendContainer = UIView()
    private let sendPill = UIView()
    private let sendIconView = UIImageView()
    private let sendButton = UIButton(type: .custom)

    private var fieldTrailingToMic: NSLayoutConstraint!
    private var fieldTrailingToEdge: NSLayoutConstraint!
    private var textFieldTrailing: NSLayoutConstraint!
    private var hasContentState = false

    var onSend: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.hitSlop = 4
        attachGlass.translatesAutoresizingMaskIntoConstraints = false
        attachGlass.isUserInteractionEnabled = false
        attachButton.addSubview(attachGlass)
        attachIcon.image = UIImage(named: "TGIconAttachment")
        attachIcon.tintColor = Theme.panelControl
        attachIcon.translatesAutoresizingMaskIntoConstraints = false
        attachGlass.contentView.addSubview(attachIcon)
        addSubview(attachButton)

        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fieldBackground)

        textField.attributedPlaceholder = NSAttributedString(
            string: "Message", attributes: [.foregroundColor: Theme.inputPlaceholder]
        )
        textField.font = .systemFont(ofSize: 17)
        textField.textColor = Theme.inputText
        textField.returnKeyType = .send
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        fieldBackground.contentView.addSubview(textField)

        stickerButton.translatesAutoresizingMaskIntoConstraints = false
        stickerButton.hitSlop = 8
        stickerButton.isExclusiveTouch = true
        stickerButton.accessibilityLabel = "Quick stickers"
        // Keep this control above the native glass view. On iOS 26 the glass
        // effect owns its content hit-testing, so nesting a UIButton inside it
        // can make the visible icon inert.
        addSubview(stickerButton)
        stickerIcon.image = UIImage(named: "TGAccessoryIconStickers")
        stickerIcon.tintColor = Theme.inputControl
        stickerIcon.alpha = 0.5
        stickerIcon.isUserInteractionEnabled = false
        stickerIcon.translatesAutoresizingMaskIntoConstraints = false
        stickerButton.addSubview(stickerIcon)

        micButton.translatesAutoresizingMaskIntoConstraints = false
        micGlass.translatesAutoresizingMaskIntoConstraints = false
        micGlass.isUserInteractionEnabled = false
        micButton.addSubview(micGlass)
        micIcon.image = UIImage(named: "TGIconMicrophone")
        micIcon.tintColor = Theme.panelControl
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        micGlass.contentView.addSubview(micIcon)
        addSubview(micButton)

        sendContainer.translatesAutoresizingMaskIntoConstraints = false
        sendContainer.alpha = 0
        sendContainer.isUserInteractionEnabled = false
        addSubview(sendContainer)
        sendPill.backgroundColor = Theme.sendPill
        sendPill.layer.cornerRadius = 17
        sendPill.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
        sendPill.translatesAutoresizingMaskIntoConstraints = false
        sendContainer.addSubview(sendPill)
        sendIconView.image = UIImage(named: "TGSendIcon")
        sendIconView.tintColor = Theme.sendIcon
        sendIconView.translatesAutoresizingMaskIntoConstraints = false
        sendPill.addSubview(sendIconView)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        fieldTrailingToMic = fieldBackground.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -6)
        fieldTrailingToEdge = fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        textFieldTrailing = textField.trailingAnchor.constraint(equalTo: stickerButton.leadingAnchor, constant: -4)

        NSLayoutConstraint.activate([
            attachButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            attachButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 40),
            attachButton.heightAnchor.constraint(equalToConstant: 40),
            attachGlass.leadingAnchor.constraint(equalTo: attachButton.leadingAnchor),
            attachGlass.topAnchor.constraint(equalTo: attachButton.topAnchor),
            attachGlass.trailingAnchor.constraint(equalTo: attachButton.trailingAnchor),
            attachGlass.bottomAnchor.constraint(equalTo: attachButton.bottomAnchor),
            attachIcon.centerXAnchor.constraint(equalTo: attachGlass.centerXAnchor),
            attachIcon.centerYAnchor.constraint(equalTo: attachGlass.centerYAnchor),

            fieldBackground.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 6),
            fieldBackground.heightAnchor.constraint(equalToConstant: 40),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            fieldTrailingToMic,
            textField.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 12),
            textFieldTrailing,
            textField.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            textField.heightAnchor.constraint(equalToConstant: 40),

            stickerButton.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -4),
            stickerButton.centerYAnchor.constraint(equalTo: fieldBackground.centerYAnchor),
            stickerButton.widthAnchor.constraint(equalToConstant: 32),
            stickerButton.heightAnchor.constraint(equalToConstant: 32),
            stickerIcon.centerXAnchor.constraint(equalTo: stickerButton.centerXAnchor),
            stickerIcon.centerYAnchor.constraint(equalTo: stickerButton.centerYAnchor),
            stickerIcon.widthAnchor.constraint(equalToConstant: 24),
            stickerIcon.heightAnchor.constraint(equalToConstant: 24),

            micButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            micButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 40),
            micButton.heightAnchor.constraint(equalToConstant: 40),
            micGlass.leadingAnchor.constraint(equalTo: micButton.leadingAnchor),
            micGlass.topAnchor.constraint(equalTo: micButton.topAnchor),
            micGlass.trailingAnchor.constraint(equalTo: micButton.trailingAnchor),
            micGlass.bottomAnchor.constraint(equalTo: micButton.bottomAnchor),
            micIcon.centerXAnchor.constraint(equalTo: micGlass.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: micGlass.centerYAnchor),

            sendContainer.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor),
            sendContainer.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            sendContainer.widthAnchor.constraint(equalToConstant: 46),
            sendContainer.heightAnchor.constraint(equalToConstant: 40),
            sendPill.leadingAnchor.constraint(equalTo: sendContainer.leadingAnchor, constant: 3),
            sendPill.topAnchor.constraint(equalTo: sendContainer.topAnchor, constant: 3),
            sendPill.trailingAnchor.constraint(equalTo: sendContainer.trailingAnchor, constant: -3),
            sendPill.bottomAnchor.constraint(equalTo: sendContainer.bottomAnchor, constant: -3),
            sendIconView.centerXAnchor.constraint(equalTo: sendPill.centerXAnchor),
            sendIconView.centerYAnchor.constraint(equalTo: sendPill.centerYAnchor),
            sendIconView.widthAnchor.constraint(equalToConstant: 30),
            sendIconView.heightAnchor.constraint(equalToConstant: 30),
            sendButton.leadingAnchor.constraint(equalTo: sendContainer.leadingAnchor),
            sendButton.topAnchor.constraint(equalTo: sendContainer.topAnchor),
            sendButton.trailingAnchor.constraint(equalTo: sendContainer.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: sendContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func fieldFrame(in view: UIView) -> CGRect {
        fieldBackground.convert(fieldBackground.bounds, to: view)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let inSticker = stickerButton.point(inside: convert(point, to: stickerButton), with: event)
        if inSticker { return stickerButton }
        if let hit = super.hitTest(point, with: event) { return hit }
        let inAttach = attachButton.point(inside: convert(point, to: attachButton), with: event)
        return inAttach ? attachButton : nil
    }

    @objc private func textChanged() { updateSendButton() }

    @objc private func sendTapped() {
        let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        onSend?(text)
        textField.text = nil
        updateSendButton()
    }

    private func updateSendButton() {
        let hasContent = !(textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasContent != hasContentState else { return }
        hasContentState = hasContent
        fieldTrailingToMic.isActive = !hasContent
        fieldTrailingToEdge.isActive = hasContent
        sendContainer.isUserInteractionEnabled = hasContent
        sendButton.isUserInteractionEnabled = hasContent
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.sendContainer.alpha = hasContent ? 1 : 0
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3) {
            self.superview?.layoutIfNeeded()
            self.micButton.transform = hasContent ? CGAffineTransform(translationX: 56, y: 0) : .identity
            self.stickerButton.transform = hasContent ? CGAffineTransform(translationX: -46, y: 0) : .identity
            self.sendPill.transform = hasContent ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
        }
        if hasContent {
            sendIconView.transform = CGAffineTransform(translationX: -22, y: 18)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3) {
                self.sendIconView.transform = .identity
            }
        }
    }
}

final class HitSlopButton: UIButton {
    var hitSlop: CGFloat = 0
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
    }
}

extension ChatInputPanelView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}
