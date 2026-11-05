import UIKit

/// UIKit counterpart of wallet_animations' ParticleEffect: a cloud sampled
/// from the glyph mask covers text, then disperses from the tap point to reveal
/// it. It intentionally uses Core Animation layers instead of WebGL so it also
/// works in this small, self-contained iOS prototype.
final class ParticleTextRevealView: UIView {
    private let label = UILabel()
    private var particleLayers: [CAShapeLayer] = []
    private var textIsHidden = false
    private var particlesNeedLayout = false
    private var onRevealChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleReveal(_:))))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, color: UIColor, hidden: Bool,
                   enabled: Bool, onRevealChanged: ((Bool) -> Void)?) {
        label.text = text
        label.font = font
        label.textColor = color
        isUserInteractionEnabled = enabled
        self.onRevealChanged = onRevealChanged

        guard enabled else {
            textIsHidden = false
            label.alpha = 0
            removeParticles()
            return
        }

        textIsHidden = hidden
        particlesNeedLayout = hidden
        label.alpha = hidden ? 0 : 1
        if hidden, bounds.width > 0, bounds.height > 0 { showParticles(animated: false) }
        if !hidden { removeParticles() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if textIsHidden, particlesNeedLayout, bounds.width > 0 {
            showParticles(animated: false)
        }
    }

    @objc private func toggleReveal(_ recognizer: UITapGestureRecognizer) {
        guard isUserInteractionEnabled else { return }
        let willReveal = textIsHidden
        let origin = recognizer.location(in: self)
        textIsHidden = !willReveal
        particlesNeedLayout = false
        onRevealChanged?(willReveal)

        if willReveal {
            reveal(from: origin)
        } else {
            showParticles(animated: true, origin: origin)
        }
    }

    private func showParticles(animated: Bool, origin: CGPoint? = nil) {
        removeParticles()
        guard bounds.width > 0, bounds.height > 0 else {
            particlesNeedLayout = true
            return
        }
        let points = particlePoints()
        guard !points.isEmpty else { return }

        particlesNeedLayout = false
        label.alpha = 0
        for point in points {
            let layer = makeParticle(at: animated ? scatteredPoint(from: point, origin: origin) : point)
            self.layer.addSublayer(layer)
            particleLayers.append(layer)
            if animated {
                let animation = CABasicAnimation(keyPath: "position")
                animation.fromValue = layer.position
                animation.toValue = point
                animation.duration = 0.26
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.position = point
                layer.add(animation, forKey: "assemble")
            } else {
                startDrifting(layer)
            }
        }

        if animated {
            let layers = particleLayers
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { [weak self] in
                guard self?.textIsHidden == true else { return }
                layers.forEach { self?.startDrifting($0) }
            }
        }
    }

    private func reveal(from origin: CGPoint) {
        UIView.animate(withDuration: 0.18, delay: 0.08, options: .curveEaseOut) {
            self.label.alpha = 1
        }
        for layer in particleLayers {
            layer.removeAnimation(forKey: "drift")
            let destination = scatteredPoint(from: layer.position, origin: origin)
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = layer.position
            position.toValue = destination
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [position, opacity]
            group.duration = 0.28
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(group, forKey: "disperse")
        }
        let departingParticles = particleLayers
        particleLayers.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            departingParticles.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func glyphPoints() -> [CGPoint] {
        let size = bounds.integral.size
        guard size.width > 0, size.height > 0 else { return [] }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            let proxy = UILabel(frame: CGRect(origin: .zero, size: size))
            proxy.numberOfLines = label.numberOfLines
            proxy.text = label.text
            proxy.font = label.font
            proxy.textColor = .black
            proxy.drawText(in: proxy.bounds)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data else { return [] }
        let bytes = CFDataGetBytePtr(data)
        let bytesPerPixel = cgImage.bitsPerPixel / cgImage.bitsPerComponent
        let bytesPerRow = cgImage.bytesPerRow
        guard let bytes, bytesPerPixel >= 4 else { return [] }

        var points: [CGPoint] = []
        let sampleStep = max(2, Int(size.height / 15))
        for y in stride(from: 0, to: cgImage.height, by: sampleStep) {
            for x in stride(from: 0, to: cgImage.width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                // UIGraphics may return BGRA or ARGB depending on the device.
                // The text is black on a transparent canvas, so coverage is the
                // strongest channel rather than assuming alpha is byte #3.
                let coverage = max(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
                guard coverage > 80, Int.random(in: 0...2) != 0 else { continue }
                points.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                if points.count == 110 { return points }
            }
        }
        return points
    }

    private func particlePoints() -> [CGPoint] {
        let maskPoints = glyphPoints()
        if !maskPoints.isEmpty { return maskPoints }

        // If Core Graphics cannot rasterise a font on a particular device,
        // retain the interaction with a soft text-sized cloud rather than
        // falling back to visible text.
        let count = min(110, max(56, Int(bounds.width * bounds.height / 42)))
        return (0..<count).map { _ in
            CGPoint(
                x: CGFloat.random(in: 4...max(4, bounds.width - 4)),
                y: CGFloat.random(in: 3...max(3, bounds.height - 3))
            )
        }
    }

    private func makeParticle(at point: CGPoint) -> CAShapeLayer {
        let radius = CGFloat.random(in: 0.8...1.7)
        let layer = CAShapeLayer()
        layer.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
        layer.fillColor = (label.textColor ?? Theme.incomingText).withAlphaComponent(CGFloat.random(in: 0.45...0.9)).cgColor
        layer.position = point
        return layer
    }

    private func startDrifting(_ layer: CAShapeLayer) {
        let origin = layer.position
        let drift = CAKeyframeAnimation(keyPath: "position")
        drift.values = [
            origin,
            CGPoint(x: origin.x + CGFloat.random(in: -3...3), y: origin.y + CGFloat.random(in: -2...2)),
            CGPoint(x: origin.x + CGFloat.random(in: -3...3), y: origin.y + CGFloat.random(in: -2...2)),
            origin,
        ]
        drift.duration = CFTimeInterval.random(in: 0.9...1.7)
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(drift, forKey: "drift")
    }

    private func scatteredPoint(from point: CGPoint, origin: CGPoint?) -> CGPoint {
        let direction = CGPoint(x: point.x - (origin?.x ?? bounds.midX), y: point.y - (origin?.y ?? bounds.midY))
        let length = max(1, hypot(direction.x, direction.y))
        let distance = CGFloat.random(in: 18...48)
        return CGPoint(
            x: point.x + direction.x / length * distance + CGFloat.random(in: -12...12),
            y: point.y + direction.y / length * distance + CGFloat.random(in: -9...9)
        )
    }

    private func removeParticles() {
        particleLayers.forEach { $0.removeFromSuperlayer() }
        particleLayers.removeAll()
    }
}
