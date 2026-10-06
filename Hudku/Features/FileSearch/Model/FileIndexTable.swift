import Foundation
import UniformTypeIdentifiers

/// The owned file index: a flat forest of names with the folded bytes to match against.
/// Built once from the scopes, kept current by FSEvents, and searched by byte scan. No
/// Spotlight daemon, no per-query round trip: a scan of a few megabytes of names.
struct FileIndexTable: Sendable {
    struct Entry: Sendable {
        var nameOffset: UInt32
        var nameLength: UInt16
        var foldOffset: UInt32
        var foldLength: UInt16
        /// A parent entry index, or (below `headCount`) the head of a scope.
        var parent: UInt32
        var flags: UInt8

        var isDirectory: Bool { flags & 1 == 1 }
    }

    /// One virtual head per resolved scope directory. Heads are entries too, in order, so a
    /// head's index is its root's; their names are empty and they never match a search.
    var roots: [String]
    var entries: [Entry]
    /// UTF-8 names, back to back, addressed by `Entry.nameOffset`.
    var names: [UInt8]
    /// Folded names joined by a single NUL each, so a match can never span two entries.
    var folded: [UInt8]
    var buildDate: Date
    var lastEventID: UInt64

    var headCount: Int { roots.count }
    var searchableCount: Int { Swift.max(0, entries.count - headCount) }

    /// Records are the whole table in order: the `roots.count` heads first (names ignored),
    /// then every real entry, each naming a parent index.
    init(
        roots: [String], records: [(name: String, parent: UInt32, isDirectory: Bool)],
        buildDate: Date = Date(), lastEventID: UInt64 = 0
    ) {
        var entries: [Entry] = []
        var names: [UInt8] = []
        var folded: [UInt8] = []
        entries.reserveCapacity(records.count)
        for record in records {
            let nameBytes = Array(record.name.utf8)
            let foldBytes = Array(FileSearchQuery.folded(record.name).utf8)
            let nameOffset = UInt32(names.count)
            names.append(contentsOf: nameBytes)
            let foldOffset = UInt32(folded.count)
            folded.append(contentsOf: foldBytes)
            folded.append(0)
            entries.append(
                Entry(
                    nameOffset: nameOffset,
                    nameLength: UInt16(Swift.min(nameBytes.count, Int(UInt16.max))),
                    foldOffset: foldOffset,
                    foldLength: UInt16(Swift.min(foldBytes.count, Int(UInt16.max))),
                    parent: record.parent,
                    flags: record.isDirectory ? 1 : 0))
        }
        self.roots = roots
        self.entries = entries
        self.names = names
        self.folded = folded
        self.buildDate = buildDate
        self.lastEventID = lastEventID
    }

    // MARK: - Lookup

    func name(of index: Int) -> String {
        let entry = entries[index]
        let start = Int(entry.nameOffset)
        return String(
            decoding: names[start..<(start + Int(entry.nameLength))], as: UTF8.self)
    }

    /// Root path plus the chain of names above the entry, which is its absolute path.
    func path(of index: Int) -> String {
        var components = [name(of: index)]
        var cursor = Int(entries[index].parent)
        while cursor >= headCount {
            components.append(name(of: cursor))
            cursor = Int(entries[cursor].parent)
        }
        var path = roots[cursor]
        for component in components.reversed() {
            path += "/" + component
        }
        return path
    }

    /// What a query resolves to: candidates by byte scan, then the shared rank and caps.
    func search(
        query: String, filter: FileSearchFilter, ignoring ignore: FileSearchIgnoreList,
        homeDirectory: URL
    ) -> [FileSearchResult] {
        let terms = FileSearchQuery.terms(in: query)
            .map(FileSearchQuery.folded)
            .filter { !$0.isEmpty }
            .map { Array($0.utf8) }
        guard !terms.isEmpty else { return [] }

        var candidates: [Int]
        if terms.count == 1 {
            candidates = entryIndices(matchingFold: terms[0])
        } else {
            var common: Set<Int>?
            for term in terms {
                let hits = Set(entryIndices(matchingFold: term))
                common = common.map { $0.intersection(hits) } ?? hits
                if common?.isEmpty == true { break }
            }
            candidates = (common ?? []).sorted()
        }

        var results: [FileSearchResult] = []
        results.reserveCapacity(Swift.min(candidates.count, FileSearchQuery.candidateLimit))
        var typeCache: [String: UTType?] = [:]
        for index in candidates {
            if results.count >= FileSearchQuery.candidateLimit { break }
            let entry = entries[index]
            if filter != .all {
                guard
                    filter.accepts(
                        contentType: contentType(at: index, cache: &typeCache),
                        isDirectory: entry.isDirectory)
                else { continue }
            }
            let path = path(of: index)
            guard !FileSearchQuery.isExcludedPath(path, ignoring: ignore) else { continue }
            results.append(
                FileSearchResult(
                    url: URL(fileURLWithPath: path), isDirectory: entry.isDirectory,
                    homeDirectory: homeDirectory))
        }
        return FileSearchQuery.rank(results, for: query, ignoring: ignore)
    }

