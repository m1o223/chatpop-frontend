import Foundation
import Security

struct NativeAuthUser: Decodable, Equatable {
    let id: String
    let email: String
    let displayName: String?
    let accountStatus: String

    private enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case accountStatus = "account_status"
    }
}

enum NativeAuthError: LocalizedError {
    case invalidCredentials, expiredSession, duplicateEmail, invalidInput, rateLimited
    case unavailable, offline, backendUnreachable, addressUnreachable, timeout, transportSecurity, networkSecurity, configuration, secureStorage
    case busy, invalidResponse, registeredButNotSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "The email or password is incorrect. Please try again."
        case .expiredSession: return "Your session has expired. Please sign in again."
        case .duplicateEmail: return "An account with this email already exists. Please log in instead."
        case .invalidInput: return "Check your email and password. New passwords must contain 12 to 128 characters."
        case .rateLimited: return "Too many attempts. Please wait a few minutes before trying again."
        case .unavailable: return "ChatPop is temporarily unavailable. Please try again later."
        case .offline:
            #if DEBUG
            return "Your network connection is unavailable or was interrupted. Check your Wi-Fi or mobile connection and try again."
            #else
            return "Your network connection is unavailable or was interrupted. Check your Wi-Fi or mobile connection and try again."
            #endif
        case .backendUnreachable:
            #if DEBUG
            return "Cannot connect to the ChatPop server. Please try again shortly."
            #else
            return "Cannot connect to the ChatPop server. Please try again shortly."
            #endif
        case .addressUnreachable:
            #if DEBUG
            return "The ChatPop server address could not be found. Check your connection and try again."
            #else
            return "The ChatPop server address could not be found. Check your connection and try again."
            #endif
        case .timeout:
            #if DEBUG
            return "ChatPop did not respond in time. Your session is saved. Check your connection and try again shortly."
            #else
            return "ChatPop did not respond in time. Check your connection and try again shortly."
            #endif
        case .transportSecurity:
            #if DEBUG
            return "iOS blocked the connection because of the app's transport security configuration. Check the API address and use the configured development build for local testing."
            #else
            return "iOS blocked an insecure connection to ChatPop. Please check for an app update."
            #endif
        case .networkSecurity: return "A secure connection could not be established. Check the app's API configuration."
        case .configuration: return "The ChatPop API address is not configured correctly."
        case .secureStorage: return "Your session could not be saved securely. Unlock your device and try again."
        case .busy: return "Please wait for the current account request to finish."
        case .invalidResponse: return "ChatPop returned an unexpected response. Please try again later."
        case .registeredButNotSignedIn: return "Your account was created, but sign-in could not finish. Please log in with your new account."
        }
    }
}

protocol NativeAuthCredentialStore {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

private struct AuthKeychainStore: NativeAuthCredentialStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ChatPop") + ".authentication",
         kSecAttrAccount as String: "backend-session",
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> Data? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw NativeAuthError.secureStorage }
        return data
    }

    func write(_ data: Data) throws {
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if result == errSecItemNotFound {
            let attributes = query.merging(values) { _, value in value }
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw NativeAuthError.secureStorage }
        } else if result != errSecSuccess { throw NativeAuthError.secureStorage }
    }

    func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw NativeAuthError.secureStorage }
    }
}

private final class AuthRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class AuthNetwork {
    private let redirectGuard = AuthRedirectGuard()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        // Allow the first Local Network permission prompt within the bounded resource timeout.
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NativeAuthError.invalidResponse }
        return (data, response)
    }
}

@MainActor
final class NativeAuthSession {
    static let shared = NativeAuthSession()
    nonisolated static let changed = Notification.Name("ChatPopNativeAuthSessionChanged")
    private(set) var user: NativeAuthUser?
    enum State: String { case restoring, signedOut, signedIn, offline, expired }
    private(set) var state: State = .restoring {
        didSet { if oldValue != state { NotificationCenter.default.post(name: Self.changed, object: self) } }
    }

