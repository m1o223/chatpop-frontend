import UIKit

enum NativeAttachmentAction: String, CaseIterable {
    case camera, photos, audio, file

    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .camera: return "camera.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .audio: return "waveform"
        case .file: return "doc.fill"
        }
    }
    var color: UIColor {
        switch self {
        case .camera: return UIColor(red: 0.32, green: 0.72, blue: 0.56, alpha: 1)
        case .photos: return UIColor(red: 0.91, green: 0.62, blue: 0.34, alpha: 1)
        case .audio: return UIColor(red: 0.54, green: 0.58, blue: 0.88, alpha: 1)
        case .file: return UIColor(red: 0.91, green: 0.49, blue: 0.49, alpha: 1)
        }
    }
}

final class NativeAttachmentViewController: UIViewController {
    var onSelect: ((NativeAttachmentAction) -> Void)?
    private weak var anchor: UIView?
    private let blur = UIVisualEffectView()
    private let backdrop = UIButton(type: .custom)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var rows: [AttachmentActionButton] = []
    private var closeButton: UIButton!
    private var closeSurface: UIVisualEffectView!
    private var appeared = false
    private var closing = false

    init(anchor: UIView) {
        self.anchor = anchor
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "attachment.menu"
        view.accessibilityViewIsModal = true
        blur.isUserInteractionEnabled = false
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        backdrop.alpha = 0
        backdrop.isAccessibilityElement = false
        backdrop.accessibilityIdentifier = "attachment.backdrop"
        backdrop.addAction(UIAction { [weak self] _ in self?.closeMenu() }, for: .touchUpInside)
        [blur, backdrop].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
            NSLayoutConstraint.activate([
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                $0.topAnchor.constraint(equalTo: view.topAnchor),
                $0.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false
        scroll.accessibilityIdentifier = "attachment.actions"
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        for action in NativeAttachmentAction.allCases {
            let row = AttachmentActionButton(action: action)
            row.addAction(UIAction { [weak self] _ in self?.closeMenu(selecting: action) }, for: .touchUpInside)
            rows.append(row)
            stack.addArrangedSubview(row)
        }

        closeButton = NativeMaterial.button(symbol: "xmark", label: "Close attachments") { [weak self] in self?.closeMenu() }
        closeButton.accessibilityIdentifier = "attachment.close"
        closeSurface = NativeMaterial.view(radius: 24, interactive: true)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeSurface.contentView.addSubview(closeButton)
        view.addSubview(closeSurface)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: closeSurface.contentView.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: closeSurface.contentView.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: closeSurface.contentView.topAnchor),
            closeButton.bottomAnchor.constraint(equalTo: closeSurface.contentView.bottomAnchor)
        ])
        view.accessibilityElements = rows + [closeButton!]
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let source = anchor.map { view.convert($0.bounds, from: $0) }
            ?? CGRect(x: safe.minX + 16, y: safe.maxY - 56, width: 44, height: 44)
        let left = min(max(source.midX - 24, safe.minX + 12), max(safe.minX + 12, safe.maxX - 60))
        let closeY = min(max(source.midY, safe.minY + 32), safe.maxY - 28)
        closeSurface.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        closeSurface.center = CGPoint(x: left + 24, y: closeY)
        let width = max(0, min(300, safe.maxX - left - 16))
        let contentHeight = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let bottom = closeY - 24 - 16
        let height = min(contentHeight, max(0, bottom - safe.minY - 12))
        scroll.frame = CGRect(x: left, y: bottom - height, width: width, height: height)
        scroll.isScrollEnabled = !closing && contentHeight > height + 1
        scroll.clipsToBounds = contentHeight > height + 1
        scroll.layoutIfNeeded()
        if !appeared { setCollapsed() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !appeared else { return }
        view.layoutIfNeeded()
        appeared = true
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.42,
                       delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.3,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.blur.effect = self.backgroundEffect
            self.backdrop.alpha = 1
            self.closeSurface.alpha = 1
            self.closeSurface.transform = .identity
            self.rows.forEach { $0.alpha = 1; $0.transform = .identity }
        } completion: { [weak self] _ in
            guard let self, !self.closing else { return }
            UIAccessibility.post(notification: .screenChanged, argument: self.rows.first)
        }
    }

    private var backgroundEffect: UIVisualEffect? {
        UIAccessibility.isReduceTransparencyEnabled ? nil : UIBlurEffect(style: .systemUltraThinMaterialDark)
    }

    @objc private func keyboardDidHide() {
        // The composer moves with UIKeyboardLayoutGuide; keep the close control at its final '+' position.
        guard appeared, !closing else { return }
        view.setNeedsLayout()
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2,
                       delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private func setCollapsed() {
        backdrop.alpha = 0
        if UIAccessibility.isReduceTransparencyEnabled {
            backdrop.backgroundColor = UIColor(white: 0.025, alpha: 1)
        }
        closeSurface.alpha = 0
        closeSurface.transform = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(rotationAngle: -.pi / 4)
        for row in rows {
            row.alpha = 0
            guard !UIAccessibility.isReduceMotionEnabled else { row.transform = .identity; continue }
            // Translate each row's untransformed center back to the original trigger, then lift it on opening.
            let center = stack.convert(row.center, to: view)
            row.transform = CGAffineTransform(translationX: 0, y: closeSurface.center.y - center.y).scaledBy(x: 0.94, y: 0.94)
        }
    }

    func closeMenu(selecting action: NativeAttachmentAction? = nil) {
        guard !closing else { return }
        closing = true
        closeButton.isEnabled = false
        rows.forEach { $0.isEnabled = false }
        scroll.isScrollEnabled = false
        let onSelect = self.onSelect
        self.onSelect = nil
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.28,
                       delay: 0, options: [.beginFromCurrentState, .curveEaseIn, .allowUserInteraction]) {
            self.blur.effect = nil
            self.setCollapsed()
        } completion: { [weak self] _ in
            self?.dismiss(animated: false) {
                if let action { onSelect?(action) }
            }
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        closeMenu()
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape))]
    }

    @objc private func escape() { closeMenu() }
}

private final class AttachmentActionButton: UIButton {
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.white.withAlphaComponent(0.07) : .clear }
    }

    init(action: NativeAttachmentAction) {
        super.init(frame: .zero)
        accessibilityLabel = action.title
        accessibilityIdentifier = "attachment.\(action.rawValue)"
        layer.cornerRadius = 8
        let circle = UIView()
        circle.backgroundColor = action.color.withAlphaComponent(0.19)
        circle.layer.cornerRadius = 24
        let icon = UIImageView(image: UIImage(systemName: action.symbol))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        icon.tintColor = action.color
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        let label = UILabel()
        label.text = action.title
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 19, weight: .medium))
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .white
        let content = UIStackView(arrangedSubviews: [circle, label])
        content.spacing = 16
        content.alignment = .center
        content.isUserInteractionEnabled = false
        content.isAccessibilityElement = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 48),
            circle.heightAnchor.constraint(equalToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: circle.leadingAnchor),
            icon.trailingAnchor.constraint(equalTo: circle.trailingAnchor),
            icon.topAnchor.constraint(equalTo: circle.topAnchor),
            icon.bottomAnchor.constraint(equalTo: circle.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