    private func contentType(at index: Int, cache: inout [String: UTType?]) -> UTType? {
        guard !entries[index].isDirectory else { return nil }
        let ext = (name(of: index) as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        if let cached = cache[ext] { return cached }
        let type = UTType(filenameExtension: ext)
        cache[ext] = type
        return type
    }

    /// How many hits one term may collect before the scan stops. Just above the display cap:
    /// a single letter over a quarter million names would otherwise build a set larger than
    /// anything that could ever be shown, and only the head of the ranking survives anyway.
    private static let hitLimit = 2_500

    private func entryIndices(matchingFold needle: [UInt8]) -> [Int] {
        guard !needle.isEmpty else { return [] }
        var hits: [Int] = []
        folded.withUnsafeBufferPointer { buffer in
            var searchFrom = 0
            var cursor = headCount
            while hits.count < Self.hitLimit {
                guard let offset = Self.find(needle, in: buffer, from: searchFrom) else { break }
                while cursor < entries.count,
                    Int(entries[cursor].foldOffset) + Int(entries[cursor].foldLength) <= offset
                {
                    cursor += 1
                }
                if cursor < entries.count, Int(entries[cursor].foldOffset) <= offset,
                    hits.last != cursor
                {
                    hits.append(cursor)
                }
                searchFrom = offset + 1
            }
        }
        return hits
    }

    /// First occurrence of `needle` at or after `from`; `memchr` does the scanning.
    private static func find(_ needle: [UInt8], in haystack: UnsafeBufferPointer<UInt8>, from: Int)
        -> Int?
    {
        guard !needle.isEmpty, haystack.count - from >= needle.count else { return nil }
        let limit = haystack.count - needle.count
        var index = from
        while index <= limit {
            guard
                let hit = memchr(haystack.baseAddress! + index, Int32(needle[0]), haystack.count - index)
            else { return nil }
            let offset = UnsafeRawPointer(hit) - UnsafeRawPointer(haystack.baseAddress!)
            if offset > limit { return nil }
            let matched = needle.withUnsafeBufferPointer { needleBuffer in
                memcmp(hit, needleBuffer.baseAddress!, needle.count) == 0
            }
            if matched { return offset }
            index = offset + 1
        }
        return nil
    }

    // MARK: - Persistence

    private static let magic: [UInt8] = Array("HUDKFI01".utf8)

    func serialized(policyKey: String) -> Data {
        var data = Data()
        data.append(contentsOf: Self.magic)
        data.appendSerializedString(policyKey)
        data.appendLE(buildDate.timeIntervalSince1970.bitPattern)
        data.appendLE(lastEventID)
        data.appendLE(UInt32(roots.count))
        for root in roots { data.appendSerializedString(root) }
        data.appendLE(UInt32(entries.count))
        for entry in entries {
            data.appendLE(entry.nameOffset)
            data.appendLE(entry.nameLength)
            data.appendLE(entry.foldOffset)
            data.appendLE(entry.foldLength)
            data.appendLE(entry.parent)
            data.append(entry.flags)
        }
        data.appendLE(UInt32(names.count))
        data.append(contentsOf: names)
        data.appendLE(UInt32(folded.count))
        data.append(contentsOf: folded)
        return data
    }

    static func deserialized(_ data: Data) -> (table: FileIndexTable, policyKey: String)? {
        var reader = ByteReader(data)
        guard reader.readBytes(magic.count) == magic else { return nil }
        guard let policyKey = reader.readString(),
            let buildBits = reader.readLE(UInt64.self),
            let lastEventID = reader.readLE(UInt64.self),
            let rootCount = reader.readLE(UInt32.self), rootCount <= 4_096
        else { return nil }
        var roots: [String] = []
        for _ in 0..<rootCount {
            guard let root = reader.readString() else { return nil }
            roots.append(root)
        }
        guard let entryCount = reader.readLE(UInt32.self), entryCount <= 4_000_000 else { return nil }
        var entries: [Entry] = []
        entries.reserveCapacity(Int(entryCount))
        for _ in 0..<entryCount {
            guard let nameOffset = reader.readLE(UInt32.self),
                let nameLength = reader.readLE(UInt16.self),
                let foldOffset = reader.readLE(UInt32.self),
                let foldLength = reader.readLE(UInt16.self),
                let parent = reader.readLE(UInt32.self),
                let flags = reader.readByte()
            else { return nil }
            entries.append(
                Entry(
                    nameOffset: nameOffset, nameLength: nameLength, foldOffset: foldOffset,
                    foldLength: foldLength, parent: parent, flags: flags))
        }
        guard let namesCount = reader.readLE(UInt32.self), let names = reader.readBytes(Int(namesCount)),
            let foldedCount = reader.readLE(UInt32.self), let folded = reader.readBytes(Int(foldedCount)),
            entries.count >= roots.count
        else { return nil }
        var table = FileIndexTable(roots: roots, records: [])
        table.entries = entries
        table.names = names
        table.folded = folded
        table.buildDate = Date(timeIntervalSince1970: Double(bitPattern: buildBits))
        table.lastEventID = lastEventID
        return (table, policyKey)
    }
}

private struct ByteReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func readByte() -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func readBytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, index + count <= bytes.count else { return nil }
        defer { index += count }
        return Array(bytes[index..<(index + count)])
    }

    mutating func readLE<T: FixedWidthInteger>(_ type: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard let raw = readBytes(size) else { return nil }
        var value: T = 0
        for (shift, byte) in raw.enumerated() {
            value |= T(byte) << (8 * shift)
        }
        return value
    }

    mutating func readString() -> String? {
        guard let length = readLE(UInt16.self), let raw = readBytes(Int(length)) else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendSerializedString(_ string: String) {
        let bytes = Array(string.utf8)
        appendLE(UInt16(Swift.min(bytes.count, Int(UInt16.max))))
        append(contentsOf: bytes.prefix(Int(UInt16.max)))
    }
}
