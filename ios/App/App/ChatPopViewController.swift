import UIKit
import Capacitor

final class ChatPopViewController: CAPBridgeViewController {
    private let nativePlugin = NativeChatControlsPlugin()
    private(set) var chatControls: NativeChatControlsView!
    private var launchIntro: ChatPopIntroView?

    override var prefersStatusBarHidden: Bool { launchIntro != nil || super.prefersStatusBarHidden }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        launchIntro?.start()
    }

    override func capacitorDidLoad() {
        nativePlugin.host = self
        bridge?.registerPluginInstance(nativePlugin)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let webView = webView else { return }

        // Preserve Capacitor's WKWebView and bridge; add a UIKit sibling layer.
        let container = UIView()
        container.backgroundColor = .systemBackground
        overrideUserInterfaceStyle = ChatPopPreferences.style
        view = container
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        chatControls = NativeChatControlsView()
        chatControls.translatesAutoresizingMaskIntoConstraints = false
        chatControls.isHidden = true
        container.addSubview(chatControls)
        NSLayoutConstraint.activate([
            chatControls.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            chatControls.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chatControls.topAnchor.constraint(equalTo: container.topAnchor),
            chatControls.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        chatControls.onEvent = { [weak self] event in
            self?.nativePlugin.notifyListeners("control", data: event)
        }
        chatControls.onModels = { [weak self] in self?.presentModels() }
        chatControls.onAttachments = { [weak self] source in self?.presentAttachments(source) }
        chatControls.onMicrophone = { [weak self] in self?.presentDictation() }
        chatControls.onVoice = { [weak self] in self?.presentVoice() }
        statusBarStyle = ChatPopPreferences.theme == "Dark" ? .lightContent : .default
        setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppearance), name: ChatPopPreferences.changed, object: nil)
        if ChatPopIntroView.claimLaunch() {
            let intro = ChatPopIntroView(frame: container.bounds)
            intro.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            intro.onFinish = { [weak self] in
                self?.launchIntro = nil
                self?.setNeedsStatusBarAppearanceUpdate()
            }
            launchIntro = intro
            container.addSubview(intro)
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    @objc private func updateAppearance() {
        var current: UIViewController? = self
        while let controller = current {
            controller.overrideUserInterfaceStyle = ChatPopPreferences.style
            current = controller.presentedViewController
        }
        statusBarStyle = ChatPopPreferences.theme == "Dark" ? .lightContent : .default
        setNeedsStatusBarAppearanceUpdate()
        nativePlugin.notifyListeners("control", data: ["type": "appearance", "theme": ChatPopPreferences.theme.lowercased()])
    }

    private func presentModels() {
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        let picker = NativeModelViewController(providers: chatControls.providers, selected: chatControls.model,
                                               anchor: chatControls.modelSelectorAnchor)
        picker.onSelect = { [weak self] name in
            self?.chatControls.selectModel(name)
        }
        present(picker, animated: false)
    }

    private func presentVoice() {
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        present(NativeVoiceViewController(), animated: true)
    }

    private func presentDictation() {
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        let chatID = chatControls.chatID
        let dictation = NativeDictationViewController()
        dictation.onInsert = { [weak self] transcript in
            self?.chatControls.insertDictation(transcript, for: chatID)
        }
        present(dictation, animated: true)
    }

    private func presentAttachments(_ source: UIView) {
        if let menu = presentedViewController as? NativeAttachmentViewController {
            menu.closeMenu()
            return
        }
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        view.layoutIfNeeded()
        let menu = NativeAttachmentViewController(anchor: source)
        menu.onSelect = { [weak self] action in self?.showUnavailable(action.title) }
        present(menu, animated: false)
    }

    private func showUnavailable(_ name: String) {
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        let alert = UIAlertController(title: "\(name) not connected", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default))
        present(alert, animated: true)
    }
}
