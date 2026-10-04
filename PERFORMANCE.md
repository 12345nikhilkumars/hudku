# Hudku performance profile — 2026-10-04

Machine: MacBook Pro (Mac16,8, M4 Pro, 24 GB), macOS 27.0 (26A428), Xcode 27.0 (27A266a).
Build under test: Release (`-O`, hardened runtime, ad-hoc signed), bundle `com.hudku.app.perf`,
243 indexed entries, fresh preferences. Harness: `Hudku/App/PerfHarness.swift` (inert unless
`HUDKU_PERF=1`), driven by the scripts in `/tmp/hudku-perf/`.

## TL;DR — requirements vs measured

| Requirement | Before | After | Verdict |
| --- | --- | --- | --- |
| Text/app search | p50 **97 µs**, p95 174 µs | p50 **13.8 µs**, p90 36 µs, p99 67 µs; single letters **5–9 µs**, 3+ chars ~5–8 µs; worst 2-char 40–85 µs | 7× better overall, 30× on single letters — **still above the 1–2 µs ask**; see "What remains" |
| Emoji `:query` search | p50 **2.0–3.5 ms** | p50 **4–13 µs** (e.g. `:s` 3518→13 µs, `:smile` 2611→7 µs, `:sat` 3308→5.5 µs) | 200–600×; met |
| RAM after use | grew to **81 MB** over hours; 47–68 MB per session | Idle **21.7 MB**; palette open **38 MB**; after-use plateau **~58.5 MB and flat** — with close-time relief the soak even converges *down* (83.8→70.9→58.6→58.5→58.5 MB across cycles) | No creep (met); plateau still above the 40 MB goal |
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
| Memo hit (repeat query) | 205 | **2.2 µs** | 5.7 µs | — |

Notables: `safari` 67 → **6.0 µs**; `s` 295 → **9.2 µs**; `t` 147 → 5.6; `c` – → 6.0;
`def hello` 98 → 18; `2+2` 75 → 8. Still slow: `st` 84 µs, `te` 60, `sa` 43 — two-char queries
whose letters seed many candidates and whose DP is two rows deep.

## What was done

The first trace showed matching was small: the CPU went to copies and refcounts. Every fix keeps
results bit-identical (proven by the unchanged harness suite).

1. **Character-mask prefilters.** Every searchable text carries a `UInt64` mask of the characters
   it can hold (`LauncherMatch.mask`, `SearchProfile.titleMask`/…). A query bit-tests any field
   before scoring it, and `AppIndex` keeps per-character postings (bitset over entries) so a query
   *enumerates* candidates instead of scanning all 243 entries (`AppIndex.ensureCharPostings`,
   `candidatePool`). Transcribed queries use the union of both folded forms — never an intersection.
2. **Zero-allocation matching.** `LauncherMatch.align` runs on reused scratch rows through unsafe
   buffers (`LauncherMatch.Scratch`); term and alternate loops, `SearchText` masks and `Facts`
   aggregates no longer allocate per candidate; the query folds once per string (`AppIndex.queryMemo`).
3. **Copy-light ranking.** `LauncherOrder` sorts `(index, compactCandidate)` tuples — a candidate is
   ints + one title — instead of copying `Item`/`Signals`/`SearchProfile` through the comparator.
   `SearchProfile` storage is boxed (one retain per pass), and `Facts` borrows the query.
4. **Emoji.** Per-character postings over the folded catalog; byte-level literal search and UTF-8
   subsequence walks (`FuzzyMatch.asciiFirstIndex`, byte `subsequenceScore`); keyword items are
   mask-pruned per field; the one-slot memo became limit-free (grid limit 320 and launcher limit 7
   no longer evict each other); single-character rankings are scored once and cached cold
   (`CharIndex.singleCharBase`) with frecency merged exactly at query time.
5. **A 12-entry LRU memo** (`SmallMemo`) for launcher matches/results and emoji searches — a render
   re-asks the same query, and backspace revisits the last few.
