import Foundation

/// The one place an entry's searchable names are decided, for every kind alike.
enum EntryNaming {
    /// Everything a producer knows about what its entry is called.
    struct Sources: Sendable, Hashable {
        var name: String
        /// Ranked like the title: a translation, a renamed file, a snippet keyword.
        var alternateTitles: [String] = []
        /// What the entry comes from, shown beside it: an extension's title.
        var subtitle: String?
        /// Found by, never ranked by: a declared name, an extension's keywords.
        var keywords: [String] = []

        init(name: String) { self.name = name }
    }

    static func profile(for sources: Sources) -> SearchProfile {
        let title = SearchText(sources.name, transliterated: true)
        // Folded, never transliterated: these compare against the query as typed.
        let alternates = usable(sources.alternateTitles, rejecting: [sources.name])
            .map { SearchText($0, transliterated: false) }
        let subtitle = sources.subtitle
            .map { SearchText($0, transliterated: true) }
            .flatMap { $0.isEmpty || $0.units == title.units ? nil : $0 }
        var keywords = usable(sources.keywords, rejecting: [sources.name] + sources.alternateTitles)
            .map { SearchText($0, transliterated: true) }
        if let subtitle { keywords += [title.joined(with: subtitle), subtitle.joined(with: title)] }
        let alternateMask = alternates.reduce(UInt64(0)) { $0 | $1.mask }
        let keywordMask = keywords.reduce(UInt64(0)) { $0 | $1.mask }
        return SearchProfile(
            title: title, alternateTitles: alternates, subtitle: subtitle, keywords: keywords,
            mask: title.mask | alternateMask | keywordMask | (subtitle?.mask ?? 0),
            titleMask: title.mask, alternateMask: alternateMask, subtitleMask: subtitle?.mask ?? 0,
            keywordMask: keywordMask)
    }

    static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Info.plist lists repeat the name and ship `ALTERNATE_NAME_1` placeholders.
    static func usable(_ raw: [String], rejecting existing: [String]) -> [String] {
        var seen = Set(existing.map { FuzzyMatch.normalized(strippingAppExtension($0)) })
        return raw.compactMap { candidate in
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return nil }
            let key = FuzzyMatch.normalized(strippingAppExtension(name))
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return name
        }
    }

    /// A lone SCREAMING_SNAKE token is an untranslated placeholder, and several ship.
    private static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && !name.contains(where: { $0.isLowercase || $0.isWhitespace })
    }
}

/// Built by `EntryNaming.profile` alone. The storage is boxed, so handing the profile
/// to a matcher costs one reference instead of retaining every field it holds.
struct SearchProfile: Sendable, Hashable {
    private final class Storage: Sendable {
        let title: SearchText
        let alternateTitles: [SearchText]
        let subtitle: SearchText?
        let keywords: [SearchText]
        let mask: UInt64
        let titleMask: UInt64
        let alternateMask: UInt64
        let subtitleMask: UInt64
        let keywordMask: UInt64

        init(
            title: SearchText, alternateTitles: [SearchText], subtitle: SearchText?,
            keywords: [SearchText], mask: UInt64, titleMask: UInt64, alternateMask: UInt64,
            subtitleMask: UInt64, keywordMask: UInt64
        ) {
            self.title = title
            self.alternateTitles = alternateTitles
            self.subtitle = subtitle
            self.keywords = keywords
            self.mask = mask
            self.titleMask = titleMask
            self.alternateMask = alternateMask
            self.subtitleMask = subtitleMask
            self.keywordMask = keywordMask
        }
    }

    private let storage: Storage

    var title: SearchText { storage.title }
    var alternateTitles: [SearchText] { storage.alternateTitles }
    var subtitle: SearchText? { storage.subtitle }
    /// Match to appear, never to rank.
    var keywords: [SearchText] { storage.keywords }
    /// Per-field character sets and their union, so a query a field cannot hold is skipped.
    var mask: UInt64 { storage.mask }
    var titleMask: UInt64 { storage.titleMask }
    var alternateMask: UInt64 { storage.alternateMask }
    var subtitleMask: UInt64 { storage.subtitleMask }
    var keywordMask: UInt64 { storage.keywordMask }

    init(
        title: SearchText, alternateTitles: [SearchText], subtitle: SearchText?,
        keywords: [SearchText], mask: UInt64, titleMask: UInt64, alternateMask: UInt64,
        subtitleMask: UInt64, keywordMask: UInt64
    ) {
        storage = Storage(
            title: title, alternateTitles: alternateTitles, subtitle: subtitle,
            keywords: keywords, mask: mask, titleMask: titleMask, alternateMask: alternateMask,
            subtitleMask: subtitleMask, keywordMask: keywordMask)
    }

    static func == (lhs: SearchProfile, rhs: SearchProfile) -> Bool {
        if lhs.storage === rhs.storage { return true }
        return lhs.title == rhs.title && lhs.alternateTitles == rhs.alternateTitles
            && lhs.subtitle == rhs.subtitle && lhs.keywords == rhs.keywords
            && lhs.mask == rhs.mask && lhs.titleMask == rhs.titleMask
            && lhs.alternateMask == rhs.alternateMask && lhs.subtitleMask == rhs.subtitleMask
            && lhs.keywordMask == rhs.keywordMask
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(alternateTitles)
        hasher.combine(subtitle)
        hasher.combine(keywords)
        hasher.combine(mask)
    }

    /// What an entry holds before its first index pass: nothing a query can reach.
    static let unnamed = SearchProfile(
        title: SearchText(units: []), alternateTitles: [], subtitle: nil, keywords: [],
        mask: 0, titleMask: 0, alternateMask: 0, subtitleMask: 0, keywordMask: 0)
}
