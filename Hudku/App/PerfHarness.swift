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
                let panePause = Double(env["HUDKU_PERF_SETTINGS_PANE_PAUSE"] ?? "") ?? 0
                if env["HUDKU_PERF_SETTINGS_PANES"] == "1" {
                    for tab in SettingsTab.allCases {
                        phase("settings_pane_\(tab)_\(cycle)")
                        core.settingsCoordinator.showSettings(tab: tab)
                        await sleep(2)
                        snapshot("settings_pane_\(tab)_\(cycle)")
                        notes["table_diag_\(tab)"] = TableVirtualizationProbe.report
                        if panePause > 0 { await sleep(panePause) }
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

        if env["HUDKU_PERF_FEATURES"] == "1" {
            phase("features_start")
            var features: [String: Any] = [:]

            var emojiSamples: [Double] = []
            for _ in 0..<10 {
                for term in ["s", "smile", "heart", "sm", "sa"] {
                    let start = clock.now
                    _ = core.emojiIndex.search(term, frequent: core.frequentEmoji, limit: 7)
                    emojiSamples.append(micros(start.duration(to: clock.now)))
                }
            }
            features["emoji_engine_us"] = summary(of: emojiSamples)

            if core.clipboardStore.items.count < 30 {
                for index in 0..<30 {
                    core.clipboardStore.addText("perf feature item \(index)", sourceBundleID: nil)
                }
                await sleep(0.5)
            }
            var clipboardSamples: [Double] = []
            for _ in 0..<10 {
                for query in ["", "item", "feature 1", "zzzz"] {
                    let start = clock.now
                    _ = core.clipboardStore.search(query, filter: .all)
                    clipboardSamples.append(micros(start.duration(to: clock.now)))
                }
            }
            features["clipboard_filter_us"] = summary(of: clipboardSamples)

            let policy = FileSearchPolicy(
                scopes: ["/Applications"], ignorePatterns: [],
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            FileIndexService.shared.apply(policy)
            let readyStart = clock.now
            while FileIndexService.shared.entryCount == nil,
                milliseconds(readyStart.duration(to: clock.now)) < 30_000
            {
                await sleep(0.05)
            }
            notes["fileindex_ready_ms"] = milliseconds(readyStart.duration(to: clock.now))
            notes["fileindex_entries"] = FileIndexService.shared.entryCount ?? -1
            notes["fileindex_source"] = FileIndexService.shared.stats.source
            notes["fileindex_build_ms"] = FileIndexService.shared.stats.buildMs
            notes["fileindex_load_ms"] = FileIndexService.shared.stats.loadMs
            var fileSamples: [Double] = []
            for query in ["safari", "term", "x", "photo"] {
                for _ in 0..<3 {
                    let start = clock.now
                    let results = await Task.detached(priority: .userInitiated) {
                        FileSearchService.search(query: query, policy: policy, filter: .all)
                    }.value
                    _ = results.count
                    fileSamples.append(micros(start.duration(to: clock.now)))
                }
            }
            features["file_search_us"] = summary(of: fileSamples)

            var dictionarySamples: [Double] = []
            for term in ["hello", "run", "light", "name"] {
                let start = clock.now
                _ = await Task.detached(priority: .userInitiated) {
                    DictionaryService.entry(for: term)
                }.value
                dictionarySamples.append(micros(start.duration(to: clock.now)))
            }
            features["dictionary_us"] = summary(of: dictionarySamples)

            // The same terms again: what a session pays once the memo holds them.
            var warmDictionarySamples: [Double] = []
            for _ in 0..<10 {
                for term in ["hello", "run", "light", "name"] {
                    let start = clock.now
                    _ = await Task.detached(priority: .userInitiated) {
                        DictionaryService.entry(for: term)
                    }.value
                    warmDictionarySamples.append(micros(start.duration(to: clock.now)))
                }
            }
            features["dictionary_warm_us"] = summary(of: warmDictionarySamples)

            notes["features"] = features
            phase("features_done")
        }

        if env["HUDKU_PERF_CLIPBOARD"] == "1" {
            phase("clipboard_fill")
            for index in 0..<40 {
                core.clipboardStore.addText(
                    "perf item \(index) " + String(repeating: "lorem ipsum dolor ", count: 80),
                    sourceBundleID: nil)
            }
            let big = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 500)
            core.clipboardStore.addText(big, sourceBundleID: nil)
            if let data = gradientPNG(side: 2400) {
                core.clipboardStore.addImage(data, sourceBundleID: nil)
                core.clipboardStore.addImage(data, sourceBundleID: nil)
            }
            await sleep(1)
            core.paletteCoordinator.showPalette(mode: .clipboard)
            await sleep(2)
            notes["clipboard_items"] = core.clipboardStore.items.count
            snapshot("clipboard_list")
            // Newest first: index 0 is an image, so this lands the heavy preview.
            core.palette.selection = 0
            await sleep(3)
            snapshot("clipboard_image_preview")
            if let index = core.clipboardStore.items.firstIndex(where: {
                ($0.text?.count ?? 0) > 20_000
            }) {
                core.palette.selection = index
            }
            await sleep(3)
            snapshot("clipboard_text_preview")
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            await sleep(3)
            snapshot("clipboard_closed")
            phase("clipboard_done")
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

    /// A real, heavy PNG for the clipboard leg: big enough that its decode dominates a preview.
    @MainActor private static func gradientPNG(side: Int) -> Data? {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for step in 0...16 {
            let fraction = CGFloat(step) / 17
            NSColor(hue: fraction, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
            NSRect(
                x: 0, y: fraction * CGFloat(side), width: CGFloat(side), height: CGFloat(side) / 16
            ).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
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

    private static func summary(of samples: [Double]) -> [String: Any] {
        guard !samples.isEmpty else { return [:] }
        let sorted = samples.sorted()
        return [
            "n": samples.count,
            "p50": percentile(sorted, 0.5),
            "p95": percentile(sorted, 0.95),
            "max": sorted.last ?? 0,
        ]
    }

    private static func percentile(_ samples: [Double], _ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[min(Int(Double(sorted.count) * p), sorted.count - 1)]
    }
}
