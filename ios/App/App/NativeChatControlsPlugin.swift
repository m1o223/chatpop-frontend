import Capacitor
import UIKit

@objc(NativeChatControlsPlugin)
public final class NativeChatControlsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeChatControlsPlugin"
    public let jsName = "NativeChatControls"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "configure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hide", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showChats", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "closeChats", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "accountState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "accountRequest", returnType: CAPPluginReturnPromise)
    ]
    weak var host: ChatPopViewController?
    private weak var chatsMenu: NativeChatsViewController?
    public override func load() {
        NotificationCenter.default.addObserver(self, selector: #selector(authChanged), name: NativeAuthSession.changed, object: nil)
    }
    @objc private func authChanged() {
        Task { @MainActor in
            let session = NativeAuthSession.shared
            if session.state == .signedOut || session.state == .expired { ChatPopPreferences.name = "" }
            self.notifyListeners("account", data: self.accountSnapshot())
        }
    }
    @MainActor private func accountSnapshot() -> [String: Any] {
        let session = NativeAuthSession.shared
        return ["state": session.state.rawValue, "userId": session.user?.id ?? ""]
    }
    @objc func accountState(_ call: CAPPluginCall) {
        Task { @MainActor in
            do { try await NativeAuthSession.shared.restore() } catch { /* Offline state is returned without removing credentials. */ }
            call.resolve(accountSnapshot())
        }
    }
    @objc func accountRequest(_ call: CAPPluginCall) {
        Task { @MainActor in
            let path = call.getString("path") ?? "", method = call.getString("method") ?? "GET"
            guard ["GET", "POST", "PATCH", "DELETE"].contains(method),
                  path.range(of: #"^/(me(/settings)?|chats(/[0-9a-fA-F-]{36}(/messages)?)?|media(/[0-9a-fA-F-]{36})?)(\?[a-zA-Z0-9%=&._~-]+)?$"#, options: .regularExpression) != nil,
                  !(method == "DELETE" && path == "/me") else { call.reject("Unsupported account request"); return }
            do {
                let body = try call.getObject("body").map { try JSONSerialization.data(withJSONObject: $0) }
                let data = try await NativeAuthSession.shared.accountRequest(method, path: path, body: body)
                let result = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                call.resolve(result)
            } catch { call.reject(NativeAuthSession.message(for: error)) }
        }
    }

    @objc func showChats(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let host = self.host, host.presentedViewController == nil else {
                call.reject("Chats cannot be presented right now")
                return
            }
            let entries = (call.options["chats"] as? [[String: Any]] ?? []).compactMap { item -> NativeChatHistoryItem? in
                guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
                return NativeChatHistoryItem(id: id, title: title)
            }
            let menu = NativeChatsViewController(chats: entries, selected: call.getString("activeId") ?? "")
            menu.onFinish = { [weak self] action, selected in
                self?.chatsMenu = nil
                call.resolve(["action": action, "selectedId": selected])
            }
            self.chatsMenu = menu
            host.view.endEditing(true)
            host.present(menu, animated: true) { menu.presentationFinished() }
        }
    }

    @objc func closeChats(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.chatsMenu?.close()
            call.resolve()
        }
    }

    @objc func configure(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let controls = self?.host?.chatControls else {
                call.reject("Native chat controls are unavailable")
                return
            }
            let raw = call.options["providers"] as? [[String: Any]] ?? []
            controls.providers = raw.compactMap { item in
                guard let name = item["name"] as? String, let description = item["description"] as? String else { return nil }
                return NativeProvider(name: name, description: description)
            }
            guard !controls.providers.isEmpty else {
                call.reject("Model providers are required")
                return
            }
            controls.apply(chatID: call.getString("chatId") ?? "", draft: call.getString("draft") ?? "",
                           model: call.getString("model") ?? "Auto", hidden: call.getBool("hidden") ?? false, reset: true)
            self?.host?.view.layoutIfNeeded()
            controls.reportLayout(force: true)
            self?.notifyListeners("control", data: ["type": "appearance", "theme": ChatPopPreferences.theme.lowercased()])
            call.resolve(["material": NativeMaterial.kind])
        }
    }

    @objc func updateState(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let controls = self?.host?.chatControls else {
                call.reject("Native chat controls are unavailable")
                return
            }
            controls.apply(chatID: call.getString("chatId") ?? "", draft: call.getString("draft") ?? "",
                           model: call.getString("model") ?? "Auto", hidden: call.getBool("hidden") ?? false)
            call.resolve()
        }
    }

    @objc func hide(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.host?.chatControls?.endEditing(true)
            self?.host?.chatControls?.isHidden = true
            call.resolve()
        }
    }
}

