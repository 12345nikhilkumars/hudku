import CoreServices
import Darwin
import Foundation

/// Looks a term up in the dictionaries enabled in Dictionary.app, entirely on this Mac.
enum DictionaryService {
    /// Blocking and parse-heavy for a long entry, so the session runs it off the main actor.
    nonisolated static func entry(for term: String) -> DictionaryEntry? {
        let key = term.lowercased()
        if let cached = EntryCache.shared.payload(for: key) {
            switch cached {
            case .missing: return nil
            case .blocks(let blocks): return DictionaryEntry(term: term, blocks: blocks)
            }
        }
        let entry: DictionaryEntry?
        if let blocks = DictionaryRecords.resolved?.blocks(for: term) {
            entry = DictionaryEntry(term: term, blocks: blocks)
        } else {
            entry = plainText(for: term).map { DictionaryEntry(term: term, plainText: $0) }
        }
        EntryCache.shared.store(key, entry?.blocks)
        return entry
    }

    private nonisolated static func plainText(for term: String) -> String? {
        let range = CFRange(location: 0, length: term.utf16.count)
        guard let text = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue()
        else { return nil }
        let trimmed = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Terms a session has already resolved; the daemon round trip is the expensive part, and a
/// miss is worth remembering too. Lowercased keys, so `Hello` and `hello` share one entry.
private final class EntryCache: @unchecked Sendable {
    static let shared = EntryCache()

    enum Payload {
        case blocks([DictionaryEntry.Block])
        case missing
    }

    private let lock = NSLock()
    private var hits: [String: [DictionaryEntry.Block]] = [:]
    private var misses: Set<String> = []
    /// Plenty for a palette session; a full cache just resets rather than evicting one by one.
    private let limit = 64

    func payload(for key: String) -> Payload? {
        lock.lock()
        defer { lock.unlock() }
        if let blocks = hits[key] { return .blocks(blocks) }
        if misses.contains(key) { return .missing }
        return nil
    }

    func store(_ key: String, _ blocks: [DictionaryEntry.Block]?) {
        lock.lock()
        defer { lock.unlock() }
        if hits.count + misses.count >= limit {
            hits.removeAll()
            misses.removeAll()
        }
        if let blocks { hits[key] = blocks } else { misses.insert(key) }
    }
}

/// Dictionary Services' record calls: what Dictionary.app reads, though no header declares them.
private struct DictionaryRecords: Sendable {
    private typealias ActiveDictionaries = @convention(c) () -> Unmanaged<CFArray>?
    private typealias CopyRecords =
        @convention(c) (
            DCSDictionary, CFString, UnsafeRawPointer?, UnsafeRawPointer?
        ) -> Unmanaged<CFArray>?
    private typealias CopyData = @convention(c) (CFTypeRef, CFIndex) -> Unmanaged<CFString>?

    /// `DCSRecordCopyData`'s XHTML version; the plain-text one is what the public API returns.
    private static let xhtml: CFIndex = 0

    private let activeDictionaries: ActiveDictionaries
    private let copyRecords: CopyRecords
    private let copyData: CopyData

    /// Looked up at run time: a macOS that drops a symbol loses the layout, not the launch.
    static let resolved: DictionaryRecords? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let active = dlsym(rtldDefault, "DCSGetActiveDictionaries"),
            let records = dlsym(rtldDefault, "DCSCopyRecordsForSearchString"),
            let data = dlsym(rtldDefault, "DCSRecordCopyData")
        else { return nil }
        return DictionaryRecords(
            activeDictionaries: unsafeBitCast(active, to: ActiveDictionaries.self),
            copyRecords: unsafeBitCast(records, to: CopyRecords.self),
            copyData: unsafeBitCast(data, to: CopyData.self))
    }()

    /// The first enabled dictionary that knows the term, in Dictionary.app's own order.
    func blocks(for term: String) -> [DictionaryEntry.Block]? {
        guard let dictionaries = activeDictionaries()?.takeUnretainedValue() as? [DCSDictionary]
        else { return nil }
        for dictionary in dictionaries {
            guard
                let records = copyRecords(dictionary, term as CFString, nil, nil)?
                    .takeRetainedValue() as? [CFTypeRef]
            else { continue }
            let blocks = records.flatMap { record in
                (copyData(record, Self.xhtml)?.takeRetainedValue() as String?)
                    .map(DictionaryMarkup.blocks(fromXHTML:)) ?? []
            }
            if !blocks.isEmpty { return blocks }
        }
        return nil
    }
}
