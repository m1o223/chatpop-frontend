import Foundation

final class MemoryCredentials: NativeAuthCredentialStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func remove() throws { data = nil }
    func expire() throws {
        var json = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
        json["expiresAt"] = Date.distantPast.timeIntervalSinceReferenceDate
        data = try JSONSerialization.data(withJSONObject: json)
    }
}

@MainActor
final class MockAPI {
    let base = URL(string: "https://api.chatpop.invalid")!
    var calls: [String: Int] = [:]
    var refreshFailure = false
    var logoutFailure = false
    var wrongDeletePassword = false
    var delayLogin = false
    var delayProfile = false
    var profileOffline = false
    var loginStatus = 200
    var registrationStatus = 201
    var tokenNumber = 0
    let profile: [String: Any] = ["id": "4d8c6f51-16d0-47b5-8959-b9640fdfd416", "email": "sample@example.com", "display_name": "Sample", "account_status": "active"]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        calls[path, default: 0] += 1
        var status = 200
        var response: [String: Any] = [:]
        switch path {
        case "/auth/register": response = ["user": profile]; status = registrationStatus
        case "/auth/login":
            if delayLogin { try await Task.sleep(nanoseconds: 120_000_000) }
            response = tokens()
            status = loginStatus
        case "/auth/refresh":
            try await Task.sleep(nanoseconds: 40_000_000)
            if refreshFailure { throw URLError(.timedOut) }
            response = tokens()
        case "/auth/logout":
            if logoutFailure { throw URLError(.notConnectedToInternet) }
            status = 204
        case "/me":
            if delayProfile { try await Task.sleep(nanoseconds: 120_000_000) }
            if profileOffline { throw URLError(.notConnectedToInternet) }
            if request.httpMethod == "DELETE" { status = wrongDeletePassword ? 401 : 204 }
            else { response = ["user": profile] }
        default: status = 404
        }
        return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func tokens() -> [String: Any] {
        tokenNumber += 1
        let token = String(repeating: "A", count: 42) + String(tokenNumber % 10)
        return ["access_token": "cp_at_" + token, "refresh_token": "cp_rt_" + token, "expires_in": 900, "token_type": "Bearer"]
    }
    func session(_ store: MemoryCredentials) -> NativeAuthSession {
        NativeAuthSession(baseURL: { self.base }, store: store, transport: send)
    }
}

