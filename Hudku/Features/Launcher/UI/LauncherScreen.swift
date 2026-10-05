import SwiftUI

/// The root search: favorites, suggestions, then one section per kind, led by any card.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so Restart and Quit can't move while the menu is up.
    let running: Bool
    let openActions: () -> Void
    /// Called when an action reorders the list, so the highlight scrolls back into view.
    let scrollToFollow: () -> Void

    /// The one ordered result list; an empty query pins favorites above the ranked matches.
    private let results: [AppEntry]
    private let calc: CalcResult?
    /// The colour the query itself spells, if it spells one; nil for every other query.
    private let color: ColorValue?
    /// Sections stand in for the ranked Results list, which a typed query collapses to.
    private let showSections: Bool
    /// Only the empty query pins favorites - a category shows its sections without one of its own.
    private let pinsFavorites: Bool
    /// How many of `results` are pinned favorites; zero unless the section shows.
    private let favoriteCount: Int
    /// How many follow the favorites as Suggestions; zero unless the field is empty.
    private let suggestionCount: Int
    /// `@word` typed in root search: files and folders under the search scopes, by name.
    private let fileTerm: String?
    private let fileMatches: [FileSearchResult]
    /// `:smile` typed in root search: Slack/Discord-style emoji matches, answered from the index.
    private let emojiMatches: [EmojiEntry]
    /// `def word` typed in root search: the dictionary page fills the palette in place.
    private let definitionTerm: String?
    private let dictionaryMatch: DictionaryEntry?
    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [Row]

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        openActions: @escaping () -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.openActions = openActions
        self.scrollToFollow = scrollToFollow

        let ordered = appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
        var results = ordered.entries
        // A typed web address leads: nothing the index holds answers it better.
        if let browser = CommandCatalog.openInBrowser(for: vm.query),
            visibility.isVisible(browser)
        {
            results.insert(browser, at: 0)
        }
        let calc = CalcMemo.evaluate(vm.query, rates: currencyRates.rates, format: core.calcNumberFormat)
        // After the calculator: `#FF5733` is never arithmetic, so the two can't both answer.
        let color = calc == nil ? ColorValue.parse(vm.query) : nil
        let fileTerm = core.settings.fileSearchEnabled ? Self.fileSearchTerm(in: vm.query) : nil
        // The session publishes whatever it last ran; only its own term's results are answers.
        let fileMatches: [FileSearchResult] =
            fileTerm.flatMap { term in
                core.fileSearch.publishedQuery == term ? core.fileSearch.results : nil
            } ?? []
        let emojiTerm = Self.emojiSearchTerm(in: vm.query)
        let emojiMatches = emojiTerm.map { term in
            // A bare `:` opens the section with favourites first, then the top of the catalog -
            // the way Slack and Discord list something before a letter is typed.
            term.isEmpty ? Self.defaultEmoji(core: core) : core.emojiIndex.search(
                term, frequent: core.frequentEmoji, limit: 7)
        } ?? []
        let definitionTerm = Self.definitionTerm(in: vm.query)
        let dictionaryMatch = definitionTerm.flatMap { term in
            core.dictionary.lookup.flatMap { $0.term == term ? $0.entry : nil }
        }
        let entries = results.map(Row.entry)
        let pinsFavorites = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        self.results = results
        self.calc = calc
        self.color = color
        self.fileTerm = fileTerm
        self.fileMatches = fileMatches
        self.emojiMatches = emojiMatches
        self.definitionTerm = definitionTerm
        self.dictionaryMatch = dictionaryMatch
        self.showSections = pinsFavorites || AppEntry.Kind.named(by: vm.query) != nil
        self.pinsFavorites = pinsFavorites
        self.favoriteCount = pinsFavorites ? ordered.favoriteCount : 0
        self.suggestionCount = pinsFavorites ? ordered.suggestionCount : 0
        if let dictionaryMatch {
            self.rows = [.definition(dictionaryMatch)]
        } else if definitionTerm != nil, core.dictionary.lookup?.term == definitionTerm {
            // The term resolved to nothing: the page states that instead of copying a blank.
            self.rows = []
        } else if fileTerm != nil, fileMatches.isEmpty {
            // Until the search lands (or when it finds nothing) the files are the whole answer.
            self.rows = []
        } else {
            var rows = emojiMatches.map(Row.emoji)
            if let calc {
                rows = [.calc(calc)] + rows
            } else if let color {
                rows = [.color(color)] + rows
            }
            self.rows = fileMatches.map(Row.file) + rows + entries
        }
    }

    // MARK: - Keyword syntaxes

    /// `:`, `:smile` or `:smile:` - the emoji requested by name, the Discord/Slack way.
    static func emojiSearchTerm(in query: String) -> String? {
        guard query.hasPrefix(":") else { return nil }
        var term = query.dropFirst()
        if term.hasSuffix(":") { term = term.dropLast() }
        return term.trimmingCharacters(in: .whitespaces)
    }

    /// What a bare `:` lists: the reader's own favourites first, then the catalog's head.
    private static func defaultEmoji(core: AppCore, limit: Int = 7) -> [EmojiEntry] {
        var picked: [EmojiEntry] = []
        var seen = Set<String>()
        for glyph in core.frequentEmoji.top() {
            guard picked.count < limit else { break }
            guard let entry = core.emojiIndex.entry(for: glyph), seen.insert(entry.glyph).inserted
            else { continue }
            picked.append(entry)
        }
        for section in core.emojiIndex.categorySections {
            guard picked.count < limit else { break }
            for entry in section.entries where seen.insert(entry.glyph).inserted {
                picked.append(entry)
                if picked.count == limit { break }
            }
        }
        return picked
    }

    /// `@word` / `?word` - a file or folder under the search scopes, by name.
    static func fileSearchTerm(in query: String) -> String? {
        guard let first = query.first, first == "@" || first == "?" else { return nil }
        let term = query.dropFirst().trimmingCharacters(in: .whitespaces)
        return term.isEmpty ? nil : term
    }

    /// `def word` / `define:word` - the word to look up, said outright.
    static func definitionTerm(in query: String) -> String? {
        guard let first = query.first, first == "d" || first == "D" else { return nil }
        let lowered = query.lowercased()
        for prefix in ["def ", "define ", "def:", "define:"] {
            guard lowered.hasPrefix(prefix) else { continue }
            let term = query.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return term.isEmpty ? nil : term
        }
        return nil
    }

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case color(ColorValue)
        case file(FileSearchResult)
        case emoji(EmojiEntry)
        case definition(DictionaryEntry)
        case entry(AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .color: return "color-card"
            case .file(let result): return "file-" + result.id
            case .emoji(let entry): return "emoji-" + entry.glyph
            case .definition(let entry): return "definition-" + entry.term
            case .entry(let app): return app.id
            }
        }
    }

    /// The pill carries no selection, so the screen applies the clamp the palette applies.
    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    var primaryActionTitle: String {
        switch row(at: clampedSelection) {
        case .calc: return "Copy Answer"
        case .color: return "Copy Color"
        case .file(let result): return result.isDirectory ? "Open Folder" : "Open File"
        case .emoji: return "Copy Emoji"
        case .definition: return "Copy Definition"
        case .entry(let app): return app.kind.descriptor.openVerb
        case nil: return "Open Application"
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .color, .definition: return true
        case .file, .emoji, .entry, nil: return false
        }
    }

    /// Whichever card leads, in the terms the list draws it in.
    private var leadCard: LauncherList.LeadCard? {
        if let calc { return .calc(calc) }
        if let color { return .color(color) }
        return nil
    }

    /// An error card is selectable but has no action: it must drive neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .color(let color):
            return ColorActionsMenu.content(color: color, core: core)
        case .file(let result):
            return FileSearchActionsMenu.content(
                result: result, core: core, target: vm.pasteTarget)
        case .emoji:
            return nil
        case .definition(let entry):
            return PopoverMenuContent(
                header: entry.term,
                items: [
                    PopoverMenuItem(
                        title: "Copy Definition", systemImage: "doc.on.doc", shortcut: "↵"
                    ) {
                        core.dictionaryCoordinator.copy(entry)
                    },
                    PopoverMenuItem(
                        title: "Open in Dictionary", systemImage: "book", shortcut: "⌘↵"
                    ) {
                        core.dictionaryCoordinator.openInDictionary(entry)
                    }
                ])
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                favorites: favoriteActions(for: app, at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // Reset can move the item; keep the highlight on the item whose action ran.
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // Error cards no-op - copyCalculatorResult only acts on value payloads.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .color(let color):
            core.clipboardCoordinator.copyColor(color, as: ColorFormat.primary(for: color))
        case .file(let result): core.fileSearchCoordinator.open(result)
        case .emoji(let entry): core.emojiCoordinator.copyEmoji(entry)
        case .definition(let entry): core.dictionaryCoordinator.copy(entry)
        case .entry(let app):
            core.launcherCoordinator.launch(app, searchQuery: vm.query)
        case nil: break
        }
    }

    /// ⌘↵ - the definition opens in Dictionary itself; a file shows in Finder; an app reveals.
    func secondary(at selection: Int) -> Bool {
        if case .definition(let entry) = row(at: selection) {
            core.dictionaryCoordinator.openInDictionary(entry)
            return true
        }
        if case .file(let result) = row(at: selection) {
            core.fileSearchCoordinator.showInFinder(result)
            return true
        }
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    /// An emoji answer has no menu: Enter copies, and that is the whole contract.
    func hasActions(at selection: Int) -> Bool {
        if case .emoji = row(at: selection) { return false }
        return true
    }

    /// Offered only for an `.application` entry `RunningAppsMonitor` reports running.
    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .toggleFavorite: return toggleFavorite(at: selection)
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit, .forceQuit: return quit(at: selection, force: shortcut == .forceQuit)
        case .restart: return restart(at: selection)
        case .favoriteSlot(let index): return launchFavorite(at: index)
        case .copyCalculation: return copyCalculation(at: selection)
        default: return false
        }
    }

    private func copyCalculation(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection), result.isActionable else { return false }
        core.calculatorCoordinator.copyCalculationWithExpression(result)
        return true
    }

    /// ⌃⇧Q or ⌃⌥⇧Q - the screen owns the chord, but only a running app has anything to quit.
    private func quit(at selection: Int, force: Bool) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app, force: force)
        return true
    }

    /// ⌘R - mirrors the Restart Application row.
    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    /// The highlight stays in Favorites: the top on add, the neighbour above on remove.
    private func toggleFavorite(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app) else { return false }
        let removed = favoriteIndex(of: app)
        favorites.toggle(app)
        // A typed query pins no favorites, so nothing moved and the highlight stays.
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    /// ⌘1–⌘9/⌘0 - launch a favorite by position, in either palette size.
    private func launchFavorite(at index: Int) -> Bool {
        guard let app = pinnedFavorites.dropFirst(index).first else { return false }
        core.launcherCoordinator.launch(app)
        return true
    }

    /// Empty while a query is typed, the only state in which the section is off screen.
    private var pinnedFavorites: ArraySlice<AppEntry> { results.prefix(favoriteCount) }

    /// ⌥⌘↑/↓ - swap with the neighbouring favorite; the ends of the section have nowhere to go.
    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let app = entry(at: selection), let index = favoriteIndex(of: app) else { return false }
        let target = index + delta
        guard target >= 0, target < favoriteCount else { return false }
        favorites.exchange(favorites.key(for: app), with: favorites.key(for: results[target]))
        follow(app)
        return true
    }

    /// The ends drop the move they can't run; both rows call back here, never drifting.
    private func favoriteActions(
        for app: AppEntry, at selection: Int
    )
        -> AppActionsMenu.FavoriteActions
    {
        let index = favoriteIndex(of: app)
        return AppActionsMenu.FavoriteActions(
            isFavorite: favorites.isFavorite(app),
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < favoriteCount - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    /// Position inside the Favorites section, or nil when the entry isn't reorderable there.
    private func favoriteIndex(of app: AppEntry) -> Int? {
        guard let index = results.firstIndex(of: app), index < favoriteCount else { return nil }
        return index
    }

    /// ⇧⌘H - the row leaves the list for good, so the highlight takes the place it vacated.
    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canHideFromSearch,
            !CommandCatalog.isQueryDriven(app), let index = results.firstIndex(of: app)
        else { return false }
        visibility.setItemVisible(false, for: app)
        select(row: min(index, max(reorderedResults().entries.count - 1, 0)))
        return true
    }

    /// The list reorders under an action; keep the highlight and the scroll on the row that moved.
    private func follow(_ app: AppEntry) {
        guard let index = reorderedResults().entries.firstIndex(of: app) else { return }
        select(row: index)
    }

    /// Highlight a row of the Favorites section, clamped into what the section now holds.
    private func selectFavorite(at index: Int) {
        let count = reorderedResults().favoriteCount
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    /// Re-read the order the change just invalidated; this warms the key the next render reads.
    private func reorderedResults() -> AppIndex.Results {
        appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
    }

    private func select(row index: Int) {
        vm.selection = index + (leadCard == nil ? 0 : 1)
        scrollToFollow()
    }

    /// The sample `openActions` takes; only an app row can ever carry the running-only actions.
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    /// The compact bar's icons: the first five favorites. The "…" that follows them is not one.
    var compactFavorites: [AppEntry] { Array(pinnedFavorites.prefix(5)) }

    /// Whether the compact bar's "…" has anything to reveal.
    var hasUnshownFavorites: Bool { favoriteCount > compactFavorites.count }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if let dictionaryMatch {
            DictionaryEntryView(entry: dictionaryMatch)
        } else if let definitionTerm, core.dictionary.lookup?.term == definitionTerm {
            EmptyResults(text: "No definition found")
        } else if let fileTerm, fileMatches.isEmpty {
            if core.fileSearch.publishedQuery == fileTerm {
                EmptyResults(text: "No files found")
            } else {
                // The search is still running; an empty list would only flash a message.
                Color.clear
            }
        } else {
        LauncherList(
            results: results,
            selectedRowID: row(at: selection)?.id,
            favoriteCount: favoriteCount,
            suggestionCount: suggestionCount,
            showSections: showSections,
            scroll: scroll,
            card: leadCard,
            cardSelected: isCardSelected(selection),
            onActivateCard: {
                vm.selection = 0
                activate(at: 0)
            },
            onCardActions: {
                guard hasPrimaryAction(at: 0) else { return }
                vm.selection = 0
                openActions()
            },
            onActivate: {
                core.launcherCoordinator.launch($0, searchQuery: vm.query)
            },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            },
            onDropped: { core.paletteCoordinator.dragLanded() },
            fileMatches: fileMatches,
            onFileActivate: { core.fileSearchCoordinator.open($0) },
            onFileActions: { result in
                if let index = rows.firstIndex(of: .file(result)) { vm.selection = index }
                openActions()
            },
            emojiMatches: emojiMatches,
            onEmojiActivate: { core.emojiCoordinator.copyEmoji($0) },
            onEmojiActions: { entry in
                if let index = rows.firstIndex(of: .emoji(entry)) { vm.selection = index }
                openActions()
            }
        )
        }
    }
}
