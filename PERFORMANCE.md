# Hudku performance profile - 2026-10-04

Machine: MacBook Pro (Mac16,8, M4 Pro, 24 GB), macOS 27.0 (26A428), Xcode 27.0 (27A266a).
Build under test: Release (`-O`, hardened runtime, ad-hoc signed), bundle `com.hudku.app.perf`,
243 indexed entries, fresh preferences. Harness: `Hudku/App/PerfHarness.swift` (inert unless
`HUDKU_PERF=1`), driven by the scripts in `/tmp/hudku-perf/`.

## How Hudku compares on this Mac

**Device**: MacBook Pro (Mac16,8), Apple M4 Pro, 24 GB, macOS 27.0 (26A428), Xcode 27.0 (27A266a).
All three launchers installed side by side and left untouched.

Method: quit everything, launch fresh, wait 45 s for startup work to settle, summon the
launcher's own surface (palette for Hudku and Tinycast, window for Raycast), wait 8 s more, then
measure for 60 s. Every process in the app's suite counts: the main process plus XPC services,
app extensions, processes that label themselves after the app (Raycast's Node backend does), and
any descendants. RAM is the summed `phys_footprint`, CPU the summed per-process CPU-time delta
over the window, threads and energy from `top`. Three runs per open state, medians shown; the
closed state is one run each. All runs on AC power.

| Launcher | Version | Processes | RAM (closed) | RAM (open) | Open CPU / 60 s | Energy (top) | Threads |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Hudku** | 0.0.1 | 1 | **22 MB** | **38 MB** | **0.04 s (0.07 %)** | **~0.02** | **3** |
| Tinycast (upstream) | 0.11.3 | 1 | 33 MB | 45 MB | 0.02 s (0.03 %) | 0.00 | 4 |
| Raycast | 2.6.2 | 4 (8 seen) | 272 MB | 287 MB (267-318) | 0.80 s (1.3 %) | ~1.1 | 82 |

Notes: Raycast's suite is its main process (29-30 MB), the Node "Raycast Backend" (195-245 MB),
and two small XPC services (Accessibility ~6.5 MB, Pasteboard 36 MB); the run-to-run spread is
almost entirely the backend. Its closed state costs the same as open (272 MB, 0.83 s): the Node
backend runs whether the window is up or not. The on-demand helpers (Raycast UI, Networking,
Graphics and Media, AppIntents) were not resident in these captures; a fuller state on this Mac
showed 8 processes and about 510 MB. Hudku and Tinycast each run a single process; threads are as
counted at the end of the window.

### Search speed, same harness in both codebases

The in-repo `HUDKU_PERF` harness compiles into both apps (upstream needs three extra
`LauncherScreen` initializer arguments) and drives the same 205-query corpus through the real
launcher screen, each query repeated many times. The first row aggregates the corpus (median of
the per-query medians, and their 90th percentile).

| | Hudku 0.0.1 | Tinycast (upstream HEAD) |
| --- | --- | --- |
| Palette search, median query p50 / p90 | **12.4 / 34.2 µs** | 108 / 167 µs |
| Single letters (`s`) | 7.9 µs | 304 µs |
| Two letters (`te`) | 53.8 µs | 229 µs |
| Full name (`safari`) | 5.3 µs | 86.2 µs |
| Empty query | 298 µs | 525 µs |
| Calculator, per-query average within each group (standalone, both sources) | 1.9 - 11.8 µs | 1.2 - 11.8 µs |

The same harness also times the feature engines directly in both apps (archived in
`features-hudku.json` and `features-tinycast.json`):

| Feature call (identical code path in both apps) | Hudku 0.0.1 | Tinycast (upstream HEAD) |
| --- | --- | --- |
| Emoji engine, per call p50 / p95 (n=50) | **0.33 / 1.4 µs** | 3054 / 4004 µs |
| Clipboard filter, p50 / p95 (n=40) | 58 / 126 µs | 31 / 59 µs |
| File search, MDQuery inside `/Applications`, p50 / p95 (n=12) | 52.3 / 87.5 ms | 53.2 / 75.8 ms |
| Dictionary lookup, p50 / p95 (n=4) | 4.1 / 7.9 ms | 8.1 / 14.3 ms |

In the emoji row, Hudku's first call in a fresh process builds the catalog (1.6 to 3.5 ms
depending on the run); every call after that is under a microsecond, while upstream pays
milliseconds on every call. Clipboard is the one row where upstream wins on today's clean
runs (31 vs 58 µs at the median); both are microseconds, and earlier runs had the spread the
other way, so read that row as parity. File search and dictionary are dominated by the system
services behind them (Spotlight, Dictionary Services), so both apps land in the same range,
with Hudku about 2x ahead on dictionary.

