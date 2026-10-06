import Foundation

/// The file search entry point: a scan over Hudku's own name index, nothing else.
enum FileSearchService {
    nonisolated static func search(
        query: String, policy: FileSearchPolicy, filter: FileSearchFilter = .all
    ) -> [FileSearchResult] {
        FileIndexService.shared.search(query: query, policy: policy, filter: filter)
    }
}
