import Foundation

// MARK: - Provider link

struct ProviderLink: Equatable, Sendable {
    let url: URL
    let displayHost: String

    init(_ value: String) throws {
        let forbiddenScalars = value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
                || (0x202A...0x202E).contains($0.value)
                || (0x2066...0x2069).contains($0.value)
        }
        guard !value.isEmpty, value.utf8.count <= 2_048,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !forbiddenScalars,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let rawHost = components.host?.lowercased(),
              case let host = Self.withoutTrailingDots(rawHost),
              Self.validHost(host),
              let url = components.url else {
            throw RequestError.invalidProviderURL
        }
        self.url = url
        displayHost = host
    }

    /// `localhost.` and `tuck.local.` are the same hosts as their undotted forms; compare the normalized name.
    private static func withoutTrailingDots(_ host: String) -> String {
        var host = Substring(host)
        while host.hasSuffix(".") { host = host.dropLast() }
        return String(host)
    }

    private static func validHost(_ host: String) -> Bool {
        // Reject every IP literal: dotted IPv4 has no letters; IPv6 (including IPv4-mapped
        // forms such as [::ffff:203.0.113.5]) always carries ":" or brackets.
        guard host.contains("."), !host.contains(":"), !host.hasPrefix("["),
              host != "localhost", !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"), host.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        return host.contains { !$0.isNumber && $0 != "." }
    }
}

// MARK: - Credential request

struct CredentialRequest: Equatable, Sendable {
    let service: String
    let account: String
    let providerLink: ProviderLink?

    init(service: String, account: String, providerLink: ProviderLink? = nil) throws {
        guard Self.valid(service), Self.valid(account) else { throw RequestError.invalidDestination }
        self.service = service
        self.account = account
        self.providerLink = providerLink
    }

    private static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 200
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }
    }
}

// MARK: - Outcomes

enum RequestError: Error, Equatable {
    case invalidDestination
    case invalidProviderURL
}

enum SaveOutcome: String, Sendable {
    case saved, cancelled, timedOut = "timed_out", busy, failed
    /// The app bundle was replaced while this process kept running; Keychain writes would fail the code check.
    case restartRequired = "restart_required"
}
