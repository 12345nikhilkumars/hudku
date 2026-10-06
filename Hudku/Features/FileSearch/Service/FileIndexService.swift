import Foundation

/// Owns the file index. First use loads the persisted table or builds one; FSEvents keeps it
/// current; every build is written back, so the next launch loads instead of walking.
final class FileIndexService: @unchecked Sendable {
    static let shared = FileIndexService()

    struct Stats: Sendable {
        var source = "none"
        var entries = 0
        var loadMs = 0.0
        var buildMs = 0.0
    }

    private let queue = DispatchQueue(label: "com.hudku.fileindex", qos: .utility)
    private let lock = NSLock()
    private var table: FileIndexTable?
    private var tableKey = ""
    private var statSnapshot = Stats()
    private var watcher: FileIndexWatcher?
    private var wantedPolicy: FileSearchPolicy?
    private var activePolicy: FileSearchPolicy?
    private var building = false
    private var latestEventID: UInt64 = 0

    /// How old a persisted table may be before it is rebuilt regardless of event replay.
    private static let maxPersistedAge: TimeInterval = 72 * 3600

    var stats: Stats {
        lock.lock()
        defer { lock.unlock() }
        return statSnapshot
    }

    var entryCount: Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let table, tableKey.isEmpty == false else { return nil }
        return table.searchableCount
    }

    // MARK: - Requesting an index

    func apply(scopes: [String], ignorePatterns: [String]) {
        let policy = FileSearchPolicy(
            scopes: scopes, ignorePatterns: ignorePatterns,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        apply(policy)
    }

    func apply(_ policy: FileSearchPolicy) {
        queue.async { [weak self] in self?.request(policy) }
    }

    /// What the search session calls: one name scan over the owned table.
    func search(query: String, policy: FileSearchPolicy, filter: FileSearchFilter)
        -> [FileSearchResult]
    {
        let key = Self.key(for: policy)
        if snapshot(forKey: key) == nil {
            queue.async { [weak self] in self?.request(policy) }
            let deadline = Date().addingTimeInterval(10)
            while snapshot(forKey: key) == nil, Date() < deadline {
                usleep(40_000)
            }
        }
        guard let table = snapshot(forKey: key) else { return [] }
        return table.search(
            query: query, filter: filter, ignoring: policy.ignore,
            homeDirectory: policy.homeDirectory)
    }

    // MARK: - The build pump

    private func request(_ policy: FileSearchPolicy) {
        wantedPolicy = policy
        pump()
    }

    private func pump() {
        guard !building, let policy = wantedPolicy else { return }
        wantedPolicy = nil
        if Self.key(for: policy) == currentKey(), snapshotUnlocked() != nil { return }
        building = true
        buildNow(policy)
        building = false
        pump()
    }

    private func buildNow(_ policy: FileSearchPolicy) {
        let key = Self.key(for: policy)
        let started = Date()

        if let loaded = Self.loadFromDisk(), loaded.policyKey == key,
            loaded.table.buildDate > Date().addingTimeInterval(-Self.maxPersistedAge)
        {
            var table = loaded.table
            table.lastEventID = Swift.max(table.lastEventID, latestEventID)
            install(tableView: table, key: key, policy: policy)
            updateStats(source: "disk", table: table, elapsed: Date().timeIntervalSince(started))
            return
        }

        var table = FileIndexBuilder.build(policy: policy)
        table.lastEventID = latestEventID
        install(tableView: table, key: key, policy: policy)
        updateStats(source: "build", table: table, elapsed: Date().timeIntervalSince(started))
        Self.saveToDisk(table.serialized(policyKey: key))
    }

    private func install(tableView: FileIndexTable, key: String, policy: FileSearchPolicy) {
        lock.lock()
        table = tableView
        tableKey = key
        lock.unlock()
        startWatcher(policy: policy, sinceWhen: tableView.lastEventID)
    }

    private func updateStats(source: String, table: FileIndexTable, elapsed: TimeInterval) {
        lock.lock()
        var next = statSnapshot
        next.source = source
        next.entries = table.searchableCount
        if source == "disk" { next.loadMs = elapsed * 1000 } else { next.buildMs = elapsed * 1000 }
        statSnapshot = next
        lock.unlock()
    }

    private func startWatcher(policy: FileSearchPolicy, sinceWhen: UInt64) {
        watcher?.stop()
        activePolicy = policy
        let roots = FileIndexBuilder.scopeRoots(policy: policy)
        watcher = FileIndexWatcher(roots: roots, sinceWhen: sinceWhen) { [weak self] _, latestID in
            guard let self else { return }
            self.queue.async {
                self.latestEventID = Swift.max(self.latestEventID, latestID)
                guard let policy = self.activePolicy else { return }
                // Coalesced by the pump: one rebuild per settled batch of changes.
                self.wantedPolicy = policy
                self.pump()
            }
        }
    }

    // MARK: - State access

    private func currentKey() -> String {
        lock.lock()
        defer { lock.unlock() }
        return tableKey
    }

    private func snapshotUnlocked() -> FileIndexTable? {
        lock.lock()
        defer { lock.unlock() }
        return table
    }

    private func snapshot(forKey key: String) -> FileIndexTable? {
        lock.lock()
        defer { lock.unlock() }
        guard tableKey == key else { return nil }
        return table
    }

    private static func key(for policy: FileSearchPolicy) -> String {
        let scopes = (policy.includesHome ? ["~"] : []) + policy.directRoots.map(\.path)
        return policy.homeDirectory.path + "||" + scopes.joined(separator: "|")
            + "||" + policy.ignore.patterns.joined(separator: "|")
    }

    // MARK: - Persistence

    private static var fileURL: URL? {
        guard
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return nil }
        let directory = base.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.hudku.app", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("FileIndex.bin")
    }

    private static func loadFromDisk() -> (table: FileIndexTable, policyKey: String)? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return FileIndexTable.deserialized(data)
    }

    private static func saveToDisk(_ data: Data) {
        guard let url = fileURL else { return }
        try? data.write(to: url, options: .atomic)
    }
}
