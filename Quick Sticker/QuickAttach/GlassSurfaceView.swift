import UIKit

/// Analog of Telegram-iOS `GlassBackgroundView` (GlassBackgroundComponent.swift),
/// `.panel` kind, light theme. iOS 26+: native UIGlassEffect(.regular) with a
/// white-10% tint (.clear gets no tint in light mode; Telegram additionally
/// tweaks private luma parameters we cannot reach). Pre-26 fallback approximates
/// their LegacyGlassView: soft blur + white-70% fill + edge highlight + drop shadow
/// (generateLegacyGlassImage / generateLegacyShadowImage).
final class GlassSurfaceView: UIView {
    enum GlassStyle { case regular, clear }

    let effectView = UIVisualEffectView()
    private let legacyFillView = UIView()
    private let fixedCornerRadius: CGFloat?
    var contentView: UIView { effectView.contentView }

    init(style: GlassStyle = .regular, interactive: Bool = false, cornerRadius: CGFloat? = nil) {
        self.fixedCornerRadius = cornerRadius
        super.init(frame: .zero)
        addSubview(effectView)
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: style == .clear ? .clear : .regular)
            glass.isInteractive = interactive
            if style == .regular {
                glass.tintColor = UIColor(white: 1.0, alpha: 0.1) // GlassBackgroundComponent.swift:752-754
            }
            effectView.effect = glass
            if let cornerRadius {
                effectView.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
            } else {
                effectView.cornerConfiguration = .capsule()
            }
        } else {
            effectView.effect = UIBlurEffect(style: .light)
            effectView.clipsToBounds = true
            legacyFillView.backgroundColor = UIColor(white: 1.0, alpha: 0.7) // LegacyGlassView, :710-718
            effectView.contentView.addSubview(legacyFillView)
            // Edge highlight + drop shadow per generateLegacyGlassImage/-ShadowImage.
            effectView.layer.borderWidth = 1.0
            effectView.layer.borderColor = UIColor(white: 1.0, alpha: 0.5).cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        if #unavailable(iOS 26.0) {
            effectView.layer.cornerRadius = fixedCornerRadius ?? bounds.height / 2
            legacyFillView.frame = effectView.contentView.bounds
        }
    }
}
