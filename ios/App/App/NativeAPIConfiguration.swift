import Foundation

enum NativeAPIConfiguration {
    static func baseURL() throws -> URL {
        try validatedBaseURL("https://chatpop-backend.onrender.com")
    }

    static func validatedBaseURL(_ value: String) throws -> URL {
        guard let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let url = parts.url, let host = parts.host, !host.isEmpty,
              host != "unconfigured.invalid", !host.contains("$"),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!) else { throw ConfigurationError() }
        let segments = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = segments.compactMap { UInt8($0) }
        let privateIPv4 = segments.count == 4 && octets.count == 4 && (octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168))
        guard host.lowercased() != "localhost", host != "::1", host != "[::1]", !host.hasPrefix("127.") else { throw ConfigurationError() }
        #if DEBUG
        guard parts.scheme == "https" || (parts.scheme == "http" && privateIPv4) else { throw ConfigurationError() }
        #else
        guard parts.scheme == "https", !privateIPv4, !host.hasSuffix(".local") else { throw ConfigurationError() }
        #endif
        return url
    }

    private struct ConfigurationError: LocalizedError {
        var errorDescription: String? { "The ChatPop server address is not configured correctly. Check the app's API configuration." }
    }
}
