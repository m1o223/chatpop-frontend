import Foundation

// Test-only volatile storage: the app's default initializer always uses Keychain.
private final class LiveCheckStore: NativeAuthCredentialStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func remove() throws { data = nil }
}

private struct CheckFailure: Error { let message: String }

@main
private struct NativeAuthLiveCheck {
    @MainActor
    static func main() async {
        do {
            guard ProcessInfo.processInfo.environment["CHATPOP_AUTH_LIVE_CONFIRM"] == "local-test",
                  let rawURL = ProcessInfo.processInfo.environment["CHATPOP_AUTH_LIVE_BASE_URL"] else {
                throw CheckFailure(message: "Set CHATPOP_AUTH_LIVE_CONFIRM=local-test and CHATPOP_AUTH_LIVE_BASE_URL to the Mac LAN URL.")
            }
            let base = try NativeAPIConfiguration.validatedBaseURL(rawURL)
            guard base.scheme == "http" else { throw CheckFailure(message: "This smoke test is restricted to the local development HTTP API.") }
            try await run(base)
            print("PASS: native Swift client registered, restored, refreshed, logged out/revoked, logged in, handled invalid credentials/duplicate email, and deleted its temporary account over real HTTP.")
            print("This checks Foundation networking and the auth protocol, not iPhone Keychain or UIKit navigation.")
        } catch {
            print("FAIL: \((error as? CheckFailure)?.message ?? NativeAuthSession.message(for: error))")
            exit(1)
        }
    }

    @MainActor
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(message: message) }
    }

    @MainActor
    static func run(_ base: URL) async throws {
        let store = LiveCheckStore()
        let client = NativeAuthSession(baseURL: { base }, store: store)
        let email = "native-auth-check-\(UUID().uuidString.lowercased())@example.test"
        let password = UUID().uuidString + "-Test42!"
        var accountCreated = false
        do {
            try await client.register(email: email, password: password)
            accountCreated = true
            guard let id = client.user?.id else { throw CheckFailure(message: "Registration did not load /me.") }
            try require(client.user?.email == email && store.data != nil, "Registration did not save a session.")

            let duplicate = NativeAuthSession(baseURL: { base }, store: LiveCheckStore())
            do {
                try await duplicate.register(email: email, password: password)
                throw CheckFailure(message: "Duplicate registration unexpectedly succeeded.")
            } catch NativeAuthError.duplicateEmail { }

            let restored = NativeAuthSession(baseURL: { base }, store: store)
            try await restored.restore()
            try require(restored.user?.id == id, "A new client did not restore the same account.")
            guard let before = store.data,
                  var payload = try JSONSerialization.jsonObject(with: before) as? [String: Any] else {
                throw CheckFailure(message: "Missing serialized session.")
            }
            // Force the client's expiry path without changing server configuration or the real Keychain.
            payload["expiresAt"] = 0
            try store.write(JSONSerialization.data(withJSONObject: payload))
            let expired = NativeAuthSession(baseURL: { base }, store: store)
            try await expired.restore()
            try require(expired.user?.id == id && store.data != before, "Refresh did not rotate and restore the account.")
            guard let rotated = store.data,
                  let tokens = try JSONSerialization.jsonObject(with: rotated) as? [String: Any],
                  let access = tokens["accessToken"] as? String,
                  let refresh = tokens["refreshToken"] as? String else {
                throw CheckFailure(message: "Missing rotated session.")
            }
            try await expired.signOut()
            try require(expired.user == nil && store.data == nil, "Logout did not clear local state.")
            try await expectRevoked(base: base, path: "me", access: access)
            try await expectRevoked(base: base, path: "auth/refresh", refresh: refresh)

            let login = NativeAuthSession(baseURL: { base }, store: store)
            do {
                try await login.signIn(email: email, password: "incorrect-password")
                throw CheckFailure(message: "Wrong password unexpectedly succeeded.")
            } catch NativeAuthError.invalidCredentials { }
            try await login.signIn(email: email, password: password)
            try require(login.user?.id == id, "Login returned a different account.")
            try await login.deleteAccount(password: password)
            accountCreated = false
            try require(login.user == nil && store.data == nil, "Deletion did not clear local state.")
        } catch {
            if accountCreated {
                let cleanup = NativeAuthSession(baseURL: { base }, store: LiveCheckStore())
                do {
                    try await cleanup.signIn(email: email, password: password)
                    try await cleanup.deleteAccount(password: password)
                } catch { print("Cleanup could not finish; a native-auth-check account may remain in the development database.") }
            }
            throw error
        }
    }

    @MainActor
    static func expectRevoked(base: URL, path: String, access: String? = nil, refresh: String? = nil) async throws {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 10
        if let access { request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization") }
        if let refresh {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        }
        let network = URLSession(configuration: .ephemeral)
        defer { network.invalidateAndCancel() }
        let (_, response) = try await network.data(for: request)
        try require((response as? HTTPURLResponse)?.statusCode == 401, "Revoked credentials still had access.")
    }
}
