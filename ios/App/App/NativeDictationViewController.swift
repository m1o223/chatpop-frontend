import UIKit

final class NativeDictationViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    var onInsert: ((String) -> Void)?
    private let session: NativeDictationSession
    private let transcriptView = UITextView()
    private let statusLabel = UILabel()
    private let waveform = DictationWaveformView()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let recoveryButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private var transcript = ""
    private var started = false
    private var closing = false
    private var openSettings = false

    init(locale: Locale = .current) {
        session = NativeDictationSession(locale: locale)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        overrideUserInterfaceStyle = .dark
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = UIAccessibility.isVoiceOverRunning || UITraitCollection.current.preferredContentSizeCategory.isAccessibilityCategory ? .large : .medium
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.045, alpha: 1)
        view.accessibilityIdentifier = "dictation.sheet"
        view.accessibilityViewIsModal = true
        presentationController?.delegate = self

        let title = UILabel()
        title.text = "Dictation"
        title.textColor = .white
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        let close = NativeMaterial.button(symbol: "xmark", label: "Cancel dictation") { [weak self] in self?.cancel() }
        close.accessibilityIdentifier = "dictation.close"
        let closeSurface = NativeMaterial.wrap(close)
        let header = UIStackView(arrangedSubviews: [title, UIView(), closeSurface])
        header.alignment = .center
        header.spacing = 12
        closeSurface.widthAnchor.constraint(equalToConstant: 44).isActive = true

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "dictation.status"
        activity.hidesWhenStopped = true
        let status = UIStackView(arrangedSubviews: [activity, statusLabel])
        status.spacing = 8
        status.alignment = .center

        transcriptView.isEditable = false
        transcriptView.isSelectable = true
        transcriptView.backgroundColor = .clear
        transcriptView.textColor = .white
        transcriptView.tintColor = ChatPopPreferences.blue
        transcriptView.font = .preferredFont(forTextStyle: .title3)
        transcriptView.adjustsFontForContentSizeCategory = true
        transcriptView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        transcriptView.textContainer.lineFragmentPadding = 0
        transcriptView.textAlignment = .natural
        transcriptView.accessibilityLabel = "Recognized speech"
        transcriptView.accessibilityIdentifier = "dictation.transcript"
        transcriptView.setContentHuggingPriority(.defaultLow, for: .vertical)

        recoveryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        recoveryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        recoveryButton.tintColor = ChatPopPreferences.blue
        recoveryButton.accessibilityIdentifier = "dictation.recovery"
        recoveryButton.addAction(UIAction { [weak self] _ in self?.recover() }, for: .touchUpInside)
        recoveryButton.isHidden = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Insert"
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        insertButton.configuration = configuration
        insertButton.configurationUpdateHandler = { button in
            var configuration = button.configuration
            configuration?.baseBackgroundColor = button.isEnabled ? ChatPopPreferences.blue : UIColor(white: 0.14, alpha: 1)
            configuration?.baseForegroundColor = button.isEnabled ? .white : .secondaryLabel
            button.configuration = configuration
        }
        insertButton.isEnabled = false
        insertButton.accessibilityIdentifier = "dictation.insert"
        insertButton.addAction(UIAction { [weak self] _ in self?.insert() }, for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [header, status, transcriptView, waveform, recoveryButton, insertButton])
        content.axis = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let transcriptHeight = transcriptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        transcriptHeight.priority = .defaultHigh
        let waveformHeight = waveform.heightAnchor.constraint(equalToConstant: 64)
        waveformHeight.priority = .defaultHigh
        let recoveryHeight = recoveryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        recoveryHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            transcriptHeight, waveformHeight, recoveryHeight,
            insertButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
        session.onChange = { [weak self] snapshot in self?.render(snapshot) }
        session.onLevel = { [weak self] level in self?.waveform.append(level) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started, !closing else { return }
        started = true
        session.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.stop()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        closing = true
        session.stop()
        transcript = ""
        onInsert = nil
    }

    override func accessibilityPerformEscape() -> Bool {
        cancel()
        return true
    }

    private func render(_ snapshot: NativeDictationSession.Snapshot) {
        guard !closing else { return }
        transcript = snapshot.transcript
        if transcriptView.text != transcript {
            let followingEnd = transcriptView.contentOffset.y + transcriptView.bounds.height >= transcriptView.contentSize.height - 36
            transcriptView.text = transcript
            if followingEnd, !transcript.isEmpty {
                transcriptView.scrollRangeToVisible(NSRange(location: (transcript as NSString).length, length: 0))
            }
        }
        insertButton.isEnabled = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        recoveryButton.isHidden = true
        openSettings = false
        activity.stopAnimating()
        let previousStatus = statusLabel.text
        switch snapshot.state {
        case .requestingPermission:
            statusLabel.text = "Requesting permission..."
            activity.startAnimating()
            waveform.reset()
        case .listening:
            statusLabel.text = "Listening..."
        case .recognizing:
            statusLabel.text = "Recognizing..."
        case .transcriptAvailable:
            statusLabel.text = "Ready to insert"
            waveform.reset()
        case .noSpeech:
            statusLabel.text = "No speech detected. Please try again."
            showRecovery(settings: false)
        case .permissionDenied(let message):
            statusLabel.text = message
            showRecovery(settings: true)
        case .unavailable(let message):
            statusLabel.text = message
            showRecovery(settings: false)
        }
        if previousStatus != statusLabel.text, UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
        }
    }

    private func showRecovery(settings: Bool) {
        waveform.reset()
        openSettings = settings
        recoveryButton.setTitle(settings ? "Open Settings" : "Try Again", for: .normal)
        recoveryButton.isHidden = false
    }

    private func recover() {
        guard !closing else { return }
        if openSettings, let url = URL(string: UIApplication.openSettingsURLString) {
            session.stop()
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                guard opened, let self else { return }
                self.openSettings = false
                self.recoveryButton.setTitle("Try Again", for: .normal)
            }
        } else {
            session.start()
        }
    }

    private func insert() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closing, !text.isEmpty else { return }
        closing = true
        insertButton.isEnabled = false
        session.stop()
        let onInsert = self.onInsert
        self.onInsert = nil
        dismiss(animated: true) { onInsert?(text) }
    }

    private func cancel() {
        guard !closing else { return }
        closing = true
        session.stop()
        transcript = ""
        onInsert = nil
        dismiss(animated: true)
    }
}

private final class DictationWaveformView: UIView {
    private var levels = [CGFloat](repeating: 0, count: 40)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = false
        accessibilityIdentifier = "dictation.waveform"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func append(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0, min(1, level))))
        setNeedsDisplay()
    }

    func reset() {
        levels = levels.map { _ in 0 }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let slot = bounds.width / CGFloat(levels.count)
        let width = max(1, slot * 0.48)
        for (index, level) in levels.enumerated() {
            let height = min(bounds.height, 3 + max(0, bounds.height - 3) * level)
            let bar = CGRect(x: CGFloat(index) * slot + (slot - width) / 2, y: bounds.midY - height / 2, width: width, height: height)
            ChatPopPreferences.blue.withAlphaComponent(0.35 + level * 0.65).setFill()
            UIBezierPath(roundedRect: bar, cornerRadius: width / 2).fill()
        }
    }
}
