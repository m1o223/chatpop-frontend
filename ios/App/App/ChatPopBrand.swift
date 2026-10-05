import UIKit

enum ChatPopBrand {
    static func mark(size: CGFloat, accessible: Bool = false) -> UIImageView {
        let image = BrandImageView(image: UIImage(named: "ChatPopLogo")?.withRenderingMode(.alwaysOriginal))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFit
        image.backgroundColor = .black
        image.clipsToBounds = true
        image.layer.cornerCurve = .continuous
        image.layer.cornerRadius = size * 0.22
        image.isAccessibilityElement = accessible
        image.accessibilityLabel = accessible ? "ChatPop" : nil
        image.accessibilityIdentifier = "brand.logo"
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: size),
            image.heightAnchor.constraint(equalToConstant: size)
        ])
        image.updateAppearance()
        return image
    }

    static func centeredMark(size: CGFloat, accessible: Bool = false) -> UIView {
        let row = UIView()
        let image = mark(size: size, accessible: accessible)
        row.addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            image.topAnchor.constraint(equalTo: row.topAnchor),
            image.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        return row
    }
}

private final class BrandImageView: UIImageView {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }

    func updateAppearance() {
        // Keep the supplied black artwork intact; light surfaces use a compact badge.
        layer.borderWidth = traitCollection.userInterfaceStyle == .light ? 1 / max(1, traitCollection.displayScale) : 0
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}

// A single logo texture and native wordmark interpolate the approved reference poses.
final class ChatPopIntroView: UIView {
    static let duration: TimeInterval = 3.95
    private static var claimedLaunch = false
    static func claimLaunch() -> Bool {
        guard !claimedLaunch else { return false }
        claimedLaunch = true
        return true
    }

    private let logo = UIImageView(image: UIImage(named: "ChatPopLogo")?.preparingForDisplay())
    private let wordmark = UILabel()
    private let reveal = CALayer()
    private var started = false
    private var finishWork: DispatchWorkItem?
    var onFinish: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        accessibilityViewIsModal = true
        isAccessibilityElement = true
        accessibilityLabel = "ChatPop"
        accessibilityIdentifier = "brand.intro"
        logo.contentMode = .scaleAspectFit
        logo.isAccessibilityElement = false
        wordmark.text = "CHATPOP"
        wordmark.font = .systemFont(ofSize: 38, weight: .bold)
        wordmark.textColor = .white
        wordmark.isAccessibilityElement = false
        wordmark.accessibilityIdentifier = "brand.intro.wordmark"
        reveal.backgroundColor = UIColor.white.cgColor
        reveal.anchorPoint = CGPoint(x: 0, y: 0.5)
        wordmark.layer.mask = reveal
        addSubview(logo)
        addSubview(wordmark)
        logo.alpha = 0
        wordmark.alpha = 0
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !started else { return }
        let textSize = wordmark.sizeThatFits(CGSize(width: 400, height: 60))
        // Keep typography fixed; reduce only the logo footprint on narrow phones.
        let logoSize = min(148, max(84, bounds.width - textSize.width - 32))
        let width = logoSize + textSize.width
        let left = (bounds.width - width) / 2
        let middle = bounds.midY
        logo.frame = CGRect(x: left, y: middle - logoSize / 2, width: logoSize, height: logoSize)
        wordmark.frame = CGRect(x: left + logoSize, y: middle - textSize.height / 2,
                                width: textSize.width, height: textSize.height)
        reveal.bounds = CGRect(origin: .zero, size: wordmark.bounds.size)
        reveal.position = CGPoint(x: 0, y: wordmark.bounds.midY)
    }

    func start() {
        guard !started, window != nil else { return }
        layoutIfNeeded()
        started = true
        let reduced = UIAccessibility.isReduceMotionEnabled
        let clock = layer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        logo.alpha = 0
        wordmark.alpha = 0
        // Model values describe the final state; removing animations never flashes a logo.
        // Keep UIKit hit-testing active while Core Animation fades the presentation layer.
        alpha = 1
        CATransaction.commit()

        // Reveal the app while the brand is still present, not after a black gap.
        animate(layer, "opacity", [1, 1, 0], [0, 3.05, Self.duration], clock)
        if reduced {
            animate(logo.layer, "opacity", [0, 0, 1, 1], [0, 0.2, 0.8, Self.duration], clock)
            animate(wordmark.layer, "opacity", [0, 0, 1, 1], [0, 0.45, 1.2, Self.duration], clock)
        } else {
            let offscreen = -logo.bounds.width - logo.center.x
            let centered = bounds.midX - logo.center.x
            animate(logo.layer, "transform.translation.x", [offscreen, offscreen, centered, centered, 0, 0, offscreen],
                    [0, 0.2, 0.95, 1.2, 2.1, 3.45, Self.duration], clock)
            animate(logo.layer, "transform.scale", [1, 1, 1.03, 0.99, 1, 1, 0.97],
                    [0, 0.95, 1.04, 1.12, 1.2, 3.05, Self.duration], clock)
            animate(wordmark.layer, "transform.scale", [1, 1, 0.97], [0, 3.05, Self.duration], clock)
            animate(logo.layer, "opacity", [0, 0, 1, 1], [0, 0.2, 0.48, Self.duration], clock)
            animate(wordmark.layer, "opacity", [0, 0, 1, 1], [0, 1.2, 1.38, Self.duration], clock)
            animate(reveal, "bounds.size.width", [0, 0, wordmark.bounds.width, wordmark.bounds.width, 0, 0],
                    [0, 1.2, 2.1, 3.05, 3.85, Self.duration], clock)
            animate(wordmark.layer, "transform.translation.x", [-14, -14, 0, 0, -14, -14],
                    [0, 1.2, 2.1, 3.05, 3.85, Self.duration], clock)
        }
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    private func animate(_ target: CALayer, _ key: String, _ values: [CGFloat], _ seconds: [Double], _ clock: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: key)
        let needsEnd = seconds.last != Self.duration
        animation.values = needsEnd ? values + [values.last ?? 0] : values
        animation.keyTimes = (needsEnd ? seconds + [Self.duration] : seconds).map { NSNumber(value: $0 / Self.duration) }
        animation.duration = Self.duration
        animation.beginTime = clock
        animation.timingFunctions = (1..<(animation.values?.count ?? 1)).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        target.add(animation, forKey: "intro.\(key)")
    }

    @objc private func interrupted() { finish() }

    private func finish() {
        finishWork?.cancel()
        finishWork = nil
        layer.removeAllAnimations()
        logo.layer.removeAllAnimations()
        wordmark.layer.removeAllAnimations()
        reveal.removeAllAnimations()
        removeFromSuperview()
        let completion = onFinish
        onFinish = nil
        completion?()
    }

    deinit { finishWork?.cancel() }
}
