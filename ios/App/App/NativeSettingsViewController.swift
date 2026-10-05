import UIKit

enum ChatPopPreferences {
    static let changed = Notification.Name("ChatPopPreferencesChanged")
    static let blue = UIColor(red: 52 / 255, green: 120 / 255, blue: 212 / 255, alpha: 1)
    static let voices = ["Voice 1", "Voice 2", "Voice 3", "Voice 4"]
    static var name: String {
        get { UserDefaults.standard.string(forKey: "chatpop.displayName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "chatpop.displayName") }
    }
    static var voice: String {
        get { UserDefaults.standard.string(forKey: "chatpop.voice") ?? voices[0] }
        set { UserDefaults.standard.set(newValue, forKey: "chatpop.voice") }
    }
    static var theme: String {
        get { UserDefaults.standard.string(forKey: "chatpop.theme") ?? "Dark" }
        set {
            UserDefaults.standard.set(newValue, forKey: "chatpop.theme")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
    static var style: UIUserInterfaceStyle { theme == "Light" ? .light : theme == "System" ? .unspecified : .dark }
    @MainActor static func loadAccountSettings() async throws {
        guard let user = NativeAuthSession.shared.user else { return }
        let data = try await NativeAuthSession.shared.accountRequest("GET", path: "/me/settings")
        guard NativeAuthSession.shared.user?.id == user.id,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = object["settings"] as? [String: Any] else { return }
        name = user.displayName ?? ""
        if let value = settings["theme"] as? String { theme = value.capitalized }
        if let value = settings["selected_voice"] as? String,
           let number = Int(value.replacingOccurrences(of: "voice-", with: "")), (1...voices.count).contains(number) { voice = voices[number - 1] }
    }
    @MainActor static func saveAccountSetting(_ key: String, value: String) async throws {
        guard NativeAuthSession.shared.user != nil else { return }
        let data = try JSONSerialization.data(withJSONObject: [key: value])
        _ = try await NativeAuthSession.shared.accountRequest("PATCH", path: "/me/settings", body: data)
    }
    static func navigation(_ root: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.modalPresentationStyle = .fullScreen
        navigation.overrideUserInterfaceStyle = style
        navigation.view.tintColor = blue
        return navigation
    }
}

final class NativeSettingsViewController: UITableViewController {
    private var accountTask: Task<Void, Never>?
    private var sections: [(String, [String])] { [
        ("", ["ChatPop Plus / Pro"]),
        ("Account & Subscription", NativeAuthSession.shared.user == nil
            ? [NativeAuthSession.shared.state == .restoring ? "Restoring account..." : NativeAuthSession.shared.state == .offline ? "Account offline" : "Account / Sign in", "Name", "Manage Subscription", "Restore Purchases", "Delete Account"]
            : ["Account", "Name", "Manage Subscription", "Restore Purchases", "Sign out", "Delete Account"]),
        ("Voice", ChatPopPreferences.voices),
        ("Appearance", ["Dark", "Light", "System"]),
        ("Personalisation", ["Your Name"]),
        ("Help & App", ["How to Use ChatPop", "About ChatPop", "Feedback & Support", "Share ChatPop", "Rate ChatPop"]),
        ("Legal", ["Terms of Service", "Privacy Policy"])
    ] }
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(closeSettings))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Back to Chats"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let footer = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 80))
        footer.text = "ChatPop\nVersion \(version)"
        footer.numberOfLines = 0
        footer.textAlignment = .center
        footer.textColor = .secondaryLabel
        footer.font = .preferredFont(forTextStyle: .footnote)
        footer.adjustsFontForContentSizeCategory = true
        tableView.tableFooterView = footer
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: NativeAuthSession.changed, object: nil)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            do { try await NativeAuthSession.shared.restore(); try await ChatPopPreferences.loadAccountSettings(); self?.tableView.reloadData() }
            catch {
                guard let self = self, self.view.window != nil, self.presentedViewController == nil else { return }
                self.placeholder("Account", NativeAuthSession.message(for: error))
            }
        }
    }
    @objc private func accountChanged() { tableView.reloadData() }
    @objc private func closeSettings() { dismiss(animated: true) }
    override func accessibilityPerformEscape() -> Bool { closeSettings(); return true }
    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 2 ? "Voice previews are not connected yet." : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let text = sections[indexPath.section].1[indexPath.row]
        let cell = UITableViewCell(style: text == "Account" ? .subtitle : .value1, reuseIdentifier: nil)
        if text == "Account", let user = NativeAuthSession.shared.user {
            cell.textLabel?.text = user.displayName?.isEmpty == false ? user.displayName : "Account"
            cell.detailTextLabel?.text = user.email
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = UIImage(systemName: "person.crop.circle")
            cell.imageView?.tintColor = ChatPopPreferences.blue
            cell.selectionStyle = .none
            return cell
        }
        if text == "Account / Sign in" {
            let signIn = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = "Sign in"
            config.subtitle = "Sync your account and subscription"
            config.image = UIImage(systemName: "person.crop.circle")
            config.imagePadding = 12
            config.baseForegroundColor = .white
            config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
            signIn.configuration = config
            signIn.contentHorizontalAlignment = .leading
            signIn.addAction(UIAction { [weak self] _ in self?.openAuthentication() }, for: .touchUpInside)
            let surface = NativeMaterial.view(radius: 12, interactive: true)
            surface.backgroundColor = ChatPopPreferences.blue
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect()
                glass.isInteractive = true
                glass.tintColor = ChatPopPreferences.blue
                surface.effect = glass
            }
            surface.translatesAutoresizingMaskIntoConstraints = false
            signIn.translatesAutoresizingMaskIntoConstraints = false
            surface.contentView.addSubview(signIn)
            cell.contentView.addSubview(surface)
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                surface.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                surface.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                signIn.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor),
                signIn.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
                signIn.topAnchor.constraint(equalTo: surface.contentView.topAnchor),
                signIn.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
                signIn.heightAnchor.constraint(greaterThanOrEqualToConstant: 88)
            ])
            cell.selectionStyle = .none
            return cell
        }
        cell.textLabel?.text = text
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.tintColor = ChatPopPreferences.blue
        cell.accessoryType = .disclosureIndicator
        let symbols = ["ChatPop Plus / Pro": "sparkles", "Account / Sign in": "person.crop.circle", "Name": "person.text.rectangle", "Manage Subscription": "creditcard", "Restore Purchases": "arrow.clockwise", "Delete Account": "trash", "Your Name": "person", "How to Use ChatPop": "questionmark.circle", "About ChatPop": "info.circle", "Feedback & Support": "bubble.left.and.bubble.right", "Share ChatPop": "square.and.arrow.up", "Rate ChatPop": "star", "Terms of Service": "doc.text", "Privacy Policy": "hand.raised"]
        if let symbol = symbols[text] { cell.imageView?.image = UIImage(systemName: symbol) }
        if indexPath.section == 2 || indexPath.section == 3 {
            let selected = text == (indexPath.section == 2 ? ChatPopPreferences.voice : ChatPopPreferences.theme)
            cell.accessoryType = selected ? .checkmark : .none
            cell.imageView?.image = UIImage(systemName: indexPath.section == 2 ? "waveform" : text == "Dark" ? "moon" : text == "Light" ? "sun.max" : "circle.lefthalf.filled")
            if selected { cell.accessibilityTraits.insert(.selected) }
        }
        if text == "Name" || text == "Your Name" { cell.detailTextLabel?.text = ChatPopPreferences.name.isEmpty ? "Not set" : ChatPopPreferences.name }
        if text == "Name", let user = NativeAuthSession.shared.user {
            cell.detailTextLabel?.text = user.displayName?.isEmpty == false ? user.displayName : "Not set"
            cell.accessoryType = .disclosureIndicator
        }
        if text == "Sign out" {
            cell.imageView?.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
            cell.accessoryType = .none
        }
        if text == "Delete Account" { cell.textLabel?.textColor = .systemRed; cell.imageView?.tintColor = .systemRed }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].1[indexPath.row]
        if indexPath.section == 2 {
            performAccountAction { [weak self] in
                let value = "voice-\((ChatPopPreferences.voices.firstIndex(of: item) ?? 0) + 1)"
                try await ChatPopPreferences.saveAccountSetting("selected_voice", value: value)
                ChatPopPreferences.voice = item; self?.tableView.reloadData()
            }; return
        }
        if indexPath.section == 3 {
            performAccountAction { [weak self] in
                try await ChatPopPreferences.saveAccountSetting("theme", value: item.lowercased())
                ChatPopPreferences.theme = item
                self?.navigationController?.overrideUserInterfaceStyle = ChatPopPreferences.style
                self?.tableView.reloadData()
            }
            return
        }
        switch item {
        case "ChatPop Plus / Pro": navigationController?.pushViewController(NativePaywallViewController(), animated: true)
        case "Account": break
        case "Name": editName()
        case "Account offline": performAccountAction { try await NativeAuthSession.shared.restore(); try await ChatPopPreferences.loadAccountSettings() }
        case "Your Name": editName()
        case "Delete Account": confirmDeletion()
        case "Sign out": performAccountAction { try await NativeAuthSession.shared.signOut() }
        case "Account / Sign in": openAuthentication()
        case "Manage Subscription", "Restore Purchases": placeholder(item, "App Store subscriptions are not connected. No purchase or restoration was performed.")
        case "Share ChatPop":
            let share = UIActivityViewController(activityItems: ["ChatPop"], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(share, animated: true)
        default: navigationController?.pushViewController(NativeInfoViewController(title: item), animated: true)
        }
    }
    private func editName() {
        let alert = UIAlertController(title: "Your Name", message: NativeAuthSession.shared.user == nil ? "Saved on this device only." : "Saved to your ChatPop account.", preferredStyle: .alert)
        alert.addTextField { field in field.text = NativeAuthSession.shared.user?.displayName ?? ChatPopPreferences.name; field.placeholder = "Display name"; field.textContentType = .nickname; field.autocapitalizationType = .words }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let name = String((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            self?.performAccountAction {
                if NativeAuthSession.shared.user != nil { try await NativeAuthSession.shared.updateName(name) }
                ChatPopPreferences.name = name; self?.tableView.reloadData()
            }
        })
        present(alert, animated: true)
    }
    private func openAuthentication() {
        guard presentedViewController == nil, NativeAuthSession.shared.user == nil else { return }
        let navigation = ChatPopPreferences.navigation(NativeAuthViewController())
        navigation.overrideUserInterfaceStyle = .dark
        present(navigation, animated: true)
    }
    private func confirmDeletion() {
        guard NativeAuthSession.shared.user != nil else {
            placeholder("Delete Account", "Sign in to delete your account."); return
        }
        let alert = UIAlertController(title: "Delete account?", message: "This permanently deletes your account and conversations. Enter your password to confirm.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Password"; field.isSecureTextEntry = true
            field.textContentType = .password; field.autocapitalizationType = .none; field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak alert] _ in alert?.textFields?.first?.text = "" })
        alert.addAction(UIAlertAction(title: "Delete Account", style: .destructive) { [weak self, weak alert] _ in
            let password = alert?.textFields?.first?.text ?? ""
            alert?.textFields?.first?.text = ""
            alert?.dismiss(animated: true) {
                self?.performAccountAction { try await NativeAuthSession.shared.deleteAccount(password: password) }
            }
        })
        present(alert, animated: true)
    }
    private func performAccountAction(_ action: @escaping @MainActor () async throws -> Void) {
        guard accountTask == nil else { return }
        tableView.isUserInteractionEnabled = false
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        accountTask = Task { [weak self] in
            defer {
                self?.accountTask = nil
                self?.tableView.isUserInteractionEnabled = true
                self?.navigationItem.rightBarButtonItem = nil
            }
            do { try await action() }
            catch {
                guard let self = self, self.view.window != nil else { return }
                self.placeholder("Account", NativeAuthSession.message(for: error))
            }
        }
    }
    private func placeholder(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class NativeInfoViewController: UIViewController {
    init(title: String) { super.init(nibName: nil, bundle: nil); self.title = title }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let text = UITextView()
        text.isEditable = false
        text.backgroundColor = .clear
        text.font = .preferredFont(forTextStyle: .body)
        text.adjustsFontForContentSizeCategory = true
        text.textColor = .secondaryLabel
        text.text = title == "About ChatPop" ? "ChatPop\nA place for your conversations." : "\(title ?? "Information")\n\nThis page is not published yet."
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        let contentTop: NSLayoutYAxisAnchor
        if title == "About ChatPop" {
            let mark = ChatPopBrand.mark(size: 64)
            view.addSubview(mark)
            NSLayoutConstraint.activate([
                mark.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                mark.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24)
            ])
            contentTop = mark.bottomAnchor
        } else {
            contentTop = view.safeAreaLayoutGuide.topAnchor
        }
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: contentTop, constant: 16),
            text.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            text.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            text.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])
    }
}
