import Dispatch

/// The system's own pressure signal: when memory runs short, the app gives back what it holds.
@MainActor
final class MemoryPressureMonitor {
    var onPressureWarning: (() -> Void)?

    private var source: DispatchSourceMemoryPressure?

    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.onPressureWarning?() }
        }
        source.activate()
        self.source = source
    }
}
