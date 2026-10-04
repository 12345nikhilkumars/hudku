import Foundation

/// The parsed catalog: sections precomputed at load, search memoized one query deep.
@MainActor
@Observable
final class EmojiIndex {
    private(set) var entries: [EmojiEntry] = []
    private(set) var categorySections: [(category: EmojiCategory, entries: [EmojiEntry])] = []

    /// `order` is the catalog index, the tie-break that keeps equal scores in catalog order.
    private struct ScoredEntry {
        let entry: EmojiEntry
        let score: Int
        let order: Int
    }

    /// An entry's text folded once at load, so a keystroke folds only the query.
    private struct FoldedEntry: Sendable {
        let name: FuzzyMatch.Candidate
        let keywords: FuzzyMatch.Candidate
        let keywordList: [FuzzyMatch.Candidate]
        /// Per-field characters, so a query a field cannot hold skips its scoring whole.
        let nameMask: UInt64
        let keywordsMask: UInt64
        let keywordMasks: [UInt64]
        let mask: UInt64

        init(_ entry: EmojiEntry) {
            name = FuzzyMatch.Candidate(entry.name)
            keywords = FuzzyMatch.Candidate(entry.keywords)
            let items = entry.keywords.split(separator: ",").map { FuzzyMatch.Candidate(String($0)) }
            keywordList = items
            nameMask = CharIndex.mask(of: name.text)
            keywordsMask = CharIndex.mask(of: keywords.text)
            keywordMasks = items.map { CharIndex.mask(of: $0.text) }
            mask = nameMask | keywordsMask
        }
    }

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
        let frequentID: ObjectIdentifier
        let frequentRevision: Int
    }

    /// One bit per entry, per character its name or keywords can hold; a query enumerates
    /// the entries holding its characters instead of scanning the whole catalog.
    private struct CharIndex {
        var words = 0
        var postings: [Int: [UInt64]] = [:]
        /// Per character, its matches ranked cold. Every `:query` types through one of
        /// these first, and rescoring a thousand entries per keystroke is pure waste.
        var singleCharBases: [UInt8: [(order: Int, score: Int)]] = [:]

        /// 0 is the space, 1...26 are letters, 27...36 digits, 37 anything else printable.
        static func bit(for byte: UInt8) -> Int? {
            switch byte {
            case 0x20: return 0
            case 0x61...0x7A: return 1 + Int(byte - 0x61)
            case 0x30...0x39: return 27 + Int(byte - 0x30)
            case 0x21...0x7E: return 37
            default: return nil
            }
        }

        static func mask(of text: String) -> UInt64 {
            var mask: UInt64 = 0
            for byte in text.utf8 {
                guard let bit = bit(for: byte) else { continue }
                mask |= 1 << bit
            }
            return mask
        }

        init(folded: [FoldedEntry]) {
            let words = (folded.count + 63) / 64
            self.words = words
            guard words > 0 else { return }
            for (entry, value) in folded.enumerated() {
                var mask = value.mask
                guard mask != 0 else { continue }
                let word = entry >> 6
                let bit = UInt64(1) << UInt64(entry & 63)
                while mask != 0 {
                    let character = mask.trailingZeroBitCount
                    mask &= mask - 1
                    postings[character, default: [UInt64](repeating: 0, count: words)][word] |= bit
                }
            }
        }

        /// The single character's matches, scored once and kept cold-ranked.
        mutating func singleCharBase(
            for byte: UInt8, folded: [FoldedEntry], entries: [EmojiEntry]
        ) -> [(order: Int, score: Int)] {
            if let cached = singleCharBases[byte] { return cached }
            var ranked: [(order: Int, score: Int)] = []
            if words > 0, let bit = Self.bit(for: byte), let posting = postings[bit] {
                let query = FuzzyMatch.Query(String(UnicodeScalar(byte)))
                let queryMask = UInt64(1) << UInt64(bit)
                for word in posting.indices {
                    var set = posting[word]
                    while set != 0 {
                        let offset = set.trailingZeroBitCount
                        set &= set - 1
                        let order = (word << 6) + offset
                        guard order < folded.count,
                            let score = EmojiIndex.textScore(
                                query, terms: [], folded: folded[order], queryMask: queryMask)
                        else { continue }
                        ranked.append((order: order, score: score))
                    }
                }
            }
            ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            singleCharBases[byte] = ranked
            return ranked
        }

        /// Entry ordinals that can hold every character of `query`; nil when the query
        /// needs the full scan (a character the mapping cannot pin down).
        func entriesHolding(_ query: String) -> [Int]? {
            var bits = [UInt64](repeating: ~0, count: words)
            for byte in query.utf8 {
                // Separate words may match separate keyword fields, so the union is never
                // required to hold the space that joins them.
                if byte == 0x20 { continue }
                guard let character = Self.bit(for: byte) else { return nil }
                guard let posting = postings[character] else { return [] }
                for word in bits.indices { bits[word] &= posting[word] }
            }
            var found: [Int] = []
            for word in bits.indices {
                var w = bits[word]
                while w != 0 {
                    let bit = w.trailingZeroBitCount
                    w &= w - 1
                    found.append((word << 6) + bit)
                }
            }
            return found
        }
    }

    private var byGlyph: [String: EmojiEntry] = [:]
    /// Parallel to `entries`.
    private var foldedEntries: [FoldedEntry] = []
    private var charIndex = CharIndex(folded: [])
    @ObservationIgnored private var searchMemo = SmallMemo<SearchKey, [EmojiEntry]>()
    /// Bumped on each load, so the key above names the catalog it scored.
    private var revision = 0

    var isLoaded: Bool { !entries.isEmpty }
    @ObservationIgnored private var isLoading = false

    /// `languages` pick which of the bundle's keyword packs join the catalog's English keywords.
    /// A reload is a supported call; overlapping loads coalesce so a lazy trigger can fire freely.
    func load(_ raw: String = EmojiData.raw, languages: [String] = [], bundle: Bundle = .main) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let (parsed, folded, index) = await Task.detached(priority: .utility) {
            let parsed = EmojiCatalog.parse(raw, localized: Self.keywordPacks(for: languages, in: bundle))
            let folded = parsed.map(FoldedEntry.init)
            return (parsed, folded, CharIndex(folded: folded))
        }.value
        entries = parsed
        foldedEntries = folded
        charIndex = index
        var grouped: [EmojiCategory: [EmojiEntry]] = [:]
        for entry in parsed { grouped[entry.category, default: []].append(entry) }
        categorySections = EmojiCategory.allCases.compactMap { category in
            grouped[category].map { (category, $0) }
        }
        byGlyph = Dictionary(parsed.map { ($0.glyph, $0) }, uniquingKeysWith: { first, _ in first })
        revision &+= 1
    }

    /// Plain files, never `.lproj`: one would switch AppKit's own text out of English.
    private nonisolated static func keywordPacks(for languages: [String], in bundle: Bundle) -> [String] {
        let urls = bundle.urls(forResourcesWithExtension: "txt", subdirectory: "EmojiKeywords") ?? []
        let byLanguage = Dictionary(
            urls.map { ($0.deletingPathExtension().lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first })
        return EmojiCatalog.keywordLanguages(available: byLanguage.keys.sorted(), preferred: languages)
            .compactMap { byLanguage[$0].flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
    }

    func entry(for glyph: String) -> EmojiEntry? { byGlyph[glyph] }

    /// Ranked fuzzy matches over names and keywords; an empty query returns nothing.
    /// Every search ranks the fixed cap once, so the grid's limit and the launcher's
    /// narrower one share a slot instead of evicting each other.
    func search(_ query: String, frequent: FrequentEmojiStore, limit: Int = 320) -> [EmojiEntry] {
        guard limit > 0 else { return [] }
        if limit > Self.searchCap {
            return scan(query: query, frequent: frequent, cap: limit)
        }
        let key = SearchKey(
            query: query, revision: revision, frequentID: ObjectIdentifier(frequent),
            frequentRevision: frequent.revision)
        let top = searchMemo.value(for: key) {
            scan(query: query, frequent: frequent, cap: Self.searchCap)
        }
        return limit < top.count ? Array(top.prefix(limit)) : top
    }

    private static let searchCap = 320

    /// The cold ranking plus frecency. Every entry that carries a lift is added to the
    /// cold top, so the merge is exact — lift can never pull an entry past its cold band.
    private static func rankedFromBase(
        _ base: [(order: Int, score: Int)], cap: Int, frecency: [String: Int],
        entries: [EmojiEntry]
    ) -> [EmojiEntry] {
        guard !base.isEmpty else { return [] }
        if frecency.isEmpty {
            return base.prefix(cap).map { entries[$0.order] }
        }
        var merged: [(score: Int, order: Int)] = []
        merged.reserveCapacity(min(base.count, cap) + frecency.count)
        var seen: Set<Int> = []
        for item in base.prefix(cap) {
            seen.insert(item.order)
            merged.append((item.score + (frecency[entries[item.order].glyph] ?? 0), item.order))
        }
        for item in base where !seen.contains(item.order) {
            guard let lift = frecency[entries[item.order].glyph] else { continue }
            merged.append((item.score + lift, item.order))
        }
        merged.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return merged.prefix(cap).map { entries[$0.order] }
    }

    private func scan(query: String, frequent: FrequentEmojiStore, cap limit: Int) -> [EmojiEntry] {
            let trimmed = FuzzyMatch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
            let unwrapped =
                trimmed.count > 2 && trimmed.first == ":" && trimmed.last == ":"
                ? String(trimmed.dropFirst().dropLast()) : trimmed
            let words = unwrapped.split(whereSeparator: \.isWhitespace).map(String.init)
            let q = words.joined(separator: " ")
            guard !q.isEmpty, limit > 0 else { return [] }
            let frequentGlyphs = frequent.top(Self.frecencyLimit)
            let frecency = Dictionary(
                frequentGlyphs.enumerated().map {
                    ($0.element, Self.frecencyLimit - $0.offset)
                }, uniquingKeysWith: max)
            // A single character is the first press of every `:query`; its ranking is
            // scored once and reused, with frecency applied on top.
            if q.utf8.count == 1, let byte = q.utf8.first {
                let base = charIndex.singleCharBase(
                    for: byte, folded: foldedEntries, entries: entries)
                return Self.rankedFromBase(base, cap: limit, frecency: frecency, entries: entries)
            }
            let query = FuzzyMatch.Query(q)
            let terms = words.count > 1 ? words : []
            let queryMask = CharIndex.mask(of: q)
            var scored: [ScoredEntry] = []
            // A match needs every query character, so only entries holding them can score.
            if let candidates = charIndex.entriesHolding(q) {
                scored.reserveCapacity(candidates.count)
                for order in candidates {
                    guard
                        let textScore = Self.textScore(
                            query, terms: terms, folded: foldedEntries[order],
                            queryMask: queryMask)
                    else { continue }
                    let entry = entries[order]
                    let score = textScore + (frecency[entry.glyph] ?? 0)
                    scored.append(ScoredEntry(entry: entry, score: score, order: order))
                }
            } else {
                for (order, entry) in entries.enumerated() {
                    guard
                        let textScore = Self.textScore(
                            query, terms: terms, folded: foldedEntries[order],
                            queryMask: queryMask)
                    else { continue }
                    let score = textScore + (frecency[entry.glyph] ?? 0)
                    scored.append(ScoredEntry(entry: entry, score: score, order: order))
                }
            }
            return
                scored
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
                .prefix(limit)
                .map(\.entry)
    }

    /// Just under half a tier, so an equal-quality name match always wins.
    nonisolated private static let keywordPenalty = 500
    nonisolated private static let frecencyLimit = 100
    /// A complete leading name word: above an exact keyword, below the exact name.
    nonisolated private static let leadingWordScore = 95_000
    /// Scattered query words rank below every literal phrase, name-only words first.
    nonisolated private static let nameWordsScore = 60_000
    nonisolated private static let mixedWordsScore = 50_000

    nonisolated private static func textScore(
        _ query: FuzzyMatch.Query, terms: [String], folded: FoldedEntry, queryMask: UInt64
    ) -> Int? {
        var nameOnly = true
        for term in terms where !containsWordStart(term, in: folded.name.text) {
            guard !term.contains(","), containsWordStart(term, in: folded.keywords.text) else { return nil }
            nameOnly = false
        }

        // Without terms every match is single-field, so a field the query's characters
        // cannot fit is skipped before any scoring.
        let wholeQuery = terms.isEmpty
        let nameMatch =
            wholeQuery && (queryMask & ~folded.nameMask) != 0
            ? nil : FuzzyMatch.match(query, candidate: folded.name)
        if nameMatch?.tier == .exact { return nameMatch?.score }
        var best = nameMatch?.score
        if let nameMatch, nameMatch.tier == .prefix,
            let next = folded.name.text.dropFirst(nameMatch.queryLength).first,
            !next.isLetter && !next.isNumber
        {
            best = leadingWordScore - nameMatch.candidateLength
        }
        if !terms.isEmpty {
            let ordered = nameMatch?.tier == .subsequence ? nameMatch?.score ?? 0 : 0
            best = max(best ?? Int.min, (nameOnly ? nameWordsScore : mixedWordsScore) + ordered)
        }
        // A keyword contribution is capped, so a best already at the cap cannot improve.
        if let best, best >= leadingWordScore - keywordPenalty { return best }
        guard !folded.keywordList.isEmpty,
            !wholeQuery || (queryMask & ~folded.keywordsMask) == 0,
            FuzzyMatch.score(query, candidate: folded.keywords) != nil
        else { return best }
        for (keyword, mask) in zip(folded.keywordList, folded.keywordMasks) {
            if wholeQuery, (queryMask & ~mask) != 0 { continue }
            guard let match = FuzzyMatch.match(query, candidate: keyword) else { continue }
            best = max(best ?? Int.min, min(match.score, leadingWordScore) - keywordPenalty)
            if match.tier == .exact { break }
        }
        return best
    }

    nonisolated private static func containsWordStart(_ term: String, in candidate: String) -> Bool {
        var start = candidate.startIndex
        while let range = candidate.range(of: term, range: start..<candidate.endIndex) {
            if range.lowerBound == candidate.startIndex { return true }
            let previous = candidate[candidate.index(before: range.lowerBound)]
            if !previous.isLetter && !previous.isNumber { return true }
            start = candidate.index(after: range.lowerBound)
        }
        return false
    }
}
