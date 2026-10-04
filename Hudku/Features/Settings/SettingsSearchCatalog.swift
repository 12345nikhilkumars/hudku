import Foundation

/// One searchable place in Settings: a pane, or a row inside one of its `Form` sections.
struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    /// Where picking this result lands; nil for the pane itself, which is its own result.
    let target: SettingsTarget?
    let title: String
    /// Words a user might type that the visible title doesn't contain.
    let keywords: [String]

    /// Taking the pane from the target is what makes a row filed under the wrong pane unwritable.
    private init(_ target: SettingsTarget, _ title: String, _ keywords: [String]) {
        self.tab = target.tab
        self.target = target
        self.title = title
        self.keywords = keywords
    }

    /// One setting, which its pane marks with a matching `SettingsRowTitle`.
    init(_ anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.row(anchor, title), title, keywords)
    }

    /// A whole group, for a result no single row answers — a list, or a section's master switch.
    init(group anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.section(anchor), title, keywords)
    }

    init(pane: SettingsTab, keywords: [String] = []) {
        self.tab = pane
        self.target = nil
        self.title = pane.title
        self.keywords = keywords
    }

    var anchor: SettingsAnchor? { target?.anchor }

    var id: String { "\(tab.title)/\(anchor?.title ?? "")/\(title)" }

    /// The result row's second line — "General", or "General › Hyper Key".
    var breadcrumb: String {
        guard let anchor, anchor.title != tab.title else { return tab.title }
        return "\(tab.title) › \(anchor.title)"
    }
}

/// What Settings offers to search. Hand-written: a `Form` can't be asked what rows it holds, so a
/// new row is searchable only once it is listed here.
enum SettingsSearchCatalog {
    struct Query: Sendable {
        let terms: [FuzzyMatch.Query]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map {
                FuzzyMatch.Query(String($0))
            }
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func results(for raw: String, limit: Int = 50) -> [SettingsSearchEntry] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        // Catalog order is the tie-break, so results don't reshuffle between equal-scoring rows.
        return
            entries
            .enumerated()
            .compactMap { item -> (entry: SettingsSearchEntry, score: Int, rank: Int)? in
                guard let score = score(query, item.element) else { return nil }
                return (item.element, score, item.offset)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
            .map(\.entry)
    }

