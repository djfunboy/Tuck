import Foundation

/// One well-known credential shape. Data lives in the generated `KeyFormats.swift`.
struct KeyFormat: Sendable {
    let id: String
    let provider: String
    let family: String
    let isGeneric: Bool
    let pattern: String
}

struct KeyRecognition: Equatable, Sendable {
    let provider: String
    let family: String
    let isGeneric: Bool
}

/// On-device recognition of well-known key formats. Advisory only: it never blocks a save,
/// never leaves the native window, and never retains the value it inspects.
enum KeyRecognizer {
    private struct Compiled: Sendable {
        let format: KeyFormat
        let regex: NSRegularExpression
    }

    private static let compiled: [Compiled] = KeyFormats.formats.compactMap { format in
        guard let regex = try? NSRegularExpression(pattern: format.pattern) else { return nil }
        return Compiled(format: format, regex: regex)
    }

    /// Format ids whose pattern does not compile. A unit test keeps this empty.
    static var invalidFormatIDs: [String] {
        KeyFormats.formats.filter { (try? NSRegularExpression(pattern: $0.pattern)) == nil }.map(\.id)
    }

    static func recognize(_ value: String) -> KeyRecognition? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        for generic in [false, true] {
            for entry in compiled where entry.format.isGeneric == generic {
                if entry.regex.firstMatch(in: trimmed, options: [.anchored], range: range) != nil {
                    return KeyRecognition(provider: entry.format.provider, family: entry.format.family, isGeneric: generic)
                }
            }
        }
        return nil
    }

    /// Whitespace that a provider will reject but a secure field cannot show.
    static func whitespaceHint(_ raw: String) -> String? {
        guard let last = raw.unicodeScalars.last else { return nil }
        if last == "\n" || last == "\r" { return String(localized: "ends with a line break") }
        if last == " " || last == "\t" { return String(localized: "ends with a space") }
        if let first = raw.unicodeScalars.first, CharacterSet.whitespacesAndNewlines.contains(first) {
            return String(localized: "starts with whitespace")
        }
        return nil
    }

    /// "a" or "an" for the provider name that follows.
    static func article(for provider: String) -> String {
        guard let first = provider.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }
}

/// Flags a recognized key whose family contradicts the destination the agent named.
enum DestinationMismatch {
    static func check(recognition: KeyRecognition, service: String, account: String) -> String? {
        guard !recognition.isGeneric else { return nil }
        let tokens = Set((service + " " + account).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        func names(_ family: String) -> [String] {
            (KeyFormats.familyAliases[family] ?? [family]).filter { $0.count >= 3 }
        }
        if names(recognition.family).contains(where: tokens.contains) { return nil }
        for family in namedFamilies where family != recognition.family {
            if names(family).contains(where: tokens.contains) { return family }
        }
        return nil
    }

    /// Families that have at least one provider-specific format. Generic shapes (JWT, PEM) never contradict a destination.
    private static let namedFamilies: [String] = Array(Set(KeyFormats.formats.filter { !$0.isGeneric }.map(\.family))).sorted()
}
