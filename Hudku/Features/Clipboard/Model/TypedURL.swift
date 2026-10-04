import Foundation

/// What a short typed or copied string names, shared by the browser fallback and the drag payload.
enum TypedURL: Equatable, Sendable {
    /// A browser reads `public.url`, a text field reads the string.
    case web(URL)
    case network(URL)
    case deeplink(URL)
    case path(String)

    /// A link or an address is one short token, so anything longer is prose by definition.
    private static let detectionLimit = 2048

    /// A scheme-less link needs a TLD people actually copy, or every `report.pdf` reads as one.
    private static let commonTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "co", "ai", "app", "dev", "me", "info", "biz",
        "xyz", "tv", "ly", "gg", "to", "uk", "us", "eu", "de", "fr", "es", "it", "nl", "se", "no",
        "fi", "dk", "ch", "at", "be", "ie", "cz", "ru", "ua", "tr", "cn", "jp", "kr", "hk", "sg",
        "au", "nz", "ca", "mx", "br", "ar", "za",
    ]

    /// What a string names, or nil when it names nothing openable.
    static func detect(_ text: String) -> TypedURL? {
        guard text.utf8.count <= detectionLimit else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isWhitespace) else { return nil }
        if token.hasPrefix("/") || token.hasPrefix("~") || token.hasPrefix("./") {
            return .path(token)
        }
        guard let separator = token.range(of: "://") else {
            guard isBareDomain(token), let url = URL(string: "https://" + token) else { return nil }
            return .web(url)
        }
        guard let url = URL(string: token) else { return nil }
        let scheme = token[token.startIndex..<separator.lowerBound].lowercased()
        switch scheme {
        case "http", "https": return .web(url)
        case "smb", "afp", "nfs": return .network(url)
        default: return .deeplink(url)
        }
    }

    private static func isBareDomain(_ token: String) -> Bool {
        guard token.contains("."), !token.contains("@"), !token.hasPrefix(".") else { return false }
        guard let host = token.split(separator: "/", omittingEmptySubsequences: false).first,
            !host.isEmpty
        else { return false }
        guard let tld = host.split(separator: ".").last?.lowercased() else { return false }
        return commonTopLevelDomains.contains(tld)
    }
}