private struct NativeChatHistoryItem {
    let id: String
    let title: String
}

private final class NativeChatsViewController: UIViewController, UITextFieldDelegate, UIScrollViewDelegate {
    var onFinish: ((String, String) -> Void)?
    private var chats: [NativeChatHistoryItem]
    private var historyTask: Task<Void, Never>?
    private var hasMore = false
    private var historyOffset = 0
    private var selected: String
    private var closing = false
    private var presentationComplete = false
    private var pendingClose: String?
    private let pageTransition = ChatsPageTransitionDelegate()
    private let blue = UIColor(red: 52 / 255, green: 120 / 255, blue: 212 / 255, alpha: 1)
    private let rows = UIStackView()
    private let scroll = UIScrollView()
    private let creativeCard = NativeCreativeStudioCard()
    private var menuVisible = false
    private let field = UITextField()
    private let searchToggle = UIButton(type: .system)
    private let searchFields = UIStackView()
    private let menuHeader = UIStackView()
    private let searchSurface = NativeMaterial.view(radius: 24, interactive: true)
    private var menuInsetsInstalled = false
    private var compactSearch: NSLayoutConstraint!
    private var expandedSearch: NSLayoutConstraint!

    init(chats: [NativeChatHistoryItem], selected: String) {
        self.chats = chats
        self.selected = selected
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = pageTransition
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, style: UIFont.TextStyle, secondary: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = secondary ? .secondaryLabel : .label
        label.numberOfLines = 0
        return label
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        view.tintColor = blue
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "chats.menu"
        NotificationCenter.default.addObserver(self, selector: #selector(historyAccountChanged), name: NativeAuthSession.changed, object: nil)
        let backButton = NativeMaterial.button(symbol: "chevron.left", label: "Close chats") { [weak self] in self?.close() }
        backButton.accessibilityIdentifier = "chats.close"
        let back = NativeMaterial.wrap(backButton)
        let title = label("CHATPOP", style: .title2)
        title.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 28, weight: .bold))
        title.textAlignment = .left
        title.accessibilityTraits = .header
        let header = menuHeader
        let settingsButton = NativeMaterial.button(symbol: "gearshape", label: "Settings") { [weak self] in
            guard let self, self.presentedViewController == nil, !self.closing else { return }
            self.view.endEditing(true)
            self.creativeCard.playbackEnabled = false
            self.present(ChatPopPreferences.navigation(NativeSettingsViewController()), animated: true)
        }
        settingsButton.accessibilityIdentifier = "chats.settings"
        let settings = NativeMaterial.wrap(settingsButton)
        [title, settings, back].forEach(header.addArrangedSubview)
        settings.widthAnchor.constraint(equalToConstant: 44).isActive = true
        header.alignment = .center
        header.spacing = 8
        back.widthAnchor.constraint(equalToConstant: 44).isActive = true

        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        scroll.keyboardDismissMode = .interactive
        scroll.contentInsetAdjustmentBehavior = .never
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12
        content.addArrangedSubview(card(title: "Try ChatPop Plus or Pro", detail: "Unlock more features", subscription: true))
        creativeCard.addTarget(self, action: #selector(creationNotice), for: .touchUpInside)
        content.addArrangedSubview(creativeCard)
        let chatsTitle = label("Chats", style: .title2)
        chatsTitle.accessibilityTraits = .header
        let newChat = NativeMaterial.button(symbol: "square.and.pencil", label: "New chat") { [weak self] in self?.close(action: "newChat") }
        newChat.tintColor = blue
        newChat.widthAnchor.constraint(equalToConstant: 44).isActive = true
        newChat.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let heading = UIStackView(arrangedSubviews: [chatsTitle, newChat])
        heading.alignment = .center
        content.setCustomSpacing(22, after: content.arrangedSubviews[1])
        content.addArrangedSubview(heading)
        rows.axis = .vertical
        rows.spacing = 2
        content.addArrangedSubview(rows)

        let search = searchSurface
        var config = UIButton.Configuration.plain()
        config.title = "Search"
        config.image = UIImage(systemName: "magnifyingglass")
        config.imagePadding = 8
        config.baseForegroundColor = .secondaryLabel
        searchToggle.configuration = config
        searchToggle.addAction(UIAction { [weak self] _ in self?.setSearching(true) }, for: .touchUpInside)
        field.placeholder = "Search chats"
        field.accessibilityLabel = "Search chats"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.delegate = self
        field.addTarget(self, action: #selector(filterChats), for: .editingChanged)
        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = .secondaryLabel
        searchIcon.contentMode = .center
        searchIcon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let cancel = NativeMaterial.button(symbol: "xmark", label: "Close search") { [weak self] in self?.setSearching(false) }
        cancel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        [searchIcon, field, cancel].forEach { searchFields.addArrangedSubview($0) }
        searchFields.alignment = .center
        searchFields.spacing = 8
        searchFields.isHidden = true
        for item in [scroll, header, search] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        for item in [searchToggle, searchFields] { item.translatesAutoresizingMaskIntoConstraints = false; search.contentView.addSubview(item) }
        compactSearch = search.widthAnchor.constraint(equalToConstant: 132)
        expandedSearch = search.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            search.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            search.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            search.heightAnchor.constraint(equalToConstant: 48), compactSearch,
            searchToggle.leadingAnchor.constraint(equalTo: search.contentView.leadingAnchor),
            searchToggle.trailingAnchor.constraint(equalTo: search.contentView.trailingAnchor),
            searchToggle.topAnchor.constraint(equalTo: search.contentView.topAnchor),
            searchToggle.bottomAnchor.constraint(equalTo: search.contentView.bottomAnchor),
            searchFields.leadingAnchor.constraint(equalTo: search.contentView.leadingAnchor, constant: 14),
            searchFields.trailingAnchor.constraint(equalTo: search.contentView.trailingAnchor),
            searchFields.topAnchor.constraint(equalTo: search.contentView.topAnchor),
            searchFields.bottomAnchor.constraint(equalTo: search.contentView.bottomAnchor)
        ])
        filterChats()
    }

    private func card(title: String, detail: String, subscription: Bool) -> UIView {
        let surface = UIView()
        surface.backgroundColor = .secondarySystemBackground
        surface.layer.cornerRadius = 8
        let copy = UIStackView(arrangedSubviews: [label(title, style: .subheadline), label(detail, style: .caption1, secondary: true)])
        copy.axis = .vertical
        copy.spacing = 5
        let action = UIButton(type: .system)
        if subscription {
            var config = UIButton.Configuration.filled()
            config.title = "Try Now"
            config.baseBackgroundColor = blue
            config.baseForegroundColor = .white
            action.configuration = config
            action.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else {
            action.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            action.accessibilityLabel = "Create Images & Videos"
            action.tintColor = .secondaryLabel
        }
        action.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        action.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [copy, action])
        if !subscription {
            let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle"))
            icon.tintColor = blue
            icon.contentMode = .center
            icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
            stack.insertArrangedSubview(icon, at: 0)
            surface.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(creationNotice)))
        }
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -16)
        ])
        action.addAction(UIAction { [weak self] _ in
            if subscription {
                self?.creativeCard.playbackEnabled = false
                self?.present(ChatPopPreferences.navigation(NativePaywallViewController()), animated: true)
            }
            else { self?.notice("Image and video creation") }
        }, for: .touchUpInside)
        return surface
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        menuVisible = true
        updateCreativePlayback()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        menuVisible = false
        updateCreativePlayback()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = UIEdgeInsets(top: menuHeader.frame.maxY + 16, left: 0,
                                  bottom: max(0, view.bounds.height - searchSurface.frame.minY) + 12, right: 0)
        if scroll.contentInset != insets {
            let previousTop = scroll.contentInset.top
            let offset = scroll.contentOffset
            scroll.contentInset = insets
            scroll.verticalScrollIndicatorInsets = insets
            // Preserve the reading position through safe-area and keyboard changes.
            scroll.contentOffset = CGPoint(x: offset.x, y: menuInsetsInstalled ? offset.y + previousTop - insets.top : -insets.top)
            menuInsetsInstalled = true
        }
        updateCreativePlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCreativePlayback()
    }

    private func updateCreativePlayback() {
        let frame = creativeCard.convert(creativeCard.bounds, to: scroll)
        let visible = frame.intersection(scroll.bounds)
        creativeCard.playbackEnabled = menuVisible && !closing && presentedViewController == nil
            && !visible.isNull && visible.height >= min(80, frame.height * 0.3)
    }

    @objc private func creationNotice() {
        guard !closing, presentationComplete, presentedViewController == nil else { return }
        view.endEditing(true)
        creativeCard.playbackEnabled = false
        let studio = NativeCreativeStudioViewController()
        if #available(iOS 18.0, *), !UIAccessibility.isReduceMotionEnabled {
            studio.preferredTransition = .zoom { [weak self] _ in self?.creativeCard }
        } else if UIAccessibility.isReduceMotionEnabled {
            studio.modalTransitionStyle = .crossDissolve
        }
        present(studio, animated: true)
    }
    private func notice(_ title: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: "Not available yet", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func setSearching(_ expanded: Bool) {
        compactSearch.isActive = false
        expandedSearch.isActive = expanded
        compactSearch.isActive = !expanded
        searchToggle.isHidden = expanded
        searchFields.isHidden = !expanded
        if expanded { field.becomeFirstResponder() }
        else { field.resignFirstResponder(); field.text = ""; filterChats() }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    @objc private func historyAccountChanged() {
        historyTask?.cancel()
        chats = []; hasMore = false; historyOffset = 0
        renderRows()
        if NativeAuthSession.shared.user != nil { loadHistory(reset: true) }
    }

    @objc private func filterChats() {
        if NativeAuthSession.shared.user != nil { loadHistory(reset: true); return }
        renderRows()
    }

    private func loadHistory(reset: Bool) {
        historyTask?.cancel()
        let query = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = reset ? 0 : historyOffset
        let owner = NativeAuthSession.shared.user?.id
        historyTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                var parts = URLComponents()
                parts.queryItems = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "q", value: query)]
                let data = try await NativeAuthSession.shared.accountRequest("GET", path: "/chats?" + (parts.percentEncodedQuery ?? ""))
                try Task.checkCancellation()
                guard let self, NativeAuthSession.shared.user?.id == owner,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = json["chats"] as? [[String: Any]] else { return }
                let page = entries.compactMap { item -> NativeChatHistoryItem? in
                    guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
                    return NativeChatHistoryItem(id: id, title: title)
                }
                self.chats = reset ? page : self.chats + page.filter { next in !self.chats.contains { $0.id == next.id } }
                self.historyOffset = offset + page.count; self.hasMore = page.count == 50
                self.renderRows()
            } catch is CancellationError {} catch {
                guard let self, !Task.isCancelled else { return }
                self.notice("Could not load chats. Please try again.")
            }
        }
    }

    private func editChat(_ chat: NativeChatHistoryItem, deleting: Bool) {
        let alert = UIAlertController(title: deleting ? "Delete chat?" : "Rename chat", message: deleting ? "This removes this conversation and its associated attachments." : nil, preferredStyle: .alert)
        if !deleting { alert.addTextField { $0.text = chat.title } }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: deleting ? "Delete" : "Save", style: deleting ? .destructive : .default) { [weak self, weak alert] _ in
            let title = alert?.textFields?.first?.text ?? ""
            Task { @MainActor in
                do {
                    let body = deleting ? nil : try JSONSerialization.data(withJSONObject: ["title": title])
                    _ = try await NativeAuthSession.shared.accountRequest(deleting ? "DELETE" : "PATCH", path: "/chats/" + chat.id, body: body)
                    if deleting && self?.selected == chat.id { self?.selected = "" }
                    self?.loadHistory(reset: true)
                } catch { self?.notice("Could not update chat. Please try again.") }
            }
        })
        present(alert, animated: true)
    }

    private func renderRows() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = chats.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
        for chat in matches {
            let row = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = chat.title
            config.titleLineBreakMode = .byTruncatingTail
            config.image = UIImage(systemName: chat.id == selected ? "checkmark.bubble" : "bubble.left")
            config.imagePadding = 12
            config.baseForegroundColor = chat.id == selected ? blue : .label
            config.background.backgroundColor = chat.id == selected ? blue.withAlphaComponent(0.12) : .clear
            row.configuration = config
            row.contentHorizontalAlignment = .leading
            row.titleLabel?.lineBreakMode = .byTruncatingTail
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            row.accessibilityLabel = chat.title
            if chat.id == selected { row.accessibilityTraits.insert(.selected) }
            row.addAction(UIAction { [weak self] _ in self?.selected = chat.id; self?.renderRows() }, for: .touchUpInside)
            if NativeAuthSession.shared.user != nil {
                row.menu = UIMenu(children: [
                    UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.editChat(chat, deleting: false) },
                    UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.editChat(chat, deleting: true) }
                ])
            }
            rows.addArrangedSubview(row)
        }
        if matches.isEmpty { rows.addArrangedSubview(label("No chats found", style: .subheadline, secondary: true)) }
        if hasMore {
            let more = UIButton(type: .system)
            more.setTitle("Load more chats", for: .normal)
            more.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            more.addAction(UIAction { [weak self] _ in self?.loadHistory(reset: false) }, for: .touchUpInside)
            rows.addArrangedSubview(more)
        }
        if !query.isEmpty {
            view.layoutIfNeeded()
            let frame = rows.convert(rows.bounds, to: scroll)
            scroll.scrollRectToVisible(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(48, frame.height)), animated: false)
        }
    }

    func presentationFinished() {
        presentationComplete = true
        if let action = pendingClose {
            pendingClose = nil
            close(action: action)
        }
    }

    func close(action: String = "close") {
        guard !closing else { return }
        // React cleanup or an early Back tap can arrive while UIKit is still presenting.
        guard presentationComplete else {
            if pendingClose == nil { pendingClose = action }
            return
        }
        closing = true
        historyTask?.cancel()
        creativeCard.playbackEnabled = false
        view.endEditing(true)
        view.isUserInteractionEnabled = false
        if let child = presentedViewController {
            child.dismiss(animated: false) { [weak self] in self?.dismissPage(action: action) }
        } else {
            dismissPage(action: action)
        }
    }

    private func dismissPage(action: String) {
        dismiss(animated: true) {
            let onFinish = self.onFinish
            self.onFinish = nil
            onFinish?(action, self.selected)
        }
    }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

