import CoreServices
import Foundation

/// FSEvents over the scope roots: any batch of changes settles for a few seconds, then one
/// call reports where they landed along with the newest event ID to resume from.
final class FileIndexWatcher: @unchecked Sendable {
    private let handler: @Sendable ([String], UInt64) -> Void
    private let queue = DispatchQueue(label: "com.hudku.fileindex.watch", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingPaths: Set<String> = []
    private var latestEventID: UInt64 = 0
    private var debounce: DispatchSourceTimer?

    /// `sinceWhen` replays whatever happened while the previous run was not watching.
    init?(
        roots: [URL], sinceWhen: UInt64,
        handler: @escaping @Sendable ([String], UInt64) -> Void
    ) {
        self.handler = handler
        guard !roots.isEmpty else { return nil }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let flags =
            UInt32(kFSEventStreamCreateFlagFileEvents) | UInt32(kFSEventStreamCreateFlagNoDefer)
            | UInt32(kFSEventStreamCreateFlagWatchRoot)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, eventIDs in
            guard let info else { return }
            Unmanaged<FileIndexWatcher>.fromOpaque(info).takeUnretainedValue()
                .receive(
                    count: count,
                    paths: paths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self),
                    eventIDs: eventIDs)
        }
        guard
            let created = FSEventStreamCreate(
                nil, callback, &context, roots.map(\.path) as CFArray,
                FSEventStreamEventId(sinceWhen), 1.0, flags)
        else { return nil }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return nil
        }
        stream = created
    }

    /// Runs on `queue`, so the state below is single-threaded by construction.
    private func receive(
        count: Int, paths: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>?,
        eventIDs: UnsafePointer<FSEventStreamEventId>?
    ) {
        guard let paths else { return }
        for index in 0..<count {
            pendingPaths.insert(String(cString: paths[index]))
            if let eventIDs { latestEventID = Swift.max(latestEventID, UInt64(eventIDs[index])) }
        }
        debounce?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 4.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let paths = Array(self.pendingPaths)
            self.pendingPaths.removeAll()
            self.handler(paths, self.latestEventID)
        }
        timer.resume()
        debounce = timer
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    deinit { stop() }
}
