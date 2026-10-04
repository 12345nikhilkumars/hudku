import Foundation

/// The launcher's two orderings, kept pure so a harness ranks the shipped code.
enum LauncherOrder {
    /// Folded once per pass, in both forms the fields compare against.
    struct Query: Sendable {
        /// Titles, subtitles, keywords and search terms compare against the Latin reading.
        let latin: SearchText
        /// Alternate titles and aliases compare against the text as typed.
        let typed: SearchText
        let term: String

        var isEmpty: Bool { typed.isEmpty }

        init(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            latin = SearchText(trimmed, transliterated: true)
            typed = SearchText(trimmed, transliterated: false)
            term = typed.string
        }
    }

    struct Signals: Sendable {
        var alias: SearchText?
        var usage: LauncherUsage
        /// Which kind wins a full tie; higher first.
        var priority: Int
        var title: String
        /// Queries this entry wins until the user opens a rival more.
        var boostedTerms: Set<String> = []
    }

    static func ranked<Item>(
        _ items: [Item], query: Query, sensitivity: SearchSensitivity, limit: Int,
        profile: (Item) -> SearchProfile, signals: (Item) -> Signals
    ) -> [Item] {
        guard !query.isEmpty else { return [] }
        // One scratch for the whole pass: the per-candidate alignment never allocates.
        let scratch = LauncherMatch.Scratch()
        let latinMask = query.latin.mask
        let typedMask = query.typed.mask
        // Scored by index, so sorting swaps compact values and each item is touched once.
        var scored: [(index: Int, candidate: Candidate)] = []
        scored.reserveCapacity(items.count)
        for index in items.indices {
            let item = items[index]
            let signals = signals(item)
            guard
                let facts = Facts(
                    profile: profile(item), signals: signals, query: query,
                    sensitivity: sensitivity, latinMask: latinMask, typedMask: typedMask,
                    scratch: scratch)
            else { continue }
            scored.append(
                (index, Candidate(facts: facts, signals: signals, position: index)))
        }
        let length = query.latin.units.count
        return
            scored
            .sorted { orders($0.candidate, before: $1.candidate, length: length) }
            .prefix(limit)
            .map { items[$0.index] }
    }

    /// The empty list: most frecent first, then aliased entries, then by kind and name.
    static func byUsage<Item>(_ items: [Item], signals: (Item) -> Signals) -> [Item] {
        items.indices
            .map { (index: $0, candidate: Candidate(facts: nil, signals: signals(items[$0]), position: $0)) }
            .sorted {
                let order = tiebreak($0.candidate, $1.candidate)
                return order != 0 ? order < 0 : $0.candidate.position < $1.candidate.position
            }
            .map { items[$0.index] }
    }

    // MARK: - One entry's match

    /// Only what the comparator reads: the heavyweight `Signals` is consumed once, here.
    private struct Candidate {
        let facts: Facts?
        let frecency: Double
        let priority: Int
        let title: String
        let hasAlias: Bool
        let position: Int

        init(facts: Facts?, signals: Signals, position: Int) {
            self.facts = facts
            frecency = signals.usage.frecency
            priority = signals.priority
            title = signals.title
            hasAlias = signals.alias != nil
            self.position = position
        }
    }

    private enum AliasHit: Equatable {
        case none
        case prefix
        case exact
    }

    /// How a past search term relates to the query; `length` is the stored term's.
    private enum TermHit: Equatable {
        case none
        case exact(length: Int)
        case prefix(length: Int)
        case overbounds(length: Int)

        var strength: Int {
            switch self {
            case .none: 0
            case .overbounds: 1
            case .prefix: 2
            case .exact: 3
            }
        }

        var isExact: Bool { if case .exact = self { true } else { false } }
        var isPrefix: Bool { if case .prefix = self { true } else { false } }

        /// A stored term this long or longer is specific enough to reorder a longer query.
        var isLongOverbounds: Bool {
            if case .overbounds(let length) = self { length >= LauncherOrder.overboundsFloor } else { false }
        }
    }

    /// Nil when the entry does not match at all.
    private struct Facts {
        let alias: AliasHit
        let isBoosted: Bool
        let titleExact: Bool
        /// The best of the title and alternate titles; an exact hit is `Int.max`.
        let title: Int
        let titlePrefix: Bool
        let subtitleExact: Bool
        let subtitle: Int
        let term: TermHit

