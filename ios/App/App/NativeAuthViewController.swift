import UIKit
import AuthenticationServices

private final class AuthPreviewSession { var agreed = false }

final class NativeAuthViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    private enum Page { case entry, login, signup, forgot, legal(String) }
    private let page: Page
    private let session: AuthPreviewSession
    private let scroll = UIScrollView()
    private let email = UITextField()
    private let password = UITextField()
    private let continueButton = UIButton(type: .system)
    private let agreement = UIButton(type: .system)
    private let atmosphere = CAGradientLayer()
    private var submission: Task<Void, Never>?
    private var isSubmitting = false

    init() { page = .entry; session = AuthPreviewSession(); super.init(nibName: nil, bundle: nil) }
    private init(page: Page, session: AuthPreviewSession) { self.page = page; self.session = session; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var isForm: Bool { switch page { case .login, .signup, .forgot: return true; default: return false } }
    private var needsPassword: Bool { switch page { case .login, .signup: return true; default: return false } }
    private var heading: String {
        switch page { case .entry: return "Log in or sign up"; case .login: return "Log in"; case .signup: return "Create an account"; case .forgot: return "Reset password"; case .legal(let title): return title }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        view.tintColor = ChatPopPreferences.blue
        // Branding atmosphere only, not a simulated glass surface.
        atmosphere.colors = [UIColor(red: 0.04, green: 0.16, blue: 0.32, alpha: 1).cgColor, UIColor.black.cgColor]
        view.layer.insertSublayer(atmosphere, at: 0)
        if case .entry = page {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(closeFlow))
            navigationItem.leftBarButtonItem?.accessibilityLabel = "Back to Settings"
        }
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeFlow))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Close authentication"
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        let mark = ChatPopBrand.centeredMark(size: 48, accessible: true)
        stack.addArrangedSubview(mark)
        let title = label(heading, style: .title1)
        title.textAlignment = .center
        title.accessibilityTraits = .header
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(32, after: title)
        switch page {
        case .entry: buildEntry(stack)
        case .login, .signup, .forgot: buildForm(stack)
        case .legal:
            stack.addArrangedSubview(label("This document is not published yet. No legal agreement is being submitted in this preview.", style: .body, secondary: true))
        }
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        if isForm {
            continueButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(continueButton)
            NSLayoutConstraint.activate([
                continueButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
                continueButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                continueButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
                continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
                scroll.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -12)
            ])
        } else { scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        tap.cancelsTouchesInView = false
        scroll.addGestureRecognizer(tap)
        updateValidation()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); atmosphere.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: min(420, view.bounds.height * 0.65)) }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAgreement()
        password.isSecureTextEntry = true
        (password.rightView as? UIButton)?.setImage(UIImage(systemName: "eye"), for: .normal)
        password.rightView?.accessibilityLabel = "Show password"
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Credentials are never persisted or sent across the Capacitor bridge.
        password.text = ""
        password.isSecureTextEntry = true
        updateValidation()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true { cancelSubmission() }
    }
    private func label(_ text: String, style: UIFont.TextStyle, secondary: Bool = false) -> UILabel {
        let label = UILabel(); label.text = text; label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true; label.numberOfLines = 0
        label.textColor = secondary ? .secondaryLabel : .label
        return label
    }
    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = UIColor(white: 0.10, alpha: 1)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        button.configuration = config
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    private func buildEntry(_ stack: UIStackView) {
        let apple = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        apple.cornerRadius = 12
        apple.layer.borderColor = UIColor(white: 0.3, alpha: 1).cgColor
        apple.layer.borderWidth = 1
        apple.heightAnchor.constraint(equalToConstant: 52).isActive = true
        apple.addAction(UIAction { [weak self] _ in self?.social("Apple") }, for: .touchUpInside)
        stack.addArrangedSubview(apple)
        for (provider, asset) in [("Google", "GoogleSignIn"), ("Microsoft", "MicrosoftSignIn")] {
            let row = button("Continue with \(provider)") { [weak self] in self?.social(provider) }
            var config = row.configuration!
            let source = UIImage(named: asset)
            config.image = source.map { original in
                let size = CGSize(width: 20, height: 20 * original.size.height / max(1, original.size.width))
                return UIGraphicsImageRenderer(size: size).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }.withRenderingMode(.alwaysOriginal)
            }
            config.imagePadding = 12
            row.configuration = config
            stack.addArrangedSubview(row)
        }
        let divider = label("OR", style: .caption1, secondary: true)
        divider.textAlignment = .center
        let leftLine = UIView(); let rightLine = UIView()
        for line in [leftLine, rightLine] { line.backgroundColor = .separator; line.heightAnchor.constraint(equalToConstant: 1).isActive = true }
        let separator = UIStackView(arrangedSubviews: [leftLine, divider, rightLine]); separator.alignment = .center; separator.spacing = 14
        stack.addArrangedSubview(separator)
        // Cross-view constraints require a common ancestor before activation.
        leftLine.widthAnchor.constraint(equalTo: rightLine.widthAnchor).isActive = true
        stack.addArrangedSubview(button("Log in") { [weak self] in self?.push(.login) })
        stack.addArrangedSubview(button("Sign up") { [weak self] in self?.push(.signup) })
        agreement.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }; self.session.agreed.toggle(); self.updateAgreement()
        }, for: .touchUpInside)
        agreement.widthAnchor.constraint(equalToConstant: 44).isActive = true
        agreement.heightAnchor.constraint(equalToConstant: 44).isActive = true
        agreement.accessibilityLabel = "I agree to the Terms of Service and Privacy Policy"
        let text = UITextView()
        text.isEditable = false; text.isScrollEnabled = false; text.backgroundColor = .clear; text.delegate = self
        let copy = "I agree to the Terms of Service and Privacy Policy"
        let attributed = NSMutableAttributedString(string: copy, attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote), .foregroundColor: UIColor.secondaryLabel])
        attributed.addAttribute(.link, value: "chatpop-preview://terms", range: (copy as NSString).range(of: "Terms of Service"))
        attributed.addAttribute(.link, value: "chatpop-preview://privacy", range: (copy as NSString).range(of: "Privacy Policy"))
        text.attributedText = attributed
        text.adjustsFontForContentSizeCategory = true
        text.linkTextAttributes = [.foregroundColor: ChatPopPreferences.blue]
        let consent = UIStackView(arrangedSubviews: [agreement, text]); consent.alignment = .top; consent.spacing = 4
        stack.addArrangedSubview(consent)
    }
    private func buildForm(_ stack: UIStackView) {
        if case .signup = page { stack.addArrangedSubview(label("Set your email and password to continue.", style: .body, secondary: true)) }
        if case .forgot = page { stack.addArrangedSubview(label("Enter your email to request a password reset.", style: .body, secondary: true)) }
        email.placeholder = "Email"; email.accessibilityLabel = "Email"
        email.keyboardType = .emailAddress; email.autocapitalizationType = .none; email.autocorrectionType = .no
        email.textContentType = .username; email.returnKeyType = needsPassword ? .next : .done
        stack.addArrangedSubview(fieldSurface(email))
        if needsPassword {
            password.placeholder = "Password"; password.accessibilityLabel = "Password"; password.isSecureTextEntry = true
            if case .signup = page { password.textContentType = .newPassword } else { password.textContentType = .password }
            password.autocapitalizationType = .none; password.autocorrectionType = .no; password.returnKeyType = .done
            let eye = NativeMaterial.button(symbol: "eye", label: "Show password") { [weak self] in
                guard let self = self else { return }
                self.password.isSecureTextEntry.toggle()
                self.password.rightView?.accessibilityLabel = self.password.isSecureTextEntry ? "Show password" : "Hide password"
                (self.password.rightView as? UIButton)?.setImage(UIImage(systemName: self.password.isSecureTextEntry ? "eye" : "eye.slash"), for: .normal)
            }
            eye.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
            password.rightView = eye; password.rightViewMode = .always
            stack.addArrangedSubview(fieldSurface(password))
            if case .signup = page { stack.addArrangedSubview(label("Use 12 to 128 characters.", style: .footnote, secondary: true)) }
        }
        if case .login = page { stack.addArrangedSubview(button("Forgot password") { [weak self] in self?.push(.forgot) }) }
        continueButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
    }
    private func fieldSurface(_ field: UITextField) -> UIView {
        field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true; field.delegate = self
        field.addTarget(self, action: #selector(updateValidation), for: .editingChanged)
        let surface = UIView(); surface.backgroundColor = UIColor(white: 0.10, alpha: 1); surface.layer.cornerRadius = 12
        field.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: surface.topAnchor, constant: 8),
            field.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -8),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return surface
    }
    @objc private func updateValidation() {
        let value = (email.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let emailValid = value.utf16.count <= 254 && value.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
        let minimum = { if case .signup = page { return 12 }; return 1 }()
        let passwordLength = (password.text ?? "").utf16.count
        continueButton.isEnabled = !isSubmitting && emailValid && (!needsPassword || (minimum...128).contains(passwordLength))
        var config = UIButton.Configuration.filled(); config.title = "Continue"; config.cornerStyle = .large
        config.showsActivityIndicator = isSubmitting
        config.baseBackgroundColor = continueButton.isEnabled ? ChatPopPreferences.blue : UIColor(white: 0.13, alpha: 1)
        config.baseForegroundColor = continueButton.isEnabled ? .white : .secondaryLabel
        continueButton.configuration = config
    }
    private func updateAgreement() {
        agreement.setImage(UIImage(systemName: session.agreed ? "checkmark.square.fill" : "square"), for: .normal)
        agreement.accessibilityValue = session.agreed ? "Checked" : "Unchecked"
        agreement.isSelected = session.agreed
    }
    private func push(_ page: Page) {
        guard !isSubmitting else { return }
        view.endEditing(true)
        navigationController?.pushViewController(NativeAuthViewController(page: page, session: session), animated: true)
    }
    private func social(_ provider: String) {
        guard session.agreed else { notice("Please review the Terms of Service and Privacy Policy and check the agreement box first."); return }
        notice("\(provider) sign-in is not connected. No account was created or signed in.")
    }
    private func submit() {
        guard continueButton.isEnabled else { return }
        if case .forgot = page { notice("Password reset is not connected. No email was sent."); return }
        guard session.agreed else { password.text = ""; updateValidation(); notice("Please go back and check the agreement box before continuing."); return }
        let submittedEmail = (email.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let submittedPassword = password.text ?? ""
        password.text = ""
        view.endEditing(true)
        isSubmitting = true
        email.isEnabled = false
        password.isEnabled = false
        updateValidation()
        submission = Task { [weak self] in
            guard let self = self else { return }
            defer {
                self.submission = nil
                self.isSubmitting = false
                self.email.isEnabled = true
                self.password.isEnabled = true
                self.password.text = ""
                self.updateValidation()
            }
            do {
                if case .signup = self.page {
                    try await NativeAuthSession.shared.register(email: submittedEmail, password: submittedPassword)
                } else {
                    try await NativeAuthSession.shared.signIn(email: submittedEmail, password: submittedPassword)
                }
                try Task.checkCancellation()
                self.submission = nil
                self.isSubmitting = false
                self.navigationController?.dismiss(animated: true)
            } catch {
                guard !Task.isCancelled, self.view.window != nil else { return }
                self.notice(NativeAuthSession.message(for: error))
            }
        }
    }
    private func cancelSubmission() {
        guard submission != nil else { return }
        submission?.cancel()
        NativeAuthSession.shared.cancelPendingAuthentication()
    }
    private func notice(_ message: String) {
        let alert = UIAlertController(title: "ChatPop", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
    @objc private func dismissKeyboard(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: scroll)
        if let hit = scroll.hitTest(point, with: nil), hit is UIControl || hit.isDescendant(of: email) || hit.isDescendant(of: password) { return }
        view.endEditing(true)
    }
    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak textField] in
            guard let self = self, let field = textField, field.isFirstResponder else { return }
            self.view.layoutIfNeeded(); self.scroll.scrollRectToVisible(field.convert(field.bounds, to: self.scroll).insetBy(dx: 0, dy: -16), animated: true)
        }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === email && needsPassword { password.becomeFirstResponder() } else { textField.resignFirstResponder(); submit() }; return true
    }
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        push(.legal(URL.host == "terms" ? "Terms of Service" : "Privacy Policy")); return false
    }
    @objc private func closeFlow() { cancelSubmission(); view.endEditing(true); password.text = ""; navigationController?.dismiss(animated: true) }
    override func accessibilityPerformEscape() -> Bool {
        if navigationController?.viewControllers.count ?? 0 > 1 { navigationController?.popViewController(animated: true) } else { closeFlow() }; return true
    }
}
