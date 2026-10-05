import UIKit

private struct SubscriptionCatalog: Decodable {
    enum Status: String, Decodable { case available, comingSoon, disabled }
    struct Provider: Decodable { let id: String; let name: String; let status: Status }
    struct Plan: Decodable {
        let id: String; let name: String; let description: String; let badge: String
        let models: [String]; let features: [String]; let creativeCredits: Int?
        let usageLevel: String; let monthlyPrice: String?; let yearlyPrice: String?
    }
    struct Feature: Decodable {
        let id: String; let title: String; let description: String; let symbol: String; let status: Status
    }
    struct Section: Decodable { let title: String; let columns: Bool; let features: [Feature] }
    let providers: [Provider]; let plans: [Plan]; let sections: [Section]
    static func load() -> SubscriptionCatalog? {
        guard let url = Bundle.main.url(forResource: "plans", withExtension: "json", subdirectory: "public/subscription"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.plans.count == 2 else { return nil }
        return value
    }
}

final class NativePaywallViewController: UIViewController {
    private let catalog = SubscriptionCatalog.load()
    private let tier = UISegmentedControl(items: ["Plus", "Pro"])
    private let billing = UISegmentedControl(items: ["Monthly", "Yearly"])
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let dock = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let price = UILabel()
    private let selection = UILabel()
    private let descriptionLabel = UILabel()
    private let badge = UILabel()
    private let credits = UILabel()
    private let usage = UILabel()
    private let priority = UILabel()
    private let continueButton = UIButton(type: .system)
    private let purchaseScroll = UIScrollView()
    private var purchaseStack: UIStackView!
    private var dockHeight: NSLayoutConstraint!
    private var providerLabels: [(SubscriptionCatalog.Provider, UILabel)] = []
    private var featureLabels: [(SubscriptionCatalog.Feature, UILabel)] = []
    private var columnStacks: [UIStackView] = []
    private var surfaces: [UIView] = []
    private var previousInset: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ChatPop Plus / Pro"
        view.backgroundColor = .systemBackground
        view.tintColor = ChatPopPreferences.blue
        let close = NativeMaterial.wrap(NativeMaterial.button(symbol: "xmark", label: "Close subscription") { [weak self] in self?.leave() })
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: close)
        content.axis = .vertical
        content.spacing = 24
        for item in [scroll, dock] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        scroll.addSubview(content)
        scroll.alwaysBounceVertical = true
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dock.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let hero = vertical([ChatPopBrand.centeredMark(size: 96), label("ChatPop Plus / Pro", .title1), label("All your AI tools in one app", .subheadline, secondary: true)], spacing: 8)
        for case let text as UILabel in hero.arrangedSubviews { text.textAlignment = .center }
        content.addArrangedSubview(hero)
        tier.selectedSegmentIndex = 0
        tier.accessibilityLabel = "Plan"
        tier.addTarget(self, action: #selector(updatePlan), for: .valueChanged)
        content.addArrangedSubview(tier)
        badge.font = .preferredFont(forTextStyle: .caption1)
        badge.textColor = ChatPopPreferences.blue
        badge.textAlignment = .center
        descriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .center
        descriptionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        content.addArrangedSubview(vertical([badge, descriptionLabel], spacing: 5))
        if let catalog {
            let models = vertical([label("AI Models", .headline), label("Access leading AI models in one place", .subheadline, secondary: true)], spacing: 8)
            let providers = catalog.providers.filter { $0.status != .disabled }
            for index in stride(from: 0, to: providers.count, by: 2) {
                let cells = providers[index..<min(index + 2, providers.count)].map { provider -> UIView in
                    let status = label("", .caption2, secondary: true)
                    providerLabels.append((provider, status))
                    return vertical([label(provider.name, .subheadline), status], spacing: 4)
                }
                models.addArrangedSubview(columns(cells))
            }
            content.addArrangedSubview(surface(models))
            for section in catalog.sections {
                let cards = section.features.filter { $0.status != .disabled }.map { feature -> UIView in
                    let state = label("", .caption2, secondary: true)
                    featureLabels.append((feature, state))
                    return surface(featureRow(feature.title, feature.description, feature.symbol, state, compact: !section.columns))
                }
                content.addArrangedSubview(vertical([label(section.title, .title3), section.columns ? columns(cards) : vertical(cards, spacing: 8)], spacing: 10))
            }
            content.addArrangedSubview(vertical([
                label("Usage", .title3),
                surface(featureRow("Higher Usage Limits", "", "chart.bar", usage)),
                surface(featureRow("Monthly Creative Credits", "Credits are used for image and video generation.", "sparkles", credits)),
                surface(featureRow("Priority Access", "", "bolt", priority))
            ], spacing: 10))
        } else { content.addArrangedSubview(label("Plan information is unavailable. Please try again later.", .body, secondary: true)) }
        setupDock()
        updateColors()
        updatePlan()
    }

