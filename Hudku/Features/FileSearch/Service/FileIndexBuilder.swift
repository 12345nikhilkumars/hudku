import Foundation

/// Walks the policy's scopes once and hands back every name worth remembering. The walk
/// prunes exactly what a Spotlight search would have filtered out: hidden names, app
/// bundles, the ignore list, and `~/Library` on the home walk.
enum FileIndexBuilder {
    /// The directories an index walks. Home is one root (its Library is skipped at depth
    /// one), the cloud roots inside Library are separate ones, and every explicit scope
    /// stands alone.
    static func scopeRoots(policy: FileSearchPolicy) -> [URL] {
        var roots: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return }
            roots.append(standardized)
        }
        if policy.includesHome {
            add(policy.homeDirectory)
            for cloud in cloudRoots(homeDirectory: policy.homeDirectory) { add(cloud) }
        }
        for root in policy.directRoots { add(root) }
        return roots
    }

    /// iCloud Drive and friends, which live inside the Library the home walk skips.
    private static func cloudRoots(homeDirectory: URL) -> [URL] {
        let candidates = [
            homeDirectory.appending(path: "Library/CloudStorage", directoryHint: .isDirectory),
            homeDirectory.appending(
                path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory),
        ]
        return candidates.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    static func build(policy: FileSearchPolicy) -> FileIndexTable {
        let roots = scopeRoots(policy: policy)
        var records: [(name: String, parent: UInt32, isDirectory: Bool)] = []
        for _ in roots {
            records.append((name: "", parent: .max, isDirectory: true))
        }
        let homeHead: UInt32? = policy.includesHome ? 0 : nil
        var nodeByPath: [String: UInt32] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        for (headIndex, root) in roots.enumerated() {
            let head = UInt32(headIndex)
            nodeByPath[root.path] = head
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                guard let parent = nodeByPath[url.deletingLastPathComponent().path] else {
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let isDirectory = values.isDirectory == true

                // Skipped entirely: no row, and no descent into whatever it hides.
                if name.lowercased().hasSuffix(".app") || policy.ignore.excludes(path: url.path) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if let homeHead, parent == homeHead,
                    name.caseInsensitiveCompare("Library") == .orderedSame
                {
                    enumerator.skipDescendants()
                    continue
                }

                let node = UInt32(records.count)
                records.append((name: name, parent: parent, isDirectory: isDirectory))
                if isDirectory {
                    if values.isPackage == true {
                        // A bundle's innards are noise; the bundle itself stays a row.
                        enumerator.skipDescendants()
                    } else {
                        nodeByPath[url.path] = node
                    }
                }
            }
        }
        return FileIndexTable(roots: roots.map(\.path), records: records)
    }
}
