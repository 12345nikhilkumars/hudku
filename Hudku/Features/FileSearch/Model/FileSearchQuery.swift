import Foundation

enum FileSearchQuery {
    /// Ranking headroom over the 200 displayed rows: constructing a result costs real URL
    /// work, so a common term ranks this many candidates and no more.
    static let candidateLimit = 400
    static let resultLimit = 200

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    /// One fold for both sides of a comparison: built into the index and applied to the query.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func rank(
        _ results: [FileSearchResult], for query: String, ignoring ignore: FileSearchIgnoreList
    ) -> [FileSearchResult] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }
        // Folded once each: a thousand candidates would otherwise re-fold every term per result.
        let whole = FuzzyMatch.Query(query)
        let folded = terms.map { FuzzyMatch.Query($0) }
        return results.filter { !isExcludedPath($0.id, ignoring: ignore) }.map { result in
            let full = FuzzyMatch.score(whole, candidate: result.name)
            let termScore = folded.compactMap { FuzzyMatch.score($0, candidate: result.name) }
                .reduce(0, +)
            return (result, full, termScore)
        }
        .sorted { left, right in
            switch (left.1, right.1) {
            case let (leftScore?, rightScore?) where leftScore != rightScore:
                return leftScore > rightScore
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if left.2 != right.2 { return left.2 > right.2 }
                let nameOrder = left.0.name.caseInsensitiveCompare(right.0.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return left.0.id.caseInsensitiveCompare(right.0.id) == .orderedAscending
            }
        }
        .prefix(resultLimit)
        .map(\.0)
    }

    static func matches(filename: String, query: String) -> Bool {
        let haystack = folded(filename)
        return terms(in: query).allSatisfy { haystack.contains(folded($0)) }
    }

    /// Hidden paths and bundle contents are what keep File Search permission-free.
    static func isExcludedPath(_ path: String, ignoring ignore: FileSearchIgnoreList) -> Bool {
        let structural = path.split(separator: "/").contains { component in
            (component.hasPrefix(".") && component != "." && component != "..")
                || component.lowercased().hasSuffix(".app")
        }
        return structural || ignore.excludes(path: path)
    }
}