### Raycast, measured externally with real input

Raycast exposes its window to the Accessibility API, so its full input-to-result path was
measured with a probe that posts real key events and timestamps the AX notification storm
(a few ms resolution; the query is committed as one event, not per character):

| Command (typed into the real window) | First UI change p50 | Settled p50 |
| --- | --- | --- |
| App search (`safari`) | 7.1 ms | 7.1 ms |
| App search (`term`) | 13.6 ms | 14.2 ms |
| Calculator (`2+2`) | 14.6 ms | 14.8 ms |
| Currency (`10 usd in eur`) | 13.9 ms | 14.0 ms |
| Color (`#ff5733`) | 12.8 ms | 13.2 ms |
| Search Files (`nikhil`) | 12.5 ms | 12.7 ms |
| Search Emoji (`smile`) | 13.7 ms | 13.9 ms |
| Define Word (`hello`) | 12.3 ms | 12.6 ms |

So every Raycast command answers in roughly 7 to 15 ms end to end. Hudku and Tinycast expose
no AX tree (their panels are invisible to the Accessibility client), so their equivalent
external number cannot be taken the same way; their side of the comparison is the in-process
compute above plus the external CPU cost below.

### External CPU cost per query

Typing a query into the summoned palette and sampling the whole process suite until it idles
again: Hudku spends 0.00 to 0.01 s of CPU per query (usually below the sampling floor),
Tinycast 0.04 to 0.09 s. Raycast cannot be measured this way because its Node backend never
idles; its answer speed is the table above.

### The features are invoked differently, so read those rows with care

Emoji and dictionary have different entry points in each launcher: Hudku answers `:smile` and
`def word` inline in the root search; Tinycast opens a separate Emoji screen and reaches
dictionary lookups through a "Define Word" fallback row on the query; Raycast reaches both through
its own command and picker searches. The emoji and dictionary rows therefore compare the two
engines and the same service calls, not keystroke flows. The palette-search rows are the
like-for-like comparison: same corpus, same screen, same machine.

### Energy, honestly