    private func setupDock() {
        billing.selectedSegmentIndex = 0
        billing.accessibilityLabel = "Billing period"
        billing.addTarget(self, action: #selector(updatePrice), for: .valueChanged)
        selection.font = .preferredFont(forTextStyle: .caption1)
        selection.textColor = .secondaryLabel
        selection.numberOfLines = 0
        price.font = .preferredFont(forTextStyle: .headline)
        price.numberOfLines = 0
        let priceRow = UIStackView(arrangedSubviews: [selection, price])
        priceRow.spacing = 12
        priceRow.distribution = .fillEqually
        price.textAlignment = .right
        continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        continueButton.addAction(UIAction { [weak self] _ in self?.notice("Subscriptions are not available yet. No charge will be made.") }, for: .touchUpInside)
        let restore = button("Restore Purchases") { [weak self] in self?.notice("App Store restoration is not connected. No purchase was restored.") }
        let legal = columns([button("Terms of Service") { [weak self] in self?.showInfo("Terms of Service") }, button("Privacy Policy") { [weak self] in self?.showInfo("Privacy Policy") }])
        let stack = vertical([billing, priceRow, continueButton, restore, legal], spacing: 6)
        purchaseStack = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        purchaseScroll.translatesAutoresizingMaskIntoConstraints = false
        dock.contentView.addSubview(purchaseScroll)
        purchaseScroll.addSubview(stack)
        dockHeight = dock.heightAnchor.constraint(equalToConstant: 260)
        NSLayoutConstraint.activate([
            dockHeight,
            purchaseScroll.topAnchor.constraint(equalTo: dock.contentView.topAnchor, constant: 12),
            purchaseScroll.leadingAnchor.constraint(equalTo: dock.contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            purchaseScroll.trailingAnchor.constraint(equalTo: dock.contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            purchaseScroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: purchaseScroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: purchaseScroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: purchaseScroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: purchaseScroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: purchaseScroll.frameLayoutGuide.widthAnchor)
        ])
    }
    private func label(_ text: String, _ style: UIFont.TextStyle, secondary: Bool = false) -> UILabel {
        let value = UILabel()
        value.text = text
        value.font = .preferredFont(forTextStyle: style)
        value.adjustsFontForContentSizeCategory = true
        value.numberOfLines = 0
        value.textColor = secondary ? .secondaryLabel : .label
        return value
    }
    private func vertical(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }
    private func columns(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        columnStacks.append(stack)
        return stack
    }
    private func surface(_ child: UIView) -> UIView {
        let panel = UIView()
        panel.layer.cornerRadius = 8
        panel.layer.borderWidth = 0.5
        surfaces.append(panel)
        child.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            child.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
            child.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            child.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14)
        ])
        return panel
    }
    private func featureRow(_ title: String, _ detail: String, _ symbol: String, _ status: UILabel, compact: Bool = true) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = ChatPopPreferences.blue
        icon.contentMode = .left
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        var views: [UIView] = [label(title, .headline)]
        if !detail.isEmpty { views.append(label(detail, .subheadline, secondary: true)) }
        views.append(status)
        let copy = vertical(views, spacing: 5)
        let row = UIStackView(arrangedSubviews: [icon, copy])
        row.axis = compact ? .horizontal : .vertical
        row.alignment = compact ? .top : .leading
        row.spacing = 10
        if !compact { copy.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true }
        return row
    }
    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let result = UIButton(type: .system)
        result.setTitle(title, for: .normal)
        result.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        result.titleLabel?.numberOfLines = 0
        result.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        result.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return result
    }
    @objc private func updatePlan() {
        guard let catalog else { continueButton.isEnabled = false; price.text = "Unavailable"; return }
        let plan = catalog.plans[tier.selectedSegmentIndex]
        badge.text = plan.badge
        descriptionLabel.text = plan.description
        for (provider, state) in providerLabels {
            state.text = !plan.models.contains(provider.id) ? "Pro · Coming soon" : provider.status == .available ? "Available" : "Coming soon"
        }
        for (feature, state) in featureLabels {
            state.text = !plan.features.contains(feature.id) ? "Pro · Coming soon" : feature.status == .available ? "Available in app" : "Coming soon"
        }
        usage.text = "\(plan.usageLevel) · Coming soon"
        credits.text = plan.creativeCredits.map { "\($0.formatted()) credits / month · Coming soon" } ?? "\(plan.name) allowance announced at launch"
        priority.text = plan.features.contains("priority") ? "Planned for Pro · Coming soon" : "Pro · Coming soon"
        var config = UIButton.Configuration.filled()
        config.title = "Continue with \(plan.name)"
        config.baseBackgroundColor = ChatPopPreferences.blue
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        continueButton.configuration = config
        updatePrice()
    }
    @objc private func updatePrice() {
        guard let catalog else { return }
        let plan = catalog.plans[tier.selectedSegmentIndex]
        let yearly = billing.selectedSegmentIndex == 1
        let update = {
            self.selection.text = "ChatPop \(plan.name)\n\(yearly ? "Yearly" : "Monthly")"
            self.price.text = (yearly ? plan.yearlyPrice : plan.monthlyPrice) ?? "Coming soon"
        }
        if UIAccessibility.isReduceMotionEnabled { update() }
        else { UIView.transition(with: price, duration: 0.2, options: .transitionCrossDissolve, animations: update) }
    }
    private func updateColors() {
        for surface in surfaces {
            surface.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.065, alpha: 1) : .secondarySystemBackground }
            surface.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        }
        for control in [tier, billing] {
            control.selectedSegmentTintColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.21, alpha: 1) : .tertiarySystemBackground }
            control.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .selected)
            control.setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel], for: .normal)
        }
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
        for stack in columnStacks { stack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let stack = purchaseStack, purchaseScroll.bounds.width > 0 {
            let natural = stack.systemLayoutSizeFitting(CGSize(width: purchaseScroll.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            dockHeight.constant = min(natural + view.safeAreaInsets.bottom + 16, view.bounds.height * 0.48)
        }
        let inset = max(0, scroll.frame.maxY - dock.frame.minY) + 16
        if previousInset != inset { previousInset = inset; scroll.contentInset.bottom = inset; scroll.verticalScrollIndicatorInsets.bottom = inset }
    }
    private func showInfo(_ title: String) { navigationController?.pushViewController(NativeInfoViewController(title: title), animated: true) }
    private func notice(_ message: String) {
        let alert = UIAlertController(title: "ChatPop", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    @objc private func leave() {
        if let navigation = navigationController, navigation.viewControllers.count > 1 { navigation.popViewController(animated: true) }
        else { dismiss(animated: true) }
    }
    override func accessibilityPerformEscape() -> Bool { leave(); return true }
    override var keyCommands: [UIKeyCommand]? { [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(leave))] }
}
