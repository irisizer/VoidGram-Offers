import UIKit

/// Telegram chat screen reproduced from Telegram-iOS (HEAD 6ad963e):
/// software-gradient wallpaper with the official doodle pattern, glass
/// navigation capsules (NavigationBarImpl metrics), glass composer, and the
/// demo's quick-sticker long-press gesture on the sticker accessory.
final class ChatViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputPanel = ChatInputPanelView()
    private let headerContainer = UIView()
    private let gradientView = UIImageView()
    private let patternView = UIImageView()
    private let topEdgeEffectView = UIView()
    private let topEdgeGradientClone = UIImageView()
    private let topEdgePatternClone = UIImageView()
    private let topEdgeMask = CAGradientLayer()

    private var messages: [Message] = []
    private var overlay: QuickStickerOverlayView?
    private var sentStickerCount = 0
    private var isParticleIntroRevealed = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupWallpaper()
        seedMessages()
        setupTable()
        setupInputPanel()
        setupTopEdgeEffect()
        setupHeader()
        setupQuickStickerGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTopEdgeEffect()
        // Keep content clear of the floating composer (grows when the chip is shown).
        let bottomInset = inputPanel.bounds.height + 16
        if abs(tableView.contentInset.bottom - bottomInset) > 0.5 {
            tableView.contentInset.bottom = bottomInset
            tableView.verticalScrollIndicatorInsets.bottom = inputPanel.bounds.height + 8
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Wallpaper
    // Gradient transcribed from GradientBackground/SoftwareGradientBackground.swift;
    // pattern = the official bundled fqv01...tgv doodle, soft-light at 50%.

    private func setupWallpaper() {
        gradientView.contentMode = .scaleToFill
        gradientView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gradientView.frame = view.bounds
        let aspect = view.bounds.width / max(view.bounds.height, 1)
        gradientView.image = Self.makeGradientImage(size: CGSize(width: floor(80 * aspect), height: 80))
        view.insertSubview(gradientView, at: 0)

        patternView.contentMode = .scaleAspectFill
        patternView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        patternView.frame = view.bounds
        patternView.clipsToBounds = true
        patternView.image = UIImage(named: "WallpaperPattern")
        patternView.tintColor = .black                                   // light wallpaper -> black pattern
        patternView.layer.compositingFilter = "softLightBlendMode"       // WallpaperBackgroundNode.swift:1587
        patternView.alpha = 0.5                                          // intensity 50/100
        view.insertSubview(patternView, aboveSubview: gradientView)
    }

    /// Top wallpaper edge effect over the messages, under the nav capsules —
    /// Telegram's WallpaperEdgeEffectNode (ChatControllerNode.swift:2622-2652):
    /// a wallpaper clone masked by an 80pt bottom-fade gradient at alpha 0.75,
    /// height = navBar + 34. (Their extra VariableBlurView maxBlurRadius 1.0
    /// uses private CAFilter — omitted; the wallpaper fade is the dominant part.)
    private func setupTopEdgeEffect() {
        topEdgeEffectView.isUserInteractionEnabled = false
        topEdgeEffectView.clipsToBounds = true
        topEdgeEffectView.alpha = 0.75 // edgeEffectAlpha for gradient wallpaper (:2412)

        topEdgeGradientClone.contentMode = .scaleToFill
        topEdgeGradientClone.image = gradientView.image
        topEdgeEffectView.addSubview(topEdgeGradientClone)

        topEdgePatternClone.contentMode = .scaleAspectFill
        topEdgePatternClone.image = patternView.image
        topEdgePatternClone.tintColor = .black
        topEdgePatternClone.layer.compositingFilter = "softLightBlendMode"
        topEdgePatternClone.alpha = 0.5
        topEdgeEffectView.addSubview(topEdgePatternClone)

        topEdgeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        topEdgeEffectView.layer.mask = topEdgeMask

        view.insertSubview(topEdgeEffectView, aboveSubview: tableView)
    }

    private func layoutTopEdgeEffect() {
        let height = view.safeAreaInsets.top + 60.0 + 34.0
        topEdgeEffectView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)
        topEdgeGradientClone.frame = view.bounds
        topEdgePatternClone.frame = view.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topEdgeMask.frame = topEdgeEffectView.bounds
        // 80pt fade ramp at the bottom edge (WallpaperEdgeEffectEdge size 80).
        let rampStart = max(0.0, (height - 80.0) / height)
        topEdgeMask.locations = [0.0, NSNumber(value: rampStart), 1.0]
        CATransaction.commit()
    }

    /// Per-pixel kernel from SoftwareGradientBackground.swift:140-175:
    /// weight = max(0, 0.92 - distance)^3 per color, normalized sum.
    private static func makeGradientImage(size: CGSize) -> UIImage {
        // basePositions at phase 0 (:235-244), y flipped (:105-108).
        let positions: [CGPoint] = [
            CGPoint(x: 0.80, y: 1.0 - 0.10),
            CGPoint(x: 0.35, y: 1.0 - 0.25),
            CGPoint(x: 0.20, y: 1.0 - 0.90),
            CGPoint(x: 0.65, y: 1.0 - 0.75),
        ]
        var components: [(CGFloat, CGFloat, CGFloat)] = []
        for color in Theme.wallpaperColors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            components.append((r, g, b))
        }

        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let directPixelY = CGFloat(y) / CGFloat(height)
            for x in 0..<width {
                let directPixelX = CGFloat(x) / CGFloat(width)
                // Swirl distortion around the center (SoftwareGradientBackground.swift):
                // theta grows with distance from center, rotating the sample point.
                let centerDistanceX = directPixelX - 0.5
                let centerDistanceY = directPixelY - 0.5
                let centerDistance = sqrt(centerDistanceX * centerDistanceX + centerDistanceY * centerDistanceY)
                let swirlFactor = 0.35 * centerDistance
                let theta = swirlFactor * swirlFactor * 0.8 * 8.0
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                let pixelX = max(0.0, min(1.0, 0.5 + centerDistanceX * cosTheta - centerDistanceY * sinTheta))
                let pixelY = max(0.0, min(1.0, 0.5 + centerDistanceX * sinTheta + centerDistanceY * cosTheta))
                var distanceSum: CGFloat = 0.0
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                for i in 0..<positions.count {
                    let dx = pixelX - positions[i].x
                    let dy = pixelY - positions[i].y
                    var distance = max(0.0, 0.92 - sqrt(dx * dx + dy * dy))
                    distance = distance * distance * distance
                    distanceSum += distance
                    r += distance * components[i].0
                    g += distance * components[i].1
                    b += distance * components[i].2
                }
                if distanceSum < 0.00001 { distanceSum = 0.00001 }
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(max(0, min(255, r / distanceSum * 255.0)))
                pixels[offset + 1] = UInt8(max(0, min(255, g / distanceSum * 255.0)))
                pixels[offset + 2] = UInt8(max(0, min(255, b / distanceSum * 255.0)))
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let cgImage = CGImage(width: width, height: height,
                              bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: true,
                              intent: .defaultIntent)!
        return UIImage(cgImage: cgImage)
    }

    private func seedMessages() {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        messages = [
            Message(content: .particleText("i got something for you"), isOutgoing: false, date: at(19, 40)),
            Message(content: .text("will you be home by eight?"), isOutgoing: false, date: at(19, 41)),
            Message(content: .text("yeah, around then."), isOutgoing: true, date: at(19, 42)),
            Message(content: .text("okay, i'll order food in the meantime."), isOutgoing: false, date: at(19, 43)),
            Message(content: .text("just nothing spicy, please."), isOutgoing: true, date: at(19, 44)),
            Message(content: .text("okay, sounds good."), isOutgoing: false, date: at(19, 45)),
        ]
    }

    // MARK: - Header
    // NavigationBarImpl glass metrics: 44pt capsules, top = safeTop + 10,
    // back at x=16 with the code-drawn chevron + black unread badge,
    // title capsule = content + 12pt sides, avatar capsule 44 with 38pt avatar.

    private func setupHeader() {
        headerContainer.backgroundColor = .clear
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)

        // Back capsule: chevron 44x44 + unread badge.
        let backPill = GlassSurfaceView(style: .regular, interactive: true)
        backPill.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(backPill)

        let backIcon = UIImageView(image: TelegramGraphics.glassBackArrowImage)
        backIcon.tintColor = Theme.panelControl
        backIcon.translatesAutoresizingMaskIntoConstraints = false
        backPill.contentView.addSubview(backIcon)

        let badge = UILabel()
        badge.text = "3"
        badge.font = .systemFont(ofSize: 13)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = Theme.panelControl
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        backPill.contentView.addSubview(badge)

        // Title capsule: name + online status, content + 12pt padding.
        let titlePill = GlassSurfaceView(style: .regular)
        titlePill.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(titlePill)

        let titleLabel = UILabel()
        titleLabel.text = "Kate ❤️"
        titleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Theme.navPrimaryText
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlePill.contentView.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = "online"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Theme.navAccentText
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlePill.contentView.addSubview(subtitleLabel)

        // Avatar capsule: 44pt glass, avatar inset 3 -> 38pt circle.
        let avatarPill = GlassSurfaceView(style: .regular, interactive: true)
        avatarPill.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(avatarPill)

        // AvatarNode placeholder: vertical two-stop gradient (red pair) with a
        // white SF Rounded bold letter (AvatarNode.swift:318-326, :1005-1011, 30-32).
        let avatar = UIView()
        avatar.layer.cornerRadius = 19
        avatar.clipsToBounds = true
        avatar.translatesAutoresizingMaskIntoConstraints = false
        let avatarGradient = CAGradientLayer()
        avatarGradient.colors = [
            UIColor(red: 1.0, green: 0.318, blue: 0.416, alpha: 1.0).cgColor, // #FF516A
            UIColor(red: 1.0, green: 0.533, blue: 0.369, alpha: 1.0).cgColor, // #FF885E
        ]
        avatarGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        avatarGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        avatarGradient.frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        avatar.layer.addSublayer(avatarGradient)

        let avatarLetter = UILabel()
        avatarLetter.text = "K"
        avatarLetter.textColor = .white
        let roundedDescriptor = UIFont.systemFont(ofSize: 16, weight: .bold).fontDescriptor.withDesign(.rounded)
        avatarLetter.font = roundedDescriptor.map { UIFont(descriptor: $0, size: 16) } ?? .systemFont(ofSize: 16, weight: .bold)
        avatarLetter.textAlignment = .center
        avatarLetter.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(avatarLetter)

        // Real peer photo on top of the placeholder (AvatarNode keeps the
        // gradient underneath and fades the image in over it).
        let avatarPhoto = UIImageView(image: UIImage(named: "KateAvatar"))
        avatarPhoto.contentMode = .scaleAspectFill
        avatarPhoto.clipsToBounds = true
        avatarPhoto.translatesAutoresizingMaskIntoConstraints = false
        avatarPhoto.isHidden = (avatarPhoto.image == nil)
        avatar.addSubview(avatarPhoto)

        avatarPill.contentView.addSubview(avatar)

        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),

            backPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            backPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            backPill.heightAnchor.constraint(equalToConstant: 44),
            backPill.widthAnchor.constraint(equalToConstant: 59), // 44 + badgeWidth(18) - 3

            backIcon.leadingAnchor.constraint(equalTo: backPill.leadingAnchor),
            backIcon.topAnchor.constraint(equalTo: backPill.topAnchor),
            backIcon.widthAnchor.constraint(equalToConstant: 44),
            backIcon.heightAnchor.constraint(equalToConstant: 44),

            badge.leadingAnchor.constraint(equalTo: backPill.leadingAnchor, constant: 30), // leftContentWidth - 14
            badge.centerYAnchor.constraint(equalTo: backPill.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 18),
            badge.heightAnchor.constraint(equalToConstant: 18),

            // Title pill sits 2pt higher than the side capsules (ChatTitleView y=6 in a
            // 60pt band whose origin is statusBar+2 -> statusBar+8).
            titlePill.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor),
            titlePill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titlePill.heightAnchor.constraint(equalToConstant: 44),

            // Block centered per ChatTitleView: title top = pill top + 5.
            titleLabel.topAnchor.constraint(equalTo: titlePill.topAnchor, constant: 5),
            titleLabel.centerXAnchor.constraint(equalTo: titlePill.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlePill.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlePill.trailingAnchor, constant: -12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            subtitleLabel.centerXAnchor.constraint(equalTo: titlePill.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlePill.leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlePill.trailingAnchor, constant: -12),
            // Telegram's formula is max(title, subtitle) + 24 (ChatTitleView.swift:
            // 1094-1099); per the user's request the pill is 10% wider than that.
            titlePill.widthAnchor.constraint(greaterThanOrEqualTo: titleLabel.widthAnchor, multiplier: 1.1, constant: 26.4),
            titlePill.widthAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.widthAnchor, multiplier: 1.1, constant: 26.4),
            {
                let minimizer = titlePill.widthAnchor.constraint(equalToConstant: 0)
                minimizer.priority = .defaultLow
                return minimizer
            }(),

            avatarPill.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            avatarPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            avatarPill.widthAnchor.constraint(equalToConstant: 44),
            avatarPill.heightAnchor.constraint(equalToConstant: 44),

            avatar.leadingAnchor.constraint(equalTo: avatarPill.leadingAnchor, constant: 3),
            avatar.topAnchor.constraint(equalTo: avatarPill.topAnchor, constant: 3),
            avatar.trailingAnchor.constraint(equalTo: avatarPill.trailingAnchor, constant: -3),
            avatar.bottomAnchor.constraint(equalTo: avatarPill.bottomAnchor, constant: -3),

            avatarLetter.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            avatarLetter.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),

            avatarPhoto.leadingAnchor.constraint(equalTo: avatar.leadingAnchor),
            avatarPhoto.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
            avatarPhoto.topAnchor.constraint(equalTo: avatar.topAnchor),
            avatarPhoto.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
        ])
    }

    private func setupTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.contentInset = UIEdgeInsets(top: 60, left: 0, bottom: 65, right: 0)
        tableView.verticalScrollIndicatorInsets.top = 60
        tableView.register(TextMessageCell.self, forCellReuseIdentifier: TextMessageCell.reuseIdentifier)
        tableView.register(StickerMessageCell.self, forCellReuseIdentifier: StickerMessageCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func setupInputPanel() {
        inputPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputPanel)

        inputPanel.onSend = { [weak self] text in
            self?.sendTextMessage(text)
        }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            inputPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // A plain UIView has no intrinsic height. Without this, its
            // subviews can still be visible outside a zero-height container,
            // but the container never receives touches.
            inputPanel.heightAnchor.constraint(equalToConstant: 40),
            inputPanel.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8), // inputPanelsInset
        ])
    }

    // MARK: - Quick sticker gesture

    private func setupQuickStickerGesture() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleStickerLongPress(_:)))
        longPress.minimumPressDuration = 0.15
        longPress.allowableMovement = 24
        inputPanel.stickerButton.addGestureRecognizer(longPress)
