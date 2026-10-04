import AppKit

/// Drives the launcher's real compute path on a loop for profiling. Inert unless HUDKU_PERF=1.
enum PerfHarness {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["HUDKU_PERF"] == "1" }

    @MainActor static func beginIfEnabled(core: AppCore) {
        guard isEnabled else { return }
        Task { await run(core: core) }
    }

    private static let directory = "/tmp/hudku-perf"

    @MainActor private static func run(core: AppCore) async {
        let env = ProcessInfo.processInfo.environment
        let outPath = env["HUDKU_PERF_OUT"] ?? "\(directory)/results.json"
        let queriesPath = env["HUDKU_PERF_QUERIES"] ?? "\(directory)/queries.txt"
        let benchSeconds = Double(env["HUDKU_PERF_BENCH_SECONDS"] ?? "") ?? 6
        let uiSeconds = Double(env["HUDKU_PERF_UI_SECONDS"] ?? "") ?? 0
        let holdSeconds = Double(env["HUDKU_PERF_HOLD_SECONDS"] ?? "") ?? 60
        let clock = ContinuousClock()
        var phases: [String] = []
        var footprints: [String: [String: UInt64]] = [:]
        var notes: [String: Any] = [:]

        func phase(_ name: String) {
            phases.append("\(name) \(String(format: "%.3f", ProcessInfo.processInfo.systemUptime))")
            try? phases.joined(separator: "\n")
                .write(toFile: "\(directory)/phase.txt", atomically: true, encoding: .utf8)
        }
        func snapshot(_ label: String) {
            footprints[label] = ["footprint": footprint(), "resident": resident()]
        }
        func sleep(_ seconds: Double) async {
            try? await Task.sleep(for: .seconds(seconds))
        }

        phase("settling")
        await sleep(2)
        snapshot("idle")
        notes["apps"] = core.appIndex.apps.count

        core.paletteCoordinator.showPalette(mode: .launcher)
        phase("opened")
        await sleep(1)
        snapshot("palette_open")

        if !core.emojiIndex.isLoaded {
            let start = clock.now
            await core.emojiIndex.load(languages: Locale.preferredLanguages)
            notes["emoji_load_ms"] = milliseconds(start.duration(to: clock.now))
        }
        notes["emoji_entries"] = core.emojiIndex.entries.count
        snapshot("emoji_loaded")
        phase("emoji_loaded")

        let refreshStart = clock.now
        await core.appIndex.refresh()
        notes["appindex_refresh_ms"] = milliseconds(refreshStart.duration(to: clock.now))
        notes["apps_after_refresh"] = core.appIndex.apps.count
        snapshot("index_refreshed")
        phase("index_refreshed")

        guard let queries = readQueries(queriesPath), !queries.isEmpty else {
            writeResults(
                outPath, phases: phases, footprints: footprints, notes: notes, timings: [:])
            phase("done")
            await sleep(holdSeconds)
            return
        }

        var missSamples: [String: [Double]] = [:]
        var hitSamples: [String: [Double]] = [:]
        phase("bench_start")
        let benchEnd = clock.now.advanced(by: .seconds(benchSeconds))
        var index = 0
        while clock.now < benchEnd {
            let query = queries[index % queries.count]
            index += 1
            core.palette.query = query
            let missStart = clock.now
            let screen = launcherScreen(core)
            let missMicros = micros(missStart.duration(to: clock.now))
            let hitStart = clock.now
            let second = launcherScreen(core)
            let hitMicros = micros(hitStart.duration(to: clock.now))
            _ = screen.rows.count + second.rows.count
            missSamples[query, default: []].append(missMicros)
            hitSamples[query, default: []].append(hitMicros)
        }
        phase("bench_end")
        snapshot("after_bench")

        if uiSeconds > 0 {
            phase("ui_start")
            let uiEnd = clock.now.advanced(by: .seconds(uiSeconds))
            var uiIndex = 0
            while clock.now < uiEnd {
                core.palette.query = queries[uiIndex % queries.count]
                uiIndex += 1
                await sleep(0.025)
            }
            phase("ui_end")
        }

        // The async half of `def`: debounce plus the blocking DCS lookup, timed to the landed entry.
        core.palette.query = "def hello"
        let landedStart = clock.now
        var landedMs: Double?
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if core.dictionary.lookup?.term == "hello", core.dictionary.lookup?.entry != nil {
                landedMs = milliseconds(landedStart.duration(to: clock.now))
                break
            }
            await sleep(0.005)
        }
        notes["dictionary_land_ms"] = landedMs ?? -1
        core.palette.query = ""
        snapshot("after_dictionary")

        core.paletteCoordinator.hidePalette(restoreFocus: false)
        phase("hidden")
        await sleep(2)
        snapshot("after_hide")

        let settingsCycles = Int(env["HUDKU_PERF_SETTINGS_CYCLES"] ?? "") ?? 1
        if env["HUDKU_PERF_SETTINGS"] == "1", settingsCycles > 0 {
            for cycle in 1...settingsCycles {
                if env["HUDKU_PERF_SETTINGS_PANES"] == "1" {
                    for tab in SettingsTab.allCases {
                        phase("settings_pane_\(tab)_\(cycle)")
                        core.settingsCoordinator.showSettings(tab: tab)
                        await sleep(2)
                        snapshot("settings_pane_\(tab)_\(cycle)")
                    }
                } else {
                    phase("settings_open_\(cycle)")
                    core.settingsCoordinator.showSettings()
                    await sleep(2)
                    snapshot("settings_open_\(cycle)")
                }
                phase("settings_close_\(cycle)")
                core.settingsCoordinator.closeSettings()
                await sleep(2)
                snapshot("settings_closed_\(cycle)")
                notes["windows_after_close_\(cycle)"] = NSApp.windows.count
                phase("settings_closed_done_\(cycle)")
            }
        }

        let soakCycles = Int(env["HUDKU_PERF_SOAK_CYCLES"] ?? "") ?? 0
        if soakCycles > 0 {
            for cycle in 1...soakCycles {
                phase("cycle_\(cycle)_start")
                core.paletteCoordinator.showPalette(mode: .launcher)
                let cycleEnd = clock.now.advanced(by: .seconds(8))
                var cycleIndex = 0
                while clock.now < cycleEnd {
                    core.palette.query = queries[cycleIndex % queries.count]
                    cycleIndex += 1
                    await sleep(0.025)
                }
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                core.palette.query = ""
                await sleep(2)
                snapshot("cycle_\(cycle)")
                phase("cycle_\(cycle)_done")
            }
        }

        writeResults(
            outPath, phases: phases, footprints: footprints, notes: notes,
            timings: ["miss_us": missSamples, "memo_hit_us": hitSamples])
        phase("done")
        await sleep(holdSeconds)
        if env["HUDKU_PERF_EXIT"] == "1" { NSApp.terminate(nil) }
    }

    @MainActor private static func launcherScreen(_ core: AppCore) -> LauncherScreen {
        LauncherScreen(
            appIndex: core.appIndex, favorites: core.favorites, visibility: core.visibility,
            currencyRates: core.currencyRates, core: core, vm: core.palette, running: false,
            openActions: {}, scrollToFollow: {})
    }

    private static func readQueries(_ path: String) -> [String]? {
        guard var text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        while text.hasSuffix("\n") { text.removeLast() }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    private static func micros(_ duration: Duration) -> Double { milliseconds(duration) * 1_000 }

    private static func footprint() -> UInt64 { vm(\.phys_footprint) }
    private static func resident() -> UInt64 { vm(\.resident_size) }

    private static func vm(_ key: KeyPath<task_vm_info_data_t, UInt64>) -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info[keyPath: key] : 0
    }

    private static func writeResults(
        _ path: String, phases: [String], footprints: [String: [String: UInt64]],
        notes: [String: Any], timings: [String: [String: [Double]]]
    ) {
        var payload: [String: Any] = ["phases": phases, "footprints": footprints, "notes": notes]
        var timingSummary: [String: [String: Any]] = [:]
        for (kind, perQuery) in timings {
            var summary: [String: Any] = [:]
            for (query, samples) in perQuery {
                let total = samples.reduce(0, +)
                summary[query] = [
                    "count": samples.count,
                    "mean": total / Double(max(samples.count, 1)),
                    "p50": percentile(samples, 0.5),
                    "p95": percentile(samples, 0.95),
                    "max": samples.max() ?? 0,
                ]
            }
            timingSummary[kind] = summary
        }
        payload["timings"] = timingSummary
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func percentile(_ samples: [Double], _ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[min(Int(Double(sorted.count) * p), sorted.count - 1)]
    }
}
