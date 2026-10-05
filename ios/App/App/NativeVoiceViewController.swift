import UIKit

// Presentation only: no audio session, microphone capture, or network requests.
final class NativeVoiceViewController: UIViewController {
    private let orb = NativeVoiceOrbView()
    private let stateLabel = UILabel()
    private var microphoneButton: UIButton!
    private var isMuted = false

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "voice.screen"

        let close = NativeMaterial.button(symbol: "xmark", label: "Close voice") { [weak self] in
            self?.dismiss(animated: true)
        }
        close.accessibilityIdentifier = "voice.close"
        let closeSurface = NativeMaterial.wrap(close)
        let title = UILabel()
        title.text = "ChatPop"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .white
        title.textAlignment = .center
        title.accessibilityTraits = .header
        let brand = UIStackView(arrangedSubviews: [ChatPopBrand.mark(size: 28), title])
        brand.axis = .horizontal
        brand.alignment = .center
        brand.spacing = 7

        microphoneButton = NativeMaterial.button(symbol: "mic.fill", label: "Mute microphone") { [weak self] in
            self?.toggleMicrophone()
        }
        microphoneButton.accessibilityIdentifier = "voice.microphone"
        microphoneButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 27, weight: .medium), forImageIn: .normal)
        let microphoneSurface = NativeMaterial.view(radius: 34, interactive: true)
        microphoneButton.translatesAutoresizingMaskIntoConstraints = false
        microphoneSurface.contentView.addSubview(microphoneButton)

        stateLabel.font = .preferredFont(forTextStyle: .subheadline)
        stateLabel.adjustsFontForContentSizeCategory = true
        stateLabel.textColor = .secondaryLabel
        stateLabel.textAlignment = .center
        stateLabel.numberOfLines = 0

        let stage = UIView()
        stage.addSubview(orb)
        [closeSurface, brand, stage, microphoneSurface, stateLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        orb.translatesAutoresizingMaskIntoConstraints = false
        let safe = view.safeAreaLayoutGuide
        let preferredOrbSize = orb.widthAnchor.constraint(equalToConstant: 248)
        preferredOrbSize.priority = .defaultHigh
        NSLayoutConstraint.activate([
            closeSurface.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            closeSurface.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            closeSurface.widthAnchor.constraint(equalToConstant: 44),
            brand.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            brand.centerYAnchor.constraint(equalTo: closeSurface.centerYAnchor),
            brand.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 72),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: closeSurface.leadingAnchor, constant: -12),
            stage.topAnchor.constraint(equalTo: closeSurface.bottomAnchor, constant: 24),
            stage.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 32),
            stage.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -32),
            stage.bottomAnchor.constraint(equalTo: microphoneSurface.topAnchor, constant: -32),
            orb.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            orb.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            orb.widthAnchor.constraint(equalTo: orb.heightAnchor),
            orb.widthAnchor.constraint(lessThanOrEqualTo: stage.widthAnchor),
            orb.heightAnchor.constraint(lessThanOrEqualTo: stage.heightAnchor),
            preferredOrbSize,
            microphoneSurface.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            microphoneSurface.widthAnchor.constraint(equalToConstant: 68),
            microphoneSurface.heightAnchor.constraint(equalToConstant: 68),
            microphoneSurface.bottomAnchor.constraint(equalTo: stateLabel.topAnchor, constant: -12),
            microphoneButton.leadingAnchor.constraint(equalTo: microphoneSurface.contentView.leadingAnchor),
            microphoneButton.trailingAnchor.constraint(equalTo: microphoneSurface.contentView.trailingAnchor),
            microphoneButton.topAnchor.constraint(equalTo: microphoneSurface.contentView.topAnchor),
            microphoneButton.bottomAnchor.constraint(equalTo: microphoneSurface.contentView.bottomAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            stateLabel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24)
        ])
        updateMicrophone()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        orb.isActive = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        orb.isActive = false
    }

    override func accessibilityPerformEscape() -> Bool {
        dismiss(animated: true)
        return true
    }

    private func toggleMicrophone() {
        isMuted.toggle()
        updateMicrophone()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func updateMicrophone() {
        microphoneButton.setImage(UIImage(systemName: isMuted ? "mic.slash.fill" : "mic.fill"), for: .normal)
        microphoneButton.accessibilityLabel = isMuted ? "Unmute microphone" : "Mute microphone"
        microphoneButton.accessibilityValue = isMuted ? "Muted" : "On"
        microphoneButton.tintColor = isMuted ? .secondaryLabel : NativeMaterial.accent
        stateLabel.text = isMuted ? "Muted" : "Voice"
        orb.isMuted = isMuted
    }
}

private final class NativeVoiceOrbView: UIView {
    var isActive = false { didSet { updateAnimation() } }
    var isMuted = false { didSet { updateAnimation() } }
    private var waves: [CAShapeLayer] = []
    private var previousSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = UIColor(white: 0.97, alpha: 1)
        clipsToBounds = true
        for index in 0..<5 {
            let wave = CAShapeLayer()
            wave.fillColor = UIColor.clear.cgColor
            wave.strokeColor = UIColor(red: 0.16, green: 0.48 + CGFloat(index) * 0.06, blue: 0.94, alpha: 0.82 - CGFloat(index) * 0.11).cgColor
            wave.lineWidth = index == 0 ? 2.5 : 1.5
            wave.lineCap = .round
            layer.addSublayer(wave)
            waves.append(wave)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateAnimation), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAnimation), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pauseAnimation), name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        guard previousSize != bounds.size else { return }
        previousSize = bounds.size
        updateAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    @objc private func pauseAnimation() {
        waves.forEach { $0.removeAnimation(forKey: "voice.wave") }
    }

    @objc private func updateAnimation() {
        guard bounds.width > 0 else { return }
        let animate = isActive && !isMuted && window != nil && !UIAccessibility.isReduceMotionEnabled
            && UIApplication.shared.applicationState == .active
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, wave) in waves.enumerated() {
            wave.removeAnimation(forKey: "voice.wave")
            wave.frame = bounds
            wave.path = path(phase: 0, index: index, muted: isMuted)
            if animate {
                let animation = CAKeyframeAnimation(keyPath: "path")
                animation.values = (0...48).map { path(phase: CGFloat($0) / 48 * .pi * 2, index: index, muted: false) }
                animation.duration = 3.6
                animation.repeatCount = .infinity
                animation.calculationMode = .linear
                wave.add(animation, forKey: "voice.wave")
            }
        }
        CATransaction.commit()
    }

    private func path(phase: CGFloat, index: Int, muted: Bool) -> CGPath {
        let path = UIBezierPath()
        let inset = bounds.width * 0.1
        let width = bounds.width - inset * 2
        for step in 0...100 {
            let progress = CGFloat(step) / 100
            let envelope = pow(sin(progress * .pi), 2)
            let amplitude = muted ? bounds.height * 0.008 : bounds.height * (0.15 + CGFloat(index) * 0.021)
            let y = bounds.midY + sin(progress * .pi * 3 + phase + CGFloat(index) * 0.55) * envelope * amplitude
            let point = CGPoint(x: inset + progress * width, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path.cgPath
    }
}