`powermetrics` reports real joules but needs root, which was not available here, so energy comes
from `top`'s POWER column, a relative energy-impact score that tracked CPU near 1:1 in these
samples. Across its whole suite Raycast sits at about 1.1 (main process ~1.0, Node backend
~0.15), Hudku at ~0.02, Tinycast at 0.00 (below the column's resolution). On battery that is the
difference between a rounding error and a small but continuous background load.

### Flames

Pure-search windows were captured with xctrace Time Profiler for both apps. Tinycast's loop spends
roughly a quarter of its CPU in the copy and refcount storm around scoring (`swift_release`,
`swift_retain`, `swift_bridgeObject*`, plus per-candidate dictionary hashing); its actual match
loop (`align`) is about 2 % of CPU. That is precisely the pattern Hudku's mask index and
copy-light ranking removed, and it is where the 13x core-search gap lives. Raycast's main process,
sampled while idle, shows every thread parked on locks and semaphores, with brief JavaScriptCore
housekeeping as the only active leaves, matching its 1.3 % suite CPU. Artifacts:
`/tmp/hudku-perf/stats-tinycast.txt`, `folded-tinycast.txt`, and `raycast-idle.txt`.

## TL;DR - requirements vs measured

| Requirement | Before | After | Verdict |
| --- | --- | --- | --- |
| Text/app search | p50 **97 µs**, p95 174 µs | p50 **13.8 µs**, p90 36 µs, p99 67 µs; single letters **5–9 µs**, 3+ chars ~5–8 µs; worst 2-char 40–85 µs | 7× better overall, 30× on single letters - **still above the 1–2 µs ask**; see "What remains" |
| Emoji `:query` search | p50 **2.0–3.5 ms** | p50 **4–13 µs** (e.g. `:s` 3518→13 µs, `:smile` 2611→7 µs, `:sat` 3308→5.5 µs) | 200–600×; met |
| RAM after use | grew to **81 MB** over hours; 47–68 MB per session | Idle **21.7 MB**; palette open **38 MB**; after-use plateau **~58.5 MB and flat** - with close-time relief the soak even converges *down* (83.8→70.9→58.6→58.5→58.5 MB across cycles) | No creep (met); plateau still above the 40 MB goal |
| Idle CPU | 0.02–0.03 s per 60 s (~0.03–0.05 %) | unchanged | Accepted by you |
| Memo/hit path | 2.5 µs | **2.2 µs** | met |

All 42 test harnesses stay green after every change (`fuzz-test` and `emoji-search-test`
guard matching semantics).

## Search latency (final, per distinct query, cold)

| Group | n | p50 | p95 | max |
| --- | --- | --- | --- | --- |
| Text/app (fuzzy) | 190 | **13.8 µs** | 36 µs | 84 µs |
| Emoji (`:…`) | 8 | **7 µs** | 13 µs | 13 µs |
| Calculator | 2 | 8 µs | 8 µs | 8 µs |
| Dictionary trigger | 3 | 18 µs | 18 µs | 18 µs |
| Color | 1 | 6 µs | 6 µs | 6 µs |
| Empty query (favorites) | 1 | **345 µs** | 345 µs | 345 µs |
| Memo hit (repeat query) | 205 | **2.2 µs** | 5.7 µs | - |

Notables: `safari` 67 → **6.0 µs**; `s` 295 → **9.2 µs**; `t` 147 → 5.6; `c` – → 6.0;
`def hello` 98 → 18; `2+2` 75 → 8. Still slow: `st` 84 µs, `te` 60, `sa` 43 - two-char queries
whose letters seed many candidates and whose DP is two rows deep.

## What was done

The first trace showed matching was small: the CPU went to copies and refcounts. Every fix keeps
results bit-identical (proven by the unchanged harness suite).

1. **Character-mask prefilters.** Every searchable text carries a `UInt64` mask of the characters
   it can hold (`LauncherMatch.mask`, `SearchProfile.titleMask`/…). A query bit-tests any field
   before scoring it, and `AppIndex` keeps per-character postings (bitset over entries) so a query
   *enumerates* candidates instead of scanning all 243 entries (`AppIndex.ensureCharPostings`,
   `candidatePool`). Transcribed queries use the union of both folded forms - never an intersection.
2. **Zero-allocation matching.** `LauncherMatch.align` runs on reused scratch rows through unsafe
   buffers (`LauncherMatch.Scratch`); term and alternate loops, `SearchText` masks and `Facts`
   aggregates no longer allocate per candidate; the query folds once per string (`AppIndex.queryMemo`).
3. **Copy-light ranking.** `LauncherOrder` sorts `(index, compactCandidate)` tuples - a candidate is
   ints + one title - instead of copying `Item`/`Signals`/`SearchProfile` through the comparator.
   `SearchProfile` storage is boxed (one retain per pass), and `Facts` borrows the query.
4. **Emoji.** Per-character postings over the folded catalog; byte-level literal search and UTF-8
   subsequence walks (`FuzzyMatch.asciiFirstIndex`, byte `subsequenceScore`); keyword items are
   mask-pruned per field; the one-slot memo became limit-free (grid limit 320 and launcher limit 7
   no longer evict each other); single-character rankings are scored once and cached cold
   (`CharIndex.singleCharBase`) with frecency merged exactly at query time.
5. **A 12-entry LRU memo** (`SmallMemo`) for launcher matches/results and emoji searches - a render
   re-asks the same query, and backspace revisits the last few.
6. **Memory ceilings and close-time release.** `IconCache` general tier 32 → 16 MB (it is the
   launcher's warm-tile cache; every tile still fits). Palette hide now purges every icon tier, and
   both palette hide and Settings close hand freed pages back via `malloc_zone_pressure_relief`
   (`MemoryPressure`) - whose zero goal turned out to be a measured no-op on this OS, so it now
   passes a real goal, a beat after the teardown drains. Closing Settings also empties the closed
   window's content and bridged toolbar, so the hosting tree dies even though something in the
   AppKit/SwiftUI seam keeps the (now empty) window object itself.

## Memory (final)

Ladder (footprint, fresh instance): idle **22** → palette open **38** → emoji loaded 39 →
after search bench 54–68 → after dictionary+hide 56–72 MB, depending on what was touched.
Soak (6 × [show → queries → hide]): 83.8, 70.9, 58.6, 59.0, 58.5, 58.8 MB - with the close-time
purge and relief the retained set *converges down* over the first cycles, then sits **flat at
~58.5 MB**; nothing accumulates. The plateau's makeup (`vmmap`/`heap` at rest):

- Malloc Small dirty **40.4 MB** (live objects ≈ 25 MB; the rest is allocator metadata and retained
  free pages - the single largest lever left).
- CoreAnimation 5.3 MB (220 regions), CG Image 4.8 MB (155 regions) - window/icon surfaces, capped
  by the caches above.
- Heap top classes: `non-object` 7.4 MB, CoreSVG `SVGAttribute`+`SVGPathCommand`+maps ≈ **1.9 MB
  (5,393+4,739 objects - reproducible in fresh instances and growing slightly with use; worth a
  dedicated look)**, CFString 1.5 MB, dictionary/array storage ≈ 2 MB, SwiftUI `PropertyList.Element`
  370 KB, our `CharIndex` posting arrays 154 KB, `FuzzyMatch.Candidate` structures 324 KB.
- No leaks: 416 leaks / 20 KB total; everything else is deliberate retention (the hidden palette
  keeps its tree - the teardown experiment regressed input handling and stays reverted).

**Settings window.** Opening Settings costs **+37 MB** (56.9 → 94.2 MB in the harness), and closing
returns only ~5 MB - but the cycles prove it is *first-touch materialization, not a leak*: open 2
adds +0.7 MB, open 3 +0.1 MB, and each close lands back at the same plateau (87.7 → 88.4 → 88.5).
The closed-state leftovers are empty window husks (content and toolbar cleared); the retained
memory is framework machinery - objc method caches, CoreSVG rasterizations, vibrancy/glass
pipelines, font and icon subsystem caches - that later opens reuse instead of re-buying. Emptying
the tree on close is still done, so the hosting controller and its panes do not sit on the budget.

**A full pane sweep** originally peaked at ~152 MB and settled to ~106 MB closed - the heavy panes
(System Settings, 52 rows; System Actions, 31) were the fixable part: only the Applications and
Shortcuts panes used the row-virtualizing table, while the rest fell into a plain `ForEach` that a
`Form` realizes *in full* - every ~450-node SwiftUI row tree alive, ~1 MB per materialized row.
Every list now goes through the table, whose rows are virtualized against the enclosing scroll's
actual viewport: real cells only inside it, blank placeholders elsewhere, and departing rows are
torn down whole (a cell parked in the AppKit reuse pool would keep hosting its tree forever). Full
sweep now peaks at **113 MB** and settles to **~88 MB**; the System Settings pane dropped 135 → 105
and System Actions 152 → 113. Repeated sweeps add ~1 MB per cycle - first-touch plateau, no leak.
The About pane also downsamples its 1024px icns, and a system memory-pressure monitor purges icon
tiers and relieves the allocator whenever macOS reports pressure.

## CPU (unchanged; accepted)

Steady idle 0.02–0.03 s per 60 s (~0.03–0.05 %), 0.0 % in Activity Monitor, zero on-CPU samples in a
5 s Time Profiler attach; the 0.5 s pasteboard poll is the only recurring work. Under sustained 40 Hz
query churn the app spends ~82 % of CPU in SwiftUI/AttributeGraph rendering and only ~1–2 % in
search - the search work is no longer measurable at the system level.

**File search and Quick Look.** The screen itself retains nothing - a clean harness run is flat
(58 → 57.5 MB with results up, 57.0 with the overlay open, 57.6 closed). Previewing a real
document is the cost: the in-process PDF render buffer is a single ~41 MB allocation, PDFKit keeps
its parsed structures, and each preview engages macOS's Quick Look services (`QuickLookUIService`,
`QLPreviewGenerationExtension`, `Hudku Graphics and Media` - those child processes in Activity
Monitor are the system's, working on Hudku's behalf) plus XPC ports and worker threads. That is
per-preview machinery, released on close (both surfaces nil their document via `dismantleNSView`),
and the hide path additionally purges thumbnails and relieves the allocator.

**Clipboard browser.** Measured with 43 fabricated items (40 texts, one 22 k-char text, two 2400px
images): opening adds ~22 MB (lazy rows; mostly the item window and first-render machinery), the
large-text preview was +14 MB and is now capped at 12 000 rendered characters (+6.5 MB - copying
still takes the full text), and image previews decode through ImageIO at the pane's exact pixel
size into a cache purged on hide - that tier was 48 MB (a browse session held ~15 decodes) and is
now **12 MB**. After close ~+23 MB remains, diffuse (allocator
pages plus warm row thumbnails); the pressure monitor is the backstop. The store's in-memory
window was 1000 rows of item text held eagerly; it is now **300** - search still reaches older
rows through FTS and pinned rows always stay, so a heavy history's worst case drops to roughly a
third.

## What remains (levers, ranked)

1. **Two-char queries 40–85 µs** - the DP itself (~2 rows × width, word points per matched cell).
   Next lever: per-character *Fact snapshots* (score the static fields once per char; merge
   usage/frecency at query time), and incremental DP resume across keystrokes - both exact, both
   moderate surgery in `LauncherOrder`.
2. **Empty query 345 µs** - the favorites split + per-kind usage sorts on every palette open after
   invalidation. Cache the split itself (it only changes with favorites/ranking revisions).
3. **Plateau 66 MB → ≤40 MB** - with relief fixed (real goal, post-drain) the free-page lever is
   spent; what remains is fragmented partially-live pages and framework-side caches, plus the
   first-open Settings materialization (~29 MB) that only a lighter Settings composition would
   avoid. The clipboard window (1000 items) turned out to be a non-factor on this machine and is
   not worth trading depth for.
4. **CoreSVG ~2 MB** - find who retains parsed SVG structures for a single bundled asset.
5. Literal 1–2 µs on *cold* scans: today's floor is ~5–9 µs for sparse queries; only the snapshot /
   incremental work above compresses the dense-candidate cases further.

## Artifacts & reproduction

`/tmp/hudku-perf/` (temporary): `bench-final.json`, `soak-final.json`, `soak-capped.json`,
`tp-loops2.xml` + `folded-loops2.txt` (pure-search Time Profiler), `flame-*.svg`, and the scripts -
`run-session.sh` (bench/soak/profilers via `HUDKU_PERF_*`, `WAIT_PHASE`, `KILL`), `parse-tp.js`,
`flame.js`, `gen-queries.sh`. Perf builds use `PRODUCT_BUNDLE_IDENTIFIER=com.hudku.app.perf` for a
clean prefs domain and never touch the installed app's state.
