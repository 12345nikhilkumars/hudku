import Darwin
import Dispatch

/// Returns allocator-held pages to the system after a surface closes; the caches that made
/// them are gone by then, so the next open simply re-warms what it needs.
enum MemoryPressure {
    @discardableResult
    static func relieve() -> Int {
        // A real goal: a goal of zero is advisory to do nothing, as measured on this OS.
        malloc_zone_pressure_relief(nil, 512 * 1024 * 1024)
    }

    /// A close's deallocations ride the runloop's drain, so a synchronous call sees almost
    /// nothing free; a beat later the teardown has landed and the purge is worth it.
    static func relieveAfterTeardown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { relieve() }
    }
}