    /// Every term must land somewhere; a term matched in the title outranks one found off it.
    private static func score(_ query: Query, _ entry: SettingsSearchEntry) -> Int? {
        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(term, candidate: entry.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard
                entry.keywords.contains(where: { FuzzyMatch.match(term, candidate: $0) != nil })
                    || FuzzyMatch.match(term, candidate: entry.breadcrumb) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        // A pane outranks its own rows, so a bare "clipboard" lands on the pane rather than a row.
        return band + titleScore + (entry.anchor == nil ? 500_000 : 0)
    }

    // MARK: - The index
    // Pane order, then section order within a pane, so this reads as a table of contents.

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings + systemActions + commands
        + appleShortcuts + fallbacks + clipboard + fileSearch + emoji + permissions + about

    private static let general: [SettingsSearchEntry] = [
        .init(pane: .general, keywords: ["preferences", "settings"]),
        .init(
            .generalGlobalShortcuts, "App Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette"]),
        .init(
            .generalGeneral, "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            .generalGeneral, "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            .generalGeneral, "Escape Key Behavior",
            keywords: ["escape", "esc", "back", "close", "navigate"]),
        .init(
            .generalGeneral, "Auto-switch input source",
            keywords: ["keyboard", "layout", "language", "abc"]),
        .init(
            .generalAppearance, "Theme",
            keywords: ["dark", "light", "mode", "appearance"]),
        .init(
            .generalAppearance, "Interface size",
            keywords: ["text size", "font size", "scale", "zoom", "bigger", "larger", "legible"]),
        .init(
            .generalAppearance, "Window mode",
            keywords: ["compact", "expanded", "slim", "search bar", "small"]),
        .init(
            .generalAppearance, "Show favorites in compact mode",
            keywords: ["pinned", "apps", "compact"]),
        .init(
            .generalAppearance, "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            .generalAppearance, "Drag to reposition",
            keywords: ["move", "position", "window"]),
        .init(
            .generalHyperKey, "Hyper Key",
            keywords: ["modifier", "remap", "caps lock", "capslock"]),
        .init(
            .generalHyperKey, "Quick Press",
            keywords: ["tap", "escape", "single press"]),
        .init(
            .generalHyperKey, "Include Shift (⇧)",
            keywords: ["modifier", "chord"]),
        .init(
            .generalCalculator, "Number format",
            keywords: ["decimal", "comma", "separator", "locale", "region", "thousands"]),
        .init(
            .generalSearch, "Show suggestions",
            keywords: ["frequent", "recent", "recommended", "empty", "root search"]),
        .init(
            .generalSearch, "Search sensitivity",
            keywords: ["fuzzy", "strict", "loose", "matching", "typo", "root search"]),
        .init(
            .generalSearch, "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(pane: .applications, keywords: ["apps", "index", "launcher"]),
        .init(
            .applicationsApplications, "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            group: .applicationsSearchScopes, "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            group: .applicationsApplications, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            pane: .systemSettings,
            keywords: ["panes", "preferences", "macos"]),
        .init(
            .systemSettingsSystemSettings, "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let systemActions: [SettingsSearchEntry] = [
        .init(
            pane: .systemActions,
            keywords: ["sleep", "lock", "restart", "shut down", "empty trash"]),
        .init(
            .systemActionsSystemActions, "Enable System Actions",
            keywords: ["hide", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            pane: .commands,
            keywords: ["built-in", "hide", "visibility"]),
        .init(
            .commandsCommands, "Enable Commands",
            keywords: ["hide", "visibility"])
    ]

    private static let appleShortcuts: [SettingsSearchEntry] = [
        .init(pane: .appleShortcuts, keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            .appleShortcutsAppleShortcuts, "Enable Apple Shortcuts",
            keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            group: .appleShortcutsShortcuts, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "hide"])
    ]

    private static let fallbacks: [SettingsSearchEntry] = [
        .init(
            pane: .fallbacks,
            keywords: ["no results", "empty", "order"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            pane: .fileSearch,
            keywords: ["spotlight", "files", "folders", "find"]),
        .init(
            .fileSearchFileSearch, "Enable File Search",
            keywords: ["spotlight", "index"]),
        .init(
            group: .fileSearchCommands, "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            group: .fileSearchSearchScopes, "Search Scopes",
            keywords: ["folders", "locations", "home", "add folder"]),
        .init(
            group: .fileSearchIgnorePatterns, "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            pane: .clipboard,
            keywords: ["paste", "history", "copy", "pasteboard"]),
        .init(
            .clipboardClipboard, "Enable Clipboard History",
            keywords: ["disable", "turn off", "monitor", "record", "privacy"]),
        .init(
            group: .clipboardCommands, "Clipboard commands",
            keywords: ["shortcut", "hotkey", "launcher", "paste", "browser"]),
        .init(
            .clipboardHistory, "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            .clipboardHistory, "Search text in images and PDFs",
            keywords: ["OCR", "recognize", "scan", "screenshot", "background", "idle"]),
        .init(
            .clipboardHistory, "Default action",
            keywords: ["enter", "return", "paste", "copy", "primary"]),
        .init(
            group: .clipboardDisabledApplications, "Disabled Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            .clipboardDisabledApplications, "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let emoji: [SettingsSearchEntry] = [
        .init(
            pane: .emoji,
            keywords: ["picker", "character", "unicode", "smiley"]),
        .init(
            group: .emojiCommands, "Emoji commands",
            keywords: ["shortcut", "hotkey", "launcher", "picker"]),
        .init(
            .emojiAppearance, "Emoji Skin Tone",
            keywords: ["colour", "color", "fitzpatrick", "default"]),
        .init(
            .emojiAppearance, "Column Count",
            keywords: ["columns", "density", "zoom", "six", "eight", "ten"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            pane: .permissions,
            keywords: ["privacy", "tcc", "access", "grant"]),
        .init(
            .permissionsAccessibility, "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            pane: .about,
            keywords: ["version", "licence", "license", "credits"])
    ]
}