#if targetEnvironment(simulator)
        // A normal mouse click is more reliable than click-and-drag in the
        // Simulator. The device path still uses the long press above.
        inputPanel.stickerButton.addTarget(self, action: #selector(openSimulatorStickerFan), for: .touchUpInside)
#endif
    }

#if targetEnvironment(simulator)
    @objc private func openSimulatorStickerFan() {
        presentQuickStickers()
    }
#endif

    @objc private func handleStickerLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            presentQuickStickers()
        case .changed:
            overlay?.updateTracking(location: gesture.location(in: view))
        case .ended:
            finishQuickStickers(location: gesture.location(in: view))
        case .cancelled, .failed:
            cancelQuickStickers()
        default:
            break
        }
    }

    private func presentQuickStickers() {
        guard overlay == nil else { return }
        view.endEditing(false)
        let stickers = StickerProvider.recentStickers
        guard !stickers.isEmpty else { return }
        let overlay = QuickStickerOverlayView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
        self.overlay = overlay
        overlay.onTap = { [weak self] location in
            self?.finishQuickStickers(location: location)
        }
        let sourceRect = inputPanel.stickerButton.convert(inputPanel.stickerButton.bounds, to: view)
        overlay.present(stickers: stickers, from: sourceRect)
    }

    private func finishQuickStickers(location: CGPoint) {
        guard let overlay else { return }
        guard let selectedIndex = overlay.finishTracking(location: location),
              StickerProvider.recentStickers.indices.contains(selectedIndex) else {
            cancelQuickStickers()
            return
        }
        let sticker = StickerProvider.recentStickers[selectedIndex]
        let indexPath = appendSticker(sticker)
        guard let cell = tableView.cellForRow(at: indexPath) as? StickerMessageCell else {
            cancelQuickStickers()
            return
        }
        cell.alpha = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        overlay.dismiss(selectedIndex: selectedIndex, targetRect: cell.stickerFrame(in: view)) { [weak self, weak cell] in
            cell?.alpha = 1
            self?.overlay = nil
        }
    }

    private func cancelQuickStickers() {
        guard let overlay else { return }
        overlay.dismiss(selectedIndex: nil, targetRect: nil) { [weak self] in
            self?.overlay = nil
        }
    }

    // MARK: - Sending

    @discardableResult
    private func appendSticker(_ sticker: StickerAsset) -> IndexPath {
        messages.append(Message(content: .sticker(sticker), isOutgoing: true, date: Date()))
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        // Reloading the whole table tears down every visible AVPlayerLayer for
        // one frame. Insert only the new row so the existing chat remains
        // visually stable while the sticker flies into place.
        tableView.insertRows(at: [indexPath], with: .none)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        tableView.layoutIfNeeded()
        scheduleKateStickerReaction()
        return indexPath
    }

    private func scheduleKateStickerReaction() {
        sentStickerCount += 1
        let reaction: String
        switch sentStickerCount {
        case 1: reaction = "wtf"
        case 2: reaction = "got it"
        default: return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.messages.append(Message(content: .text(reaction), isOutgoing: false, date: Date()))
            let indexPath = IndexPath(row: self.messages.count - 1, section: 0)
            self.tableView.insertRows(at: [indexPath], with: .none)
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
            self.tableView.layoutIfNeeded()
            guard let cell = self.tableView.cellForRow(at: indexPath) else { return }
            cell.alpha = 0
            cell.transform = CGAffineTransform(translationX: 0, y: 12)
            UIView.animate(withDuration: 0.24, delay: 0, options: .curveEaseOut) {
                cell.alpha = 1
                cell.transform = .identity
            }
        }
    }

    private func sendTextMessage(_ text: String) {
        let sourceRect = inputPanel.fieldFrame(in: view)
        messages.append(Message(content: .text(text), isOutgoing: true, date: Date()))
        tableView.reloadData()
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        tableView.layoutIfNeeded()

        // Telegram's send transition (ChatMessageTransitionNode.swift:166-179,
        // 534-553): the new bubble slides in from the composer over 0.3s with
        // decomposed axes — vertical bezier (0.199, 0.011, 0.279, 0.910),
        // horizontal bezier (0.23, 1.0, 0.32, 1.0), both additive.
        if let cell = tableView.cellForRow(at: indexPath) {
            let targetRect = cell.convert(cell.bounds, to: view)
            let dx = sourceRect.minX - targetRect.minX
            let dy = sourceRect.maxY - targetRect.maxY

            let vertical = CABasicAnimation(keyPath: "position.y")
            vertical.fromValue = dy
            vertical.toValue = 0
            vertical.isAdditive = true
            vertical.duration = 0.3
            vertical.timingFunction = CAMediaTimingFunction(controlPoints: 0.19919473, 0.01064453, 0.27920937, 0.91025391)
            cell.layer.add(vertical, forKey: "sendTransitionY")

            let horizontal = CABasicAnimation(keyPath: "position.x")
            horizontal.fromValue = dx
            horizontal.toValue = 0
            horizontal.isAdditive = true
            horizontal.duration = 0.3
            horizontal.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1.0, 0.32, 1.0)
            cell.layer.add(horizontal, forKey: "sendTransitionX")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.messages.append(Message(content: .text("👍"), isOutgoing: false, date: Date()))
            self.tableView.reloadData()
            self.scrollToBottom(animated: true)
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - UITableViewDataSource

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        let isFirstInGroup = indexPath.row == 0
            || messages[indexPath.row - 1].isOutgoing != message.isOutgoing
        let isLastInGroup = indexPath.row == messages.count - 1
            || messages[indexPath.row + 1].isOutgoing != message.isOutgoing
        switch message.content {
        case .text, .particleText:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextMessageCell.reuseIdentifier, for: indexPath) as! TextMessageCell
            let particleHidden: Bool
            if case .particleText = message.content {
                particleHidden = !isParticleIntroRevealed
            } else {
                particleHidden = false
            }
            cell.configure(with: message, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup,
                           availableWidth: tableView.bounds.width, particleHidden: particleHidden) { [weak self] isRevealed in
                self?.isParticleIntroRevealed = isRevealed
            }
            return cell
        case .sticker:
            let cell = tableView.dequeueReusableCell(withIdentifier: StickerMessageCell.reuseIdentifier, for: indexPath) as! StickerMessageCell
            cell.configure(with: message)
            return cell
        }
    }
}