    static func message(for error: Error) -> String {
        (error as? NativeAuthError)?.errorDescription ?? "Unable to connect to ChatPop. Please try again."
    }

    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let apiOrigin: String
    }
    private struct Tokens: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token"
            case expiresIn = "expires_in", tokenType = "token_type"
        }
    }
    private struct UserEnvelope: Decodable { let user: NativeAuthUser }
    private struct PasswordBody: Encodable { let email: String; let password: String }
    private struct RefreshBody: Encodable { let refresh_token: String }
    private struct DeleteBody: Encodable { let password: String; let confirmation = "DELETE" }
    private struct HTTPFailure: Error { let status: Int }
    private enum OperationKind { case authentication, sessionChange }
    private var operation: (id: UUID, kind: OperationKind)?
    private var revision = 0
    private var credentials: Credentials?
    private var restoreFlight: (id: UUID, task: Task<Void, Error>)?
    private var refreshFlight: (id: UUID, task: Task<Credentials, Error>)?
    private let baseURL: () throws -> URL
    private let store: NativeAuthCredentialStore
    private let transport: Transport

    convenience init() {
        self.init(baseURL: { try NativeAPIConfiguration.baseURL() }, store: AuthKeychainStore())
    }

    convenience init(baseURL: @escaping () throws -> URL, store: NativeAuthCredentialStore) {
        let network = AuthNetwork()
        self.init(baseURL: baseURL, store: store, transport: network.send)
    }

    // Injection keeps protocol/security tests independent of the device's real Keychain.
    init(baseURL: @escaping () throws -> URL, store: NativeAuthCredentialStore, transport: @escaping Transport) {
        self.baseURL = baseURL
        self.store = store
        self.transport = transport
    }

    func signIn(email: String, password: String) async throws {
        try await authenticate(email: email, password: password, registering: false)
    }

    func register(email: String, password: String) async throws {
        try await authenticate(email: email, password: password, registering: true)
    }

    func cancelPendingAuthentication() {
        guard operation?.kind == .authentication else { return }
        revision += 1
        operation = nil
    }

    func restore() async throws {
        if let flight = restoreFlight { return try await flight.task.value }
        guard operation == nil else { return }
        let id = UUID(), version = revision
        let task = Task { @MainActor in try await self.restoreSession(version: version) }
        restoreFlight = (id, task)
        defer { if restoreFlight?.id == id { restoreFlight = nil } }
        try await task.value
    }

    // Only relative, allowlisted account routes are exposed to the WebView; tokens remain native.
    func accountRequest(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        await finishRestore()
        guard operation == nil else { throw NativeAuthError.busy }
        let version = revision
        do {
            let url = try configuredURL()
            try loadCredentials(for: url)
            let data = try await authorized(method, path, body: body, base: url, version: version)
            try check(version)
            return data
        } catch {
            if let failure = error as? HTTPFailure, failure.status == 401 {
                try clearSession(); state = .expired
            }
            throw friendly(error)
        }
    }

    func updateName(_ name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["display_name": name])
        let data = try await accountRequest("PATCH", path: "/me", body: body)
        setUser(try decodeUser(data))
    }

    func signOut() async throws {
        await finishRestore()
        let id = try begin(.sessionChange)
        let version = revision
        defer { finish(id) }
        do {
            let url = try configuredURL()
            try loadCredentials(for: url)
            if credentials != nil {
                do { _ = try await authorized("POST", "/auth/logout", base: url, version: version) }
                catch let failure as HTTPFailure where failure.status == 401 { /* Already revoked. */ }
            }
            try check(version)
            try clearSession()
        } catch { throw friendly(error) }
    }

    func deleteAccount(password: String) async throws {
        await finishRestore()
        let id = try begin(.sessionChange)
        let version = revision
        defer { finish(id) }
        do {
            guard (1...128).contains(password.utf16.count) else { throw NativeAuthError.invalidInput }
            let url = try configuredURL()
            try loadCredentials(for: url)
            let body = try JSONEncoder().encode(DeleteBody(password: password))
            _ = try await authorized("DELETE", "/me", body: body, base: url, version: version)
            try check(version)
            try clearSession()
        } catch { throw friendly(error, credentialsError: true) }
    }

    private func authenticate(email: String, password: String, registering: Bool) async throws {
        await finishRestore()
        let id = try begin(.authentication)
        let version = revision
        defer { finish(id) }
        var issued: Credentials?
        var registered = false
        var requestBase: URL?
        do {
            let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard email.utf16.count <= 254,
                  email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil,
                  ((registering ? 12 : 1)...128).contains(password.utf16.count) else { throw NativeAuthError.invalidInput }
            let url = try configuredURL()
            requestBase = url
            let body = try JSONEncoder().encode(PasswordBody(email: email, password: password))
            if registering {
                let data = try await request("POST", "/auth/register", body: body, base: url)
                _ = try JSONDecoder().decode(UserEnvelope.self, from: data)
                registered = true
                try check(version)
            }
            let data = try await request("POST", "/auth/login", body: body, base: url)
            let next = try makeCredentials(data, base: url)
            issued = next
            try check(version)
            let profile = try await request("GET", "/me", access: next.accessToken, base: url)
            let account = try decodeUser(profile)
            try check(version)
            try store.write(JSONEncoder().encode(next))
            credentials = next
            setUser(account)
        } catch {
            if let issued, let url = requestBase {
                // A dismissed flow must not leave a newly issued session active unnecessarily.
                Task { _ = try? await self.request("POST", "/auth/logout", access: issued.accessToken, base: url) }
            }
            if registered, !(error is CancellationError) { throw NativeAuthError.registeredButNotSignedIn }
            throw friendly(error, credentialsError: true)
        }
    }

    private func restoreSession(version: Int) async throws {
        do {
            let url = try configuredURL()
            try check(version)
            try loadCredentials(for: url)
            guard credentials != nil else { setUser(nil); state = .signedOut; return }
            let data = try await authorized("GET", "/me", base: url, version: version)
            let account = try decodeUser(data)
            try check(version)
            setUser(account)
        } catch {
            if revision == version {
                if let failure = error as? HTTPFailure, failure.status == 401 {
                    try clearSession(); state = .expired
                } else { state = .offline }
            }
            throw friendly(error)
        }
    }

    private func authorized(_ method: String, _ path: String, body: Data? = nil, base: URL, version: Int) async throws -> Data {
        try check(version)
        guard var current = credentials else { throw NativeAuthError.expiredSession }
        var refreshed = false
        if current.expiresAt.timeIntervalSinceNow <= 15 {
            current = try await refresh(base: base, version: version)
            refreshed = true
        }
        do { return try await request(method, path, body: body, access: current.accessToken, base: base) }
        catch let failure as HTTPFailure where failure.status == 401 && !refreshed {
            current = try await refresh(base: base, version: version)
            return try await request(method, path, body: body, access: current.accessToken, base: base)
        }
    }

    private func refresh(base: URL, version: Int) async throws -> Credentials {
        if let flight = refreshFlight { return try await flight.task.value }
        guard let current = credentials else { throw NativeAuthError.expiredSession }
        let id = UUID()
        let task = Task { @MainActor () throws -> Credentials in
            do {
                let body = try JSONEncoder().encode(RefreshBody(refresh_token: current.refreshToken))
                let data = try await self.request("POST", "/auth/refresh", body: body, base: base)
                let next = try self.makeCredentials(data, base: base)
                try self.check(version)
                try self.store.write(JSONEncoder().encode(next))
                self.credentials = next
                return next
            } catch {
                // Transport failures do not prove revocation. Retain Keychain until the server rejects it.
                if self.revision == version, let failure = error as? HTTPFailure, failure.status == 401 {
                    try self.clearSession(); self.state = .expired
                }
                throw self.friendly(error)
            }
        }
        refreshFlight = (id, task)
        defer { if refreshFlight?.id == id { refreshFlight = nil } }
        return try await task.value
    }

    private func request(_ method: String, _ path: String, body: Data? = nil, access: String? = nil, base: URL) async throws -> Data {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host, url.port == base.port else { throw NativeAuthError.configuration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let access { request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
            #if DEBUG
            NSLog("[ChatPop Auth] %@ %@ HTTP %ld", method, path, response.statusCode)
            #endif
        } catch let error as URLError {
            #if DEBUG
            // Log only fixed route names and numeric codes, never bodies, tokens, or raw errors.
            NSLog("[ChatPop Auth] %@ %@ URL error %ld", method, path, error.errorCode)
            #endif
            throw error
        }
        guard response.url == url else { throw NativeAuthError.networkSecurity }
        guard (200...299).contains(response.statusCode) else { throw HTTPFailure(status: response.statusCode) }
        guard data.count <= 4_194_304 else { throw NativeAuthError.invalidResponse }
        return data
    }

    private func configuredURL() throws -> URL {
        do { return try baseURL() }
        catch { throw NativeAuthError.configuration }
    }

    private func makeCredentials(_ data: Data, base: URL) throws -> Credentials {
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        guard tokens.tokenType == "Bearer", tokens.expiresIn > 0, tokens.expiresIn <= 900,
              validToken(tokens.accessToken, prefix: "cp_at_"), validToken(tokens.refreshToken, prefix: "cp_rt_") else { throw NativeAuthError.invalidResponse }
        return Credentials(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
                           expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)), apiOrigin: base.absoluteString)
    }

    private func validToken(_ token: String, prefix: String) -> Bool {
        token.range(of: "^" + prefix + "[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
    }

    private func decodeUser(_ data: Data) throws -> NativeAuthUser {
        let account = try JSONDecoder().decode(UserEnvelope.self, from: data).user
        guard UUID(uuidString: account.id) != nil, account.accountStatus == "active" else { throw NativeAuthError.expiredSession }
        return account
    }

    private func loadCredentials(for url: URL) throws {
        if credentials == nil, let data = try store.read() {
            do { credentials = try JSONDecoder().decode(Credentials.self, from: data) }
            catch { try clearSession(); throw NativeAuthError.expiredSession }
        }
        if let current = credentials,
           current.apiOrigin != url.absoluteString || !validToken(current.accessToken, prefix: "cp_at_") || !validToken(current.refreshToken, prefix: "cp_rt_") {
            try clearSession()
        }
    }

    private func clearSession() throws {
        credentials = nil
        setUser(nil)
        state = .signedOut
        try store.remove()
    }

    private func setUser(_ next: NativeAuthUser?) {
        if next != nil { state = .signedIn }
        guard user != next else { return }
        user = next
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    private func begin(_ kind: OperationKind) throws -> UUID {
        try Task.checkCancellation()
        guard operation == nil else { throw NativeAuthError.busy }
        revision += 1
        let id = UUID()
        operation = (id, kind)
        return id
    }

    private func finish(_ id: UUID) { if operation?.id == id { operation = nil } }
    private func check(_ version: Int) throws {
        try Task.checkCancellation()
        guard revision == version else { throw CancellationError() }
    }
    private func finishRestore() async { if let flight = restoreFlight { _ = try? await flight.task.value } }

    private func friendly(_ error: Error, credentialsError: Bool = false) -> Error {
        if error is CancellationError { return CancellationError() }
        if let error = error as? NativeAuthError { return error }
        if let error = error as? HTTPFailure {
            switch error.status {
            case 401: return credentialsError ? NativeAuthError.invalidCredentials : NativeAuthError.expiredSession
            case 400, 413, 422: return NativeAuthError.invalidInput
            case 409: return NativeAuthError.duplicateEmail
            case 429: return NativeAuthError.rateLimited
            default: return NativeAuthError.unavailable
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled: return CancellationError()
            case .timedOut: return NativeAuthError.timeout
            case .cannotConnectToHost: return NativeAuthError.backendUnreachable
            case .cannotFindHost, .dnsLookupFailed: return NativeAuthError.addressUnreachable
            case .appTransportSecurityRequiresSecureConnection: return NativeAuthError.transportSecurity
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return NativeAuthError.networkSecurity
            default: return NativeAuthError.offline
            }
        }
        if error is DecodingError { return NativeAuthError.invalidResponse }
        return NativeAuthError.unavailable
    }
}