        init?(
            profile: SearchProfile, signals: Signals, query: borrowing Query,
            sensitivity: SearchSensitivity, latinMask: UInt64, typedMask: UInt64,
            scratch: LauncherMatch.Scratch
        ) {
            let latinLength = query.latin.units.count
            let typedLength = query.typed.units.count
            alias = signals.alias.map { Self.aliasHit($0, query.typed) } ?? .none
            isBoosted = signals.boostedTerms.contains(query.term)
            // A field whose characters cannot hold the query is skipped before any scoring.
            let titleMatch =
                LauncherMatch.covers(latinMask, in: profile.titleMask)
                ? LauncherMatch.match(query.latin, in: profile.title, scratch: scratch) : nil
            let aliasText = alias == .none ? signals.alias : nil
            var titleExactFound = titleMatch == .exact
            var titleValue = Self.value(titleMatch)
            var prefixFound = profile.title.units.starts(with: query.latin.units)
            var alternatePasses = false

            func foldAlternate(_ text: SearchText) {
                let outcome = LauncherMatch.match(query.typed, in: text, scratch: scratch)
                if outcome == .exact { titleExactFound = true }
                titleValue = max(titleValue, Self.value(outcome))
                if !alternatePasses, let outcome,
                    sensitivity.accepts(outcome, queryLength: typedLength)
                {
                    alternatePasses = true
                }
                if !prefixFound, text.units.starts(with: query.typed.units) { prefixFound = true }
            }
            for alternate in profile.alternateTitles where alternate.covers(typedMask) {
                foldAlternate(alternate)
            }
            if let aliasText, aliasText.covers(typedMask) { foldAlternate(aliasText) }

            let subtitleMatch =
                LauncherMatch.covers(latinMask, in: profile.subtitleMask)
                ? profile.subtitle.flatMap {
                    LauncherMatch.match(query.latin, in: $0, scratch: scratch)
                } : nil
            var keywordPasses = false
            if LauncherMatch.covers(latinMask, in: profile.keywordMask) {
                for keyword in profile.keywords where keyword.covers(latinMask) {
                    guard let outcome = LauncherMatch.match(query.latin, in: keyword, scratch: scratch),
                        sensitivity.accepts(outcome, queryLength: latinLength)
                    else { continue }
                    keywordPasses = true
                    break
                }
            }

            func passes(_ outcome: LauncherMatch.Outcome?, _ length: Int) -> Bool {
                outcome.map { sensitivity.accepts($0, queryLength: length) } ?? false
            }
            let isMatching =
                alias != .none || passes(titleMatch, latinLength)
                || alternatePasses || passes(subtitleMatch, latinLength) || keywordPasses
            guard isMatching else { return nil }

            titleExact = titleExactFound
            title = titleValue
            titlePrefix = prefixFound
            subtitleExact = subtitleMatch == .exact
            subtitle = Self.value(subtitleMatch)
            term = Self.termHit(signals.usage.searchTerms, query.latin.units)
        }

        /// A miss sorts below every alignment.
        private static func value(_ outcome: LauncherMatch.Outcome?) -> Int {
            outcome?.value ?? .min
        }

        /// A prefix hit must leave some of the alias still untyped.
        private static func aliasHit(_ alias: SearchText, _ query: SearchText) -> AliasHit {
            let a = alias.units
            let q = query.units
            if a.count > q.count { return a.starts(with: q) ? .prefix : .none }
            return a == q ? .exact : .none
        }

        /// Newest term first: an exact one wins outright, then the newest prefix.
        private static func termHit(_ terms: [String], _ query: [UInt16]) -> TermHit {
            var best = TermHit.none
            for term in terms.reversed() {
                let stored = term.utf16
                guard !stored.isEmpty else { continue }
                if stored.count > query.count {
                    guard stored.starts(with: query) else { continue }
                    if !best.isPrefix { best = .prefix(length: stored.count) }
                } else if stored.count == query.count {
                    if stored.elementsEqual(query) { return .exact(length: stored.count) }
                } else if query.starts(with: stored) {
                    let extra = query.count - stored.count
                    guard extra <= LauncherOrder.overboundsReach else { continue }
                    switch best {
                    case .none: best = .overbounds(length: stored.count)
                    case .overbounds(let length) where stored.count > length:
                        best = .overbounds(length: stored.count)
                    default: break
                    }
                }
            }
            return best
        }
    }

