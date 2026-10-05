import Foundation

@main
private struct ConfigurationChecks {
    static func rejects(_ value: String) {
        do {
            _ = try NativeAPIConfiguration.validatedBaseURL(value)
            fatalError("Unsafe API configuration accepted")
        } catch { }
    }

    static func main() throws {
        _ = try NativeAPIConfiguration.validatedBaseURL("https://api.example.test")
        for value in ["", "$(API_BASE_URL)", "https://unconfigured.invalid", "http://example.test",
                      "http://localhost:3000", "http://127.0.0.1:3000", "http://[::1]:3000",
                      "http://10.bad.1.2.3:3000", "http://10.1.2.3.:3000", "http://10.1.2.300:3000",
                      "https://user:password@example.test", "https://example.test?secret=1",
                      "https://example.test#fragment", "https://example.test/auth", "https://example.test:0"] {
            rejects(value)
        }
        #if DEBUG
        for address in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.2"] {
            _ = try NativeAPIConfiguration.validatedBaseURL("http://\(address):3000")
        }
        rejects("http://172.32.0.1:3000")
        print("PASS Debug API URL validation")
        #else
        rejects("http://10.0.0.1:3000")
        rejects("https://192.168.1.2:3000")
        rejects("https://mac.local")
        print("PASS Release API URL validation")
        #endif
    }
}
