import UIKit

struct NativeProvider {
    let name: String
    let description: String
}

enum NativeMaterial {
    static let accent = UIColor(red: 165 / 255, green: 223 / 255, blue: 1, alpha: 1)

    static var kind: String {
        if #available(iOS 26.0, *) { return "liquidGlass" }
        return "systemMaterial"
    }

    static func effect(interactive: Bool = false, prominent: Bool = false) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = interactive
            if prominent { glass.tintColor = accent }
            return glass
        } else {
            // Apple's native material on older supported iOS versions, not Liquid Glass.
            return UIBlurEffect(style: .systemThinMaterial)
        }
    }

    static func view(radius: CGFloat, interactive: Bool = false, prominent: Bool = false) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect(interactive: interactive, prominent: prominent))
        view.layer.cornerRadius = radius
        view.clipsToBounds = true
        return view
    }

    static func button(symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium), forImageIn: .normal)
        button.tintColor = .label
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func wrap(_ button: UIButton, prominent: Bool = false) -> UIVisualEffectView {
        let surface = view(radius: 22, interactive: true, prominent: prominent)
        button.translatesAutoresizingMaskIntoConstraints = false
        surface.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: surface.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
            surface.heightAnchor.constraint(equalToConstant: 44)
        ])
        return surface
    }
}

