import AppKit

/// Owns launcher activation: the one funnel from a palette row to whatever the entry's kind runs.
@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let systemActionCoordinator: SystemActionCoordinator
    private let fileSearchCoordinator: FileSearchCoordinator
    /// The commands that reach beyond this type's own collaborators: camera, updates, and quit.
    private unowned let core: AppCore

    init(
        ranking: LauncherRankingStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        systemActionCoordinator: SystemActionCoordinator,
        fileSearchCoordinator: FileSearchCoordinator,
        core: AppCore
    ) {
        self.ranking = ranking
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.systemActionCoordinator = systemActionCoordinator
        self.fileSearchCoordinator = fileSearchCoordinator
        self.core = core
    }

    // MARK: - Activation

    func launch(
        _ app: AppEntry, searchQuery: String? = nil, arguments: [String: String] = [:]
    ) {
        // A category word is no search for the row: learning it would rank the row under "s".
        if !CommandCatalog.isQueryDriven(app) {
            let term = searchQuery.flatMap { AppEntry.Kind.named(by: $0) == nil ? $0 : nil }
            ranking.visit(itemKey: app.preferenceKey, query: term)
        }
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if app.kind == .command {
            guard let id = CommandCatalog.command(for: app) else { return }
            // Query-driven: only this row knows the URL the typed text resolved to.
            if id == .openInBrowser {
                paletteCoordinator.hidePalette(restoreFocus: false)
                AppLauncher.open(app.url)
                return
            }
            runCommand(id)
            return
        }
        if app.kind == .systemAction {
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActionCoordinator.runSystemAction(id: action.id)
            return
        }
        if app.kind == .appleShortcut {
            guard let id = AppleShortcut.id(fromEntryID: app.id) else { return }
            core.appleShortcutCoordinator.run(id: id)
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command, .systemAction, .appleShortcut:
            break  // handled above
        }
    }

    /// The one funnel a built-in command runs through, from a palette row or its global shortcut.
    func runCommand(_ id: CommandID) {
        switch id {
        case .calculatorHistory:
            paletteCoordinator.togglePalette(mode: .calculatorHistory)
        case .clipboardHistory:
            paletteCoordinator.togglePalette(mode: .clipboard)
        case .pasteSequentially:
            core.clipboardCoordinator.pasteNextInSequence()
        case .searchEmoji:
            paletteCoordinator.togglePalette(mode: .emoji)
        case .searchFiles:
            fileSearchCoordinator.show()
        case .openCamera:
            dismissPalette()
            Task { await core.cameraCoordinator.show() }
        case .define:
            core.dictionaryCoordinator.show()
        case .openInBrowser:
            break  // Query-driven: each runs where the typed text is, never through this funnel.
        case .settings:
            dismissPalette()
            settingsCoordinator.showSettings()
        case .about:
            dismissPalette()
            settingsCoordinator.showAbout()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// A shortcut runs these with nothing open, where a plain hide would still reset palette state.
    private func dismissPalette() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    // MARK: - Row actions

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func showInFinder(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    /// Focus is never handed back: the relaunch takes it, or the app that refused has it.
    func restart(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.restart(bundleID: bundleID, url: app.url) }
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry, force: Bool = false) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Nothing here takes focus, so hand it back unless that app is on its way out.
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID, force: force) else { return }
        paletteCoordinator.hidePalette(restoreFocus: !quittingPreviousApp)
    }
}