private final class ChatsPageTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ChatsPageAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ChatsPageAnimator(presenting: false)
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        ChatsPagePresentationController(presentedViewController: presented, presenting: presenting)
    }
}

private final class ChatsPagePresentationController: UIPresentationController {
    override var shouldRemovePresentersView: Bool { false }
    override var shouldPresentInFullscreen: Bool { true }
    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let presentedView else { return }
        let frame = frameOfPresentedViewInContainerView
        // Bounds/center preserve the animator's transform while safe areas or orientation change.
        presentedView.bounds = CGRect(origin: .zero, size: frame.size)
        presentedView.center = CGPoint(x: frame.midX, y: frame.midY)
    }
}

private final class ChatsPageAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool

    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.38
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        let viewKey: UITransitionContextViewKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key), let page = context.view(forKey: viewKey) else {
            context.completeTransition(false)
            return
        }
        if presenting {
            page.frame = context.finalFrame(for: controller)
            context.containerView.addSubview(page)
            page.layoutIfNeeded()
            page.transform = CGAffineTransform(translationX: -context.containerView.bounds.width, y: 0)
        }
        let target: CGAffineTransform = presenting ? .identity : CGAffineTransform(translationX: -context.containerView.bounds.width, y: 0)
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) {
            page.transform = target
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed { page.transform = .identity }
            // UIKit retains both pages until the horizontal motion actually completes.
            context.completeTransition(completed)
        }
    }
}