final class NativeChatControlsView: UIView, UITextViewDelegate {
    var onEvent: (([String: Any]) -> Void)?
    var onModels: (() -> Void)?
    var onAttachments: ((UIView) -> Void)?
    var onMicrophone: (() -> Void)?
    var onVoice: (() -> Void)?
    var providers: [NativeProvider] = []
    private(set) var model = "Auto"
    private(set) var chatID = ""
    private let header = UIStackView()
    private let composer = NativeMaterial.view(radius: 28)
    private let textView = UITextView()
    private let placeholder = UILabel()
    private var textHeight: NSLayoutConstraint!
    private var modelButton: UIButton!
    var modelSelectorAnchor: UIView { modelButton }
    private var sendButton: UIButton!
    private var sendSurface: UIVisualEffectView!
    private var attachmentButton: UIButton!
    private var hasSendableText: Bool?
    private var lastLayout: [CGFloat] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        overrideUserInterfaceStyle = .unspecified
        setupHeader()
        setupComposer()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupHeader() {
        let menu = NativeMaterial.button(symbol: "line.3.horizontal", label: "Open menu") { [weak self] in
            self?.endEditing(true)
            self?.onEvent?(["type": "menu"])
        }
        menu.accessibilityIdentifier = "chat.menu"
        let newChat = NativeMaterial.button(symbol: "square.and.pencil", label: "New chat") { [weak self] in
            self?.endEditing(true)
            self?.onEvent?(["type": "newChat"])
        }
        modelButton = UIButton(type: .system)
        modelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        modelButton.tintColor = .label
        modelButton.addAction(UIAction { [weak self] _ in self?.onModels?() }, for: .touchUpInside)
        let left = NativeMaterial.wrap(menu)
        let center = NativeMaterial.wrap(modelButton)
        let right = NativeMaterial.wrap(newChat)
        let spacer1 = UIView()
        let spacer2 = UIView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        [left, spacer1, center, spacer2, right].forEach { header.addArrangedSubview($0) }
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        NSLayoutConstraint.activate([
            left.widthAnchor.constraint(equalToConstant: 44),
            right.widthAnchor.constraint(equalToConstant: 44),
            spacer1.widthAnchor.constraint(equalTo: spacer2.widthAnchor),
            center.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            center.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            header.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            header.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(composer)
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = NativeMaterial.accent
        textView.accessibilityLabel = "Message ChatPop"
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        textView.delegate = self
        placeholder.text = "Message ChatPop..."
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .secondaryLabel
        placeholder.isAccessibilityElement = false
        placeholder.isUserInteractionEnabled = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 9),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4)
        ])

        let plus = NativeMaterial.button(symbol: "plus", label: "Add attachment") { [weak self] in
            guard let self = self else { return }
            self.onAttachments?(self.attachmentButton)
        }
        attachmentButton = plus
        plus.accessibilityIdentifier = "chat.composer.attachments"
        let mic = NativeMaterial.button(symbol: "mic", label: "Dictate message") { [weak self] in self?.onMicrophone?() }
        mic.accessibilityIdentifier = "chat.composer.dictation"
        sendButton = NativeMaterial.button(symbol: "waveform", label: "Open voice") { [weak self] in self?.send() }
        sendButton.accessibilityIdentifier = "chat.composer.primary"
        let plusSurface = NativeMaterial.wrap(plus)
        let micSurface = NativeMaterial.wrap(mic)
        sendSurface = NativeMaterial.wrap(sendButton)
        let actions = UIStackView(arrangedSubviews: [plusSurface, UIView(), micSurface, sendSurface!])
        actions.axis = .horizontal
        actions.spacing = 8
        for surface in [plusSurface, micSurface, sendSurface!] {
            surface.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        let stack = UIStackView(arrangedSubviews: [textView, actions])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        composer.contentView.addSubview(stack)
        textHeight = textView.heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            textHeight,
            stack.leadingAnchor.constraint(equalTo: composer.contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: composer.contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: composer.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: composer.contentView.bottomAnchor, constant: -8),
            composer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            composer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            composer.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -8)
        ])
    }

    func apply(chatID: String, draft: String, model: String, hidden: Bool, reset: Bool = false) {
        // Native typing stays authoritative within a chat; JS echoes must not move the caret.
        if reset || self.chatID != chatID {
            textView.text = draft
            self.chatID = chatID
        }
        self.model = model
        updateModelTitle()
        if hidden { endEditing(true) }
        isHidden = hidden
        updateInput()
        setNeedsLayout()
    }

    func selectModel(_ name: String) {
        model = name
        updateModelTitle()
        onEvent?(["type": "model", "model": name])
    }

    private func updateModelTitle() {
        var configuration = UIButton.Configuration.plain()
        configuration.title = model
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration.baseForegroundColor = .label
        modelButton.configuration = configuration
        modelButton.titleLabel?.lineBreakMode = .byTruncatingTail
        modelButton.accessibilityLabel = "Select AI model, current: \(model)"
    }

    func textViewDidChange(_ textView: UITextView) {
        updateInput()
        onEvent?(["type": "draft", "chatId": chatID, "text": textView.text ?? ""])
    }

    func insertDictation(_ transcript: String, for chatID: String) {
        guard self.chatID == chatID, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        textView.text = DictationText.appending(transcript, to: textView.text ?? "")
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        textViewDidChange(textView)
        textView.becomeFirstResponder()
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    private func updateInput() {
        placeholder.isHidden = !textView.text.isEmpty
        let canSend = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.tintColor = canSend ? .black : NativeMaterial.accent
        if hasSendableText != canSend {
            hasSendableText = canSend
            sendButton.setImage(UIImage(systemName: canSend ? "arrow.up" : "waveform"), for: .normal)
            sendButton.accessibilityLabel = canSend ? "Send message" : "Open voice"
            sendSurface.effect = NativeMaterial.effect(interactive: true, prominent: canSend)
            if #available(iOS 26.0, *) {
                sendButton.backgroundColor = .clear
            } else {
                sendButton.backgroundColor = canSend ? NativeMaterial.accent : .clear
            }
        }
        let fitting = textView.sizeThatFits(CGSize(width: max(1, textView.bounds.width), height: .greatestFiniteMagnitude)).height
        let contentTop = header.isHidden ? safeAreaInsets.top : header.frame.maxY + 8
        let maximum = min(CGFloat(144), max(32, keyboardLayoutGuide.layoutFrame.minY - contentTop - 88))
        let height = min(maximum, max(32, fitting))
        textView.isScrollEnabled = fitting > maximum
        if abs(textHeight.constant - height) > 0.5 { textHeight.constant = height }
    }

    private func send() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            endEditing(true)
            onVoice?()
            return
        }
        textView.text = ""
        updateInput()
        onEvent?(["type": "send", "chatId": chatID, "text": text, "messageId": UUID().uuidString])
        textView.becomeFirstResponder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Make room for the composer with a tall keyboard in compact landscape.
        header.isHidden = bounds.height > 0 && keyboardLayoutGuide.layoutFrame.minY - safeAreaInsets.top < 180
        updateInput()
        reportLayout()
    }

    func reportLayout(force: Bool = false) {
        let top = header.isHidden ? safeAreaInsets.top : header.frame.maxY + 8
        let bottom = max(0, bounds.height - composer.frame.minY)
        let metrics = [top, bottom]
        guard (force || metrics != lastLayout), bounds.height > 0 else { return }
        lastLayout = metrics
        onEvent?(["type": "layout", "top": top, "bottom": bottom])
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // Empty space belongs to the React conversation, never to the overlay.
        if hit === self || (hit != nil && hit!.isDescendant(of: header) && !(hit is UIControl)) { return nil }
        return hit
    }
}
