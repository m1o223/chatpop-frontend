import UIKit

final class NativeModelViewController: UIViewController {
    var onSelect: ((String) -> Void)?
    private let providers: [NativeProvider]
    private let selected: String
    private weak var anchor: UIView?
    private let panel = NativeMaterial.view(radius: 28)
    private let backdrop = UIButton(type: .custom)
    private var closing = false

    init(providers: [NativeProvider], selected: String, anchor: UIView) {
        self.providers = providers
        self.selected = selected
        self.anchor = anchor
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = ChatPopPreferences.style
        view.backgroundColor = .clear
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        backdrop.accessibilityLabel = "Dismiss model selection"
        // The selector is outside the panel, so tapping it again also closes the picker.
        backdrop.addAction(UIAction { [weak self] _ in self?.closePanel() }, for: .touchUpInside)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)

        view.addSubview(panel)
        let heading = UILabel()
        heading.text = "Choose a model"
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true
        heading.accessibilityTraits = .header
        let close = NativeMaterial.button(symbol: "xmark", label: "Close model panel") { [weak self] in self?.closePanel() }
        let header = UIStackView(arrangedSubviews: [heading, close])
        header.alignment = .center
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44).isActive = true
        header.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(header)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        // Each provider is a section containing model rows; additional rows can be added later.
        let sections = providers.map { (title: $0.name.uppercased(), models: [$0]) }
        for section in sections {
            let sectionTitle = UILabel()
            sectionTitle.text = section.title
            sectionTitle.font = .preferredFont(forTextStyle: .caption1)
            sectionTitle.adjustsFontForContentSizeCategory = true
            sectionTitle.textColor = .secondaryLabel
            sectionTitle.accessibilityTraits = .header
            stack.addArrangedSubview(sectionTitle)
            for provider in section.models {
            let name = UILabel()
            name.text = provider.name == "Auto" ? "Auto" : "\(provider.name) models"
            name.numberOfLines = 0
            name.font = .preferredFont(forTextStyle: .body)
            name.adjustsFontForContentSizeCategory = true
            let detail = UILabel()
            detail.text = provider.description
            detail.font = .preferredFont(forTextStyle: .caption1)
            detail.adjustsFontForContentSizeCategory = true
            detail.textColor = .secondaryLabel
            detail.numberOfLines = 0
            let labels = UIStackView(arrangedSubviews: provider.name == "Auto" ? [name, detail] : [name])
            labels.axis = .vertical
            labels.spacing = 4
            let check = UIImageView(image: provider.name == selected ? UIImage(systemName: "checkmark") : nil)
            check.tintColor = NativeMaterial.accent
            check.contentMode = .center
            check.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let content = UIStackView(arrangedSubviews: [labels, check])
            content.alignment = .center
            content.spacing = 12
            content.isUserInteractionEnabled = false
            let row = UIButton(type: .system)
            row.accessibilityLabel = "\(provider.name), \(provider.description)"
            if provider.name == selected { row.accessibilityTraits.insert(.selected) }
            content.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
                content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                content.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
            ])
            row.addAction(UIAction { [weak self] _ in
                self?.onSelect?(provider.name)
                self?.closePanel()
            }, for: .touchUpInside)
            stack.addArrangedSubview(row)
            }
        }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        view.accessibilityViewIsModal = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let source = anchor.map { view.convert($0.bounds, from: $0) }
            ?? CGRect(x: safe.midX, y: safe.minY, width: 0, height: 44)
        let width = min(460, max(0, safe.width - 24))
        let top = max(safe.minY + 8, source.maxY + 8)
        let height = min(520, max(0, safe.maxY - top - 12))
        let left = min(max(source.midX - width / 2, safe.minX + 12), safe.maxX - width - 12)
        // Use bounds/center so rotation and safe-area updates do not fight the animated transform.
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        panel.center = CGPoint(x: left + width / 2, y: top + height / 2)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        panel.alpha = 0
        backdrop.alpha = 0
        panel.transform = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX: 0, y: -16)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.28,
                       delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.panel.alpha = 1
            self.backdrop.alpha = 1
            self.panel.transform = .identity
        }
    }

    private func closePanel() {
        guard !closing else { return }
        closing = true
        panel.isUserInteractionEnabled = false
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2,
                       delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.panel.alpha = 0
            self.backdrop.alpha = 0
            self.panel.transform = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX: 0, y: -12)
        } completion: { _ in self.dismiss(animated: false) }
    }

    override func accessibilityPerformEscape() -> Bool {
        closePanel()
        return true
    }
}