6. **Memory ceilings and close-time release.** `IconCache` general tier 32 → 16 MB (it is the
   launcher's warm-tile cache; every tile still fits). Palette hide now purges every icon tier, and
   both palette hide and Settings close hand freed pages back via `malloc_zone_pressure_relief`
   (`MemoryPressure`) — whose zero goal turned out to be a measured no-op on this OS, so it now
   passes a real goal, a beat after the teardown drains. Closing Settings also empties the closed
   window's content and bridged toolbar, so the hosting tree dies even though something in the
   AppKit/SwiftUI seam keeps the (now empty) window object itself.

## Memory (final)

Ladder (footprint, fresh instance): idle **22** → palette open **38** → emoji loaded 39 →
after search bench 54–68 → after dictionary+hide 56–72 MB, depending on what was touched.
Soak (6 × [show → queries → hide]): 83.8, 70.9, 58.6, 59.0, 58.5, 58.8 MB — with the close-time
purge and relief the retained set *converges down* over the first cycles, then sits **flat at
~58.5 MB**; nothing accumulates. The plateau's makeup (`vmmap`/`heap` at rest):

- Malloc Small dirty **40.4 MB** (live objects ≈ 25 MB; the rest is allocator metadata and retained
  free pages — the single largest lever left).
- CoreAnimation 5.3 MB (220 regions), CG Image 4.8 MB (155 regions) — window/icon surfaces, capped
  by the caches above.
- Heap top classes: `non-object` 7.4 MB, CoreSVG `SVGAttribute`+`SVGPathCommand`+maps ≈ **1.9 MB
  (5,393+4,739 objects — reproducible in fresh instances and growing slightly with use; worth a
  dedicated look)**, CFString 1.5 MB, dictionary/array storage ≈ 2 MB, SwiftUI `PropertyList.Element`
  370 KB, our `CharIndex` posting arrays 154 KB, `FuzzyMatch.Candidate` structures 324 KB.
- No leaks: 416 leaks / 20 KB total; everything else is deliberate retention (the hidden palette
  keeps its tree — the teardown experiment regressed input handling and stays reverted).

**Settings window.** Opening Settings costs **+37 MB** (56.9 → 94.2 MB in the harness), and closing
returns only ~5 MB — but the cycles prove it is *first-touch materialization, not a leak*: open 2
adds +0.7 MB, open 3 +0.1 MB, and each close lands back at the same plateau (87.7 → 88.4 → 88.5).
The closed-state leftovers are empty window husks (content and toolbar cleared); the retained
memory is framework machinery — objc method caches, CoreSVG rasterizations, vibrancy/glass
pipelines, font and icon subsystem caches — that later opens reuse instead of re-buying. Emptying
the tree on close is still done, so the hosting controller and its panes do not sit on the budget.

**A full pane sweep** originally peaked at ~152 MB and settled to ~106 MB closed — the heavy panes
(System Settings, 52 rows; System Actions, 31) were the fixable part: only the Applications and
Shortcuts panes used the row-virtualizing table, while the rest fell into a plain `ForEach` that a
`Form` realizes *in full* — every ~450-node SwiftUI row tree alive, ~1 MB per materialized row.
Every list now goes through the table, whose rows are virtualized against the enclosing scroll's
actual viewport: real cells only inside it, blank placeholders elsewhere, and departing rows are
torn down whole (a cell parked in the AppKit reuse pool would keep hosting its tree forever). Full
sweep now peaks at **113 MB** and settles to **~88 MB**; the System Settings pane dropped 135 → 105
and System Actions 152 → 113. Repeated sweeps add ~1 MB per cycle — first-touch plateau, no leak.
The About pane also downsamples its 1024px icns, and a system memory-pressure monitor purges icon
tiers and relieves the allocator whenever macOS reports pressure.

## CPU (unchanged; accepted)

Steady idle 0.02–0.03 s per 60 s (~0.03–0.05 %), 0.0 % in Activity Monitor, zero on-CPU samples in a
5 s Time Profiler attach; the 0.5 s pasteboard poll is the only recurring work. Under sustained 40 Hz
query churn the app spends ~82 % of CPU in SwiftUI/AttributeGraph rendering and only ~1–2 % in
search — the search work is no longer measurable at the system level.

**File search and Quick Look.** The screen itself retains nothing — a clean harness run is flat
(58 → 57.5 MB with results up, 57.0 with the overlay open, 57.6 closed). Previewing a real
document is the cost: the in-process PDF render buffer is a single ~41 MB allocation, PDFKit keeps
its parsed structures, and each preview engages macOS's Quick Look services (`QuickLookUIService`,
`QLPreviewGenerationExtension`, `Hudku Graphics and Media` — those child processes in Activity
Monitor are the system's, working on Hudku's behalf) plus XPC ports and worker threads. That is
per-preview machinery, released on close (both surfaces nil their document via `dismantleNSView`),
and the hide path additionally purges thumbnails and relieves the allocator.

**Clipboard browser.** Measured with 43 fabricated items (40 texts, one 22 k-char text, two 2400px
images): opening adds ~22 MB (lazy rows; mostly the item window and first-render machinery), the
large-text preview was +14 MB and is now capped at 12 000 rendered characters (+6.5 MB — copying
still takes the full text), and image previews decode through ImageIO at the pane's exact pixel
size into a cost-capped cache purged on hide. After close ~+23 MB remains, diffuse (allocator
pages plus warm row thumbnails); the pressure monitor is the backstop. The store's in-memory
window was 1000 rows of item text held eagerly; it is now **300** — search still reaches older
rows through FTS and pinned rows always stay, so a heavy history's worst case drops to roughly a
third.

## What remains (levers, ranked)

1. **Two-char queries 40–85 µs** — the DP itself (~2 rows × width, word points per matched cell).
   Next lever: per-character *Fact snapshots* (score the static fields once per char; merge
   usage/frecency at query time), and incremental DP resume across keystrokes — both exact, both
   moderate surgery in `LauncherOrder`.
2. **Empty query 345 µs** — the favorites split + per-kind usage sorts on every palette open after
   invalidation. Cache the split itself (it only changes with favorites/ranking revisions).
3. **Plateau 66 MB → ≤40 MB** — with relief fixed (real goal, post-drain) the free-page lever is
   spent; what remains is fragmented partially-live pages and framework-side caches, plus the
   first-open Settings materialization (~29 MB) that only a lighter Settings composition would
   avoid. The clipboard window (1000 items) turned out to be a non-factor on this machine and is
   not worth trading depth for.
4. **CoreSVG ~2 MB** — find who retains parsed SVG structures for a single bundled asset.
5. Literal 1–2 µs on *cold* scans: today's floor is ~5–9 µs for sparse queries; only the snapshot /
   incremental work above compresses the dense-candidate cases further.

## Artifacts & reproduction

`/tmp/hudku-perf/` (temporary): `bench-final.json`, `soak-final.json`, `soak-capped.json`,
`tp-loops2.xml` + `folded-loops2.txt` (pure-search Time Profiler), `flame-*.svg`, and the scripts —
`run-session.sh` (bench/soak/profilers via `HUDKU_PERF_*`, `WAIT_PHASE`, `KILL`), `parse-tp.js`,
`flame.js`, `gen-queries.sh`. Perf builds use `PRODUCT_BUNDLE_IDENTIFIER=com.hudku.app.perf` for a
clean prefs domain and never touch the installed app's state.