    /// How many characters a query may run past a stored term and still be read as it.
    private static let overboundsReach = 3
    private static let overboundsFloor = 3

    // MARK: - The comparator

    private static func orders(_ a: Candidate, before b: Candidate, length: Int) -> Bool {
        let order = compare(a, b, length: length)
        return order != 0 ? order < 0 : a.position < b.position
    }

    /// Negative puts `a` first; the first rule that separates the two decides.
    private static func compare(_ a: Candidate, _ b: Candidate, length: Int) -> Int {
        guard let x = a.facts, let y = b.facts else { return tiebreak(a, b) }
        if x.alias != y.alias, x.alias == .exact || y.alias == .exact {
            return x.alias == .exact ? -1 : 1
        }
        if x.isBoosted != y.isBoosted {
            let (boosted, other) = x.isBoosted ? (a, b) : (b, a)
            let used = other.frecency
            if !(used > 1 && used > boosted.frecency) { return x.isBoosted ? -1 : 1 }
        }
        if length > 3, x.titleExact || y.titleExact {
            guard x.titleExact, y.titleExact else { return x.titleExact ? -1 : 1 }
            return first(termStrength(x.term, y.term), frecency(a, b)) ?? tiebreak(a, b)
        }
        if x.term.isExact || y.term.isExact {
            guard x.term.isExact, y.term.isExact else { return x.term.isExact ? -1 : 1 }
            return first(frecency(a, b)) ?? tiebreak(a, b)
        }
        if x.subtitleExact || y.subtitleExact {
            guard x.subtitleExact, y.subtitleExact else { return x.subtitleExact ? -1 : 1 }
            return first(frecency(a, b), descending(x.title, y.title)) ?? tiebreak(a, b)
        }
        if (x.alias == .prefix) != (y.alias == .prefix) { return x.alias == .prefix ? -1 : 1 }
        if x.term.isPrefix != y.term.isPrefix { return x.term.isPrefix ? -1 : 1 }
        if x.term != .none, y.term != .none {
            if x.term.isPrefix, y.term.isPrefix, let order = first(frecency(a, b)) { return order }
            if case .overbounds(let left) = x.term, case .overbounds(let right) = y.term, left != right,
                left >= overboundsFloor || right >= overboundsFloor
            {
                return descending(left, right)
            }
            if x.term.isLongOverbounds != y.term.isLongOverbounds { return x.term.isLongOverbounds ? -1 : 1 }
        }
        if x.term.isLongOverbounds, y.term == .none { return -1 }
        if y.term.isLongOverbounds, x.term == .none { return 1 }
        let order = first(
            descending(max(x.title, x.subtitle), max(y.title, y.subtitle)), frecency(a, b),
            descending(x.title, y.title), descending(x.titlePrefix, y.titlePrefix),
            descending(a.priority, b.priority))
        return order ?? collate(a, b)
    }

    /// What decides two entries the query cannot tell apart.
    private static func tiebreak(_ a: Candidate, _ b: Candidate) -> Int {
        let aliased = descending(a.hasAlias, b.hasAlias)
        return first(frecency(a, b), aliased, descending(a.priority, b.priority))
            ?? collate(a, b)
    }

    private static func termStrength(_ x: TermHit, _ y: TermHit) -> Int {
        if x.strength != y.strength { return descending(x.strength, y.strength) }
        if case .overbounds(let left) = x, case .overbounds(let right) = y { return descending(left, right) }
        return 0
    }

    private static func frecency(_ a: Candidate, _ b: Candidate) -> Int {
        descending(a.frecency, b.frecency)
    }

    /// Numeric and case-blind: `Item 2` before `Item 10`.
    private static func collate(_ a: Candidate, _ b: Candidate) -> Int {
        switch a.title.localizedStandardCompare(b.title) {
        case .orderedAscending: -1
        case .orderedDescending: 1
        case .orderedSame: 0
        }
    }

    private static func descending<Value: Comparable>(_ left: Value, _ right: Value) -> Int {
        left == right ? 0 : (left > right ? -1 : 1)
    }

    private static func descending(_ left: Bool, _ right: Bool) -> Int {
        left == right ? 0 : (left ? -1 : 1)
    }

    private static func first(_ orders: Int...) -> Int? {
        orders.first { $0 != 0 }
    }
}