@main
struct Regressions {
    @MainActor static func expect(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }
    @MainActor static func main() async throws {
        let email = "sample@example.com", password = "valid-password-123"
        do {
            let api = MockAPI(), store = MemoryCredentials()
            let session = api.session(store)
            try await session.register(email: email, password: password)
            expect(session.user?.email == email && store.data != nil, "Registration must authenticate and persist")
            expect(api.calls["/auth/register"] == 1 && api.calls["/auth/login"] == 1 && api.calls["/me"] == 1, "Registration contract")
            let stored = String(data: store.data!, encoding: .utf8)!
            expect(!stored.contains(password) && !stored.contains(email), "Only tokens stored")
            session.cancelPendingAuthentication()
            expect(session.user != nil, "Closing completed flow must preserve session")
            try await session.signOut()
            expect(session.user == nil && store.data == nil && api.calls["/auth/logout"] == 1, "Logout clears storage after revocation")
            print("PASS registration, safe persistence, close after success, logout")
        }
        for delayProfile in [false, true] {
            let api = MockAPI(), store = MemoryCredentials()
            api.delayLogin = !delayProfile
            api.delayProfile = delayProfile
            let session = api.session(store)
            let task = Task { try await session.signIn(email: email, password: password) }
            try await Task.sleep(nanoseconds: 20_000_000)
            session.cancelPendingAuthentication()
            do { try await task.value; fatalError("Cancelled login completed") } catch is CancellationError {}
            expect(session.user == nil && store.data == nil, "Cancelled login must not commit")
            print("PASS close during \(delayProfile ? "profile" : "login") cannot commit")
        }
        do {
            let api = MockAPI(), store = MemoryCredentials()
            let session = api.session(store)
            try await session.signIn(email: email, password: password)
            let saved = store.data
            api.profileOffline = true
            do { try await session.restore(); fatalError("Offline profile accepted") } catch {}
            expect(session.user != nil && store.data == saved && session.state == .offline, "Offline restore must retain credentials and last verified profile")
            api.profileOffline = false
            try await session.restore()
            expect(session.user != nil, "Restoring connectivity must verify profile")
            print("PASS offline restore retains credentials and recovers")
        }
        do {
            let api = MockAPI(), store = MemoryCredentials()
            let session = api.session(store)
            api.loginStatus = 401
            do { try await session.signIn(email: email, password: "wrong"); fatalError("Wrong login accepted") }
            catch { expect(NativeAuthSession.message(for: error).contains("incorrect"), "Friendly invalid-credentials error") }
            api.registrationStatus = 409
            do { try await session.register(email: email, password: password); fatalError("Duplicate email accepted") }
            catch { expect(NativeAuthSession.message(for: error).contains("already exists"), "Friendly duplicate-email error") }
            api.registrationStatus = 201
            let count = api.calls
            do { try await session.register(email: email, password: "short"); fatalError("Weak password accepted") }
            catch { expect(NativeAuthSession.message(for: error).contains("12 to 128"), "Password requirements are reflected locally") }
            expect(api.calls == count && session.user == nil && store.data == nil, "Invalid local inputs never sent")
            print("PASS wrong credentials, duplicate email, local validation")
        }
        do {
            let cases: [(URLError.Code, NativeAuthError)] = [
                (.cannotConnectToHost, .backendUnreachable),
                (.cannotFindHost, .addressUnreachable),
                (.dnsLookupFailed, .addressUnreachable),
                (.notConnectedToInternet, .offline),
                (.networkConnectionLost, .offline),
                (.timedOut, .timeout),
                (.appTransportSecurityRequiresSecureConnection, .transportSecurity),
                (.serverCertificateUntrusted, .networkSecurity),
            ]
            for (code, expected) in cases {
                let store = MemoryCredentials()
                let session = NativeAuthSession(baseURL: { URL(string: "https://api.chatpop.invalid")! }, store: store) { _ in
                    throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "sensitive raw transport details"])
                }
                do { try await session.signIn(email: email, password: password); fatalError("Network failure accepted") }
                catch {
                    let message = NativeAuthSession.message(for: error)
                    expect(message == expected.errorDescription, "Network failure must retain its friendly category: \(code.rawValue)")
                    expect(!message.contains("sensitive raw"), "Raw transport errors must never reach the UI")
                }
                expect(session.user == nil && store.data == nil, "Failed connection must not save a session")
            }
            print("PASS offline, connection refusal, DNS, timeout, ATS, certificate error distinctions")
        }
        do {
            for status in [500, 502, 503] {
                let store = MemoryCredentials()
                let session = NativeAuthSession(baseURL: { URL(string: "https://api.chatpop.invalid")! }, store: store) { request in
                    (Data("database password and SQL details must stay hidden".utf8),
                     HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
                }
                do { try await session.signIn(email: email, password: password); fatalError("Server failure accepted") }
                catch { expect(NativeAuthSession.message(for: error) == NativeAuthError.unavailable.errorDescription, "Server details must remain sanitized") }
            }
            let session = NativeAuthSession(baseURL: { URL(string: "https://api.chatpop.invalid")! }, store: MemoryCredentials()) { _ in
                throw URLError(.cancelled)
            }
            do { try await session.signIn(email: email, password: password); fatalError("Cancelled request accepted") }
            catch is CancellationError {}
            print("PASS sanitized server failures and preserved network cancellation")
        }
        do {
            let api = MockAPI(), store = MemoryCredentials()
            try await api.session(store).signIn(email: email, password: password)
            try store.expire()
            let session = api.session(store)
            async let first: Void = session.restore()
            async let second: Void = session.restore()
            _ = try await (first, second)
            expect(api.calls["/auth/refresh"] == 1 && session.user != nil, "Refresh/restore must coalesce")
            print("PASS concurrent restore uses one refresh")
        }
        do {
            let api = MockAPI(), store = MemoryCredentials()
            try await api.session(store).signIn(email: email, password: password)
            try store.expire()
            api.refreshFailure = true
            let session = api.session(store)
            do { try await session.restore(); fatalError("Lost refresh accepted") } catch {}
            expect(api.calls["/auth/refresh"] == 1 && store.data != nil && session.user == nil, "Network failure must retain credentials")
            print("PASS interrupted refresh retains credentials without automatic retry")
        }
        do {
            let api = MockAPI(), store = MemoryCredentials()
            let session = api.session(store)
            try await session.signIn(email: email, password: password)
            api.logoutFailure = true
            do { try await session.signOut(); fatalError("Offline logout accepted") } catch {}
            expect(session.user != nil && store.data != nil, "Offline logout must not pretend revocation")
            api.logoutFailure = false
            api.wrongDeletePassword = true
            do { try await session.deleteAccount(password: "wrong"); fatalError("Wrong password accepted") } catch {}
            expect(session.user != nil && store.data != nil, "Wrong delete password must preserve account")
            api.wrongDeletePassword = false
            try await session.deleteAccount(password: password)
            expect(session.user == nil && store.data == nil, "Delete must clear credentials")
            print("PASS offline logout, wrong delete password, successful delete")
        }
        do {
            let api = MockAPI(), store = MemoryCredentials()
            try await api.session(store).signIn(email: email, password: password)
            let before = api.calls
            let session = NativeAuthSession(baseURL: { URL(string: "https://other.chatpop.invalid")! }, store: store, transport: api.send)
            try await session.restore()
            expect(session.user == nil && store.data == nil && before == api.calls, "Origin change must not transmit old tokens")
            print("PASS credentials are API-origin bound")
        }
        print("All native auth regression checks passed.")
    }
}
