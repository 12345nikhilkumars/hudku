import SwiftUI

/// Delay before a closed palette pops to root; an unset key reads as `.immediately`.
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// What `AppIndex` scans, in scan order; editing it re-indexes, being observed.
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    var launcherShowsSuggestions: Bool {
        didSet {
            defaults.set(launcherShowsSuggestions, forKey: Key.launcherShowsSuggestions.rawValue)
        }
    }

    /// How loose a fuzzy root-search hit may be and still show.
    var rootSearchSensitivity: SearchSensitivity {
        didSet {
            defaults.set(rootSearchSensitivity.rawValue, forKey: Key.rootSearchSensitivity.rawValue)
        }
    }

    /// Ships on, unlike every other feature switch: a launcher is expected to keep history.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardTextSearchEnabled: Bool {
        didSet { defaults.set(clipboardTextSearchEnabled, forKey: Key.clipboardTextSearchEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    /// Bundle IDs never recorded from; ordered, so the Settings list stays stable.
    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    /// What ↵ does on a clipboard entry; Paste takes the chord the chosen action leaves free.
    var clipboardDefaultAction: ClipboardDefaultAction {
        didSet {
            defaults.set(
                clipboardDefaultAction.rawValue, forKey: Key.clipboardDefaultAction.rawValue)
        }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The physical key remapped to the Hyper chord; `HyperKeyTap` reacts via its observer.
    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey.rawValue) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet {
            defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress.rawValue)
        }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone.rawValue) }
    }

    /// Grid density used when the emoji picker opens; in-session zoom remains temporary.
    var emojiGridColumns: EmojiGridColumns {
        didSet { defaults.set(emojiGridColumns.rawValue, forKey: Key.emojiGridColumns.rawValue) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }

    /// Whether Escape walks back through the screens the palette opened, or just closes it.
    var escapeKeyBehavior: EscapeKeyBehavior {
        didSet { defaults.set(escapeKeyBehavior.rawValue, forKey: Key.escapeKeyBehavior.rawValue) }
    }

    /// Follow macOS, or pin Hudku to one appearance. Applied by `AppCore.applyAppearance()`.
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    /// Which separators the calculator reads and writes; `.system` follows Language & Region.
    var calcNumberStyle: CalcNumberStyle {
        didSet { defaults.set(calcNumberStyle.rawValue, forKey: Key.calcNumberStyle.rawValue) }
    }

    /// Scales the palette and its floating siblings only. Read through `InterfaceSize.metrics`.
    var interfaceSize: InterfaceSize {
        didSet {
            defaults.set(interfaceSize.rawValue, forKey: Key.interfaceSize.rawValue)
            let shift = Double(
                (oldValue.metrics.size.panelWidth - interfaceSize.metrics.size.panelWidth) / 2)
            if shift != 0 {
                palettePositions = palettePositions.mapValues { offset in
                    offset.count == 2 ? [offset[0] + shift, offset[1]] : offset
                }
            }
        }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    var showFavoritesInCompactMode: Bool {
        didSet {
            defaults.set(
                showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode.rawValue)
        }
    }

    /// Summon the palette on the display under the pointer instead of the one holding the menu bar.
    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    /// Lets the panel be dragged by its top edge; off by default, so most launches never grab it.
    var paletteDraggable: Bool {
        didSet { defaults.set(paletteDraggable, forKey: Key.paletteDraggable.rawValue) }
    }

    /// Where a drag left the panel's top-left, per display and relative to it.
    var palettePositions: [String: [Double]] {
        didSet { defaults.set(palettePositions, forKey: Key.palettePosition.rawValue) }
    }

    var paletteExpandedCenterDisplays: Set<String> {
        didSet {
            defaults.set(
                Array(paletteExpandedCenterDisplays),
                forKey: Key.paletteExpandedCenterDisplays.rawValue)
        }
    }

    func palettePosition(on display: String) -> CGPoint? {
        palettePositions[display].flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    func setPalettePosition(_ offset: CGPoint?, on display: String, expandedCenter: Bool) {
        if offset != nil && expandedCenter {
            paletteExpandedCenterDisplays.insert(display)
        } else {
            paletteExpandedCenterDisplays.remove(display)
        }
        guard let offset else {
            palettePositions.removeValue(forKey: display)
            return
        }
        palettePositions[display] = [offset.x, offset.y]
    }

    // Feature switches, off out of the box, and off means fully off.
    var fileSearchEnabled: Bool {
        didSet { defaults.set(fileSearchEnabled, forKey: Key.fileSearchEnabled.rawValue) }
    }

    /// Tilde-abbreviated, so a backup taken on one machine still points somewhere on another.
    var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Key.fileSearchScopes.rawValue) }
    }

    /// Only what the user added; the shipped rules are compiled into `FileSearchIgnoreList`.
    var fileSearchIgnorePatterns: [String] {
        didSet {
            defaults.set(fileSearchIgnorePatterns, forKey: Key.fileSearchIgnorePatterns.rawValue)
        }
    }

    /// Off means the Shortcuts tool is never run, down to a bound shortcut running nothing.
    var appleShortcutsEnabled: Bool {
        didSet { defaults.set(appleShortcutsEnabled, forKey: Key.appleShortcutsEnabled.rawValue) }
    }

    /// Whether settings.json mirrors these settings; `AppCore` starts and stops the mirror.
    var settingsFileEnabled: Bool {
        didSet { defaults.set(settingsFileEnabled, forKey: Key.settingsFileEnabled.rawValue) }
    }

    init() {
        // The only feature switch that defaults on, so absence has to outrank a stored `false`.
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        // `integer(forKey:)` returns 0 when unset, which no case matches.
        clipboardTextSearchEnabled = defaults.bool(forKey: Key.clipboardTextSearchEnabled.rawValue)
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        // Password managers ship excluded, until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardDefaultAction =
            defaults.string(forKey: Key.clipboardDefaultAction.rawValue)
            .flatMap(ClipboardDefaultAction.init) ?? .paste
        launchAtLogin = LaunchAtLogin.isEnabled
        hyperKey =
            defaults.string(forKey: Key.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init)
            ?? .none
        // Defaults to true, so absence must be distinguished from a stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress.rawValue)
            .flatMap(HyperKeyQuickPress.init)
            ?? .none
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        emojiGridColumns =
            EmojiGridColumns(rawValue: defaults.integer(forKey: Key.emojiGridColumns.rawValue))
            ?? .default
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        escapeKeyBehavior =
            defaults.string(forKey: Key.escapeKeyBehavior.rawValue).flatMap(EscapeKeyBehavior.init)
            ?? .navigateBackOrClose
        appearance =
            defaults.string(forKey: Key.appearance.rawValue).flatMap(AppAppearance.init) ?? .system
        calcNumberStyle =
            defaults.string(forKey: Key.calcNumberStyle.rawValue).flatMap(CalcNumberStyle.init)
            ?? .system
        interfaceSize =
            defaults.string(forKey: Key.interfaceSize.rawValue).flatMap(InterfaceSize.init)
            ?? .standard
        compactMode = defaults.bool(forKey: Key.compactMode.rawValue)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode.rawValue) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode.rawValue)
        // Unset seeds the defaults; a stored empty array is a deliberately cleared list.
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        launcherShowsSuggestions =
            defaults.object(forKey: Key.launcherShowsSuggestions.rawValue) == nil
            || defaults.bool(forKey: Key.launcherShowsSuggestions.rawValue)
        rootSearchSensitivity =
            defaults.string(forKey: Key.rootSearchSensitivity.rawValue)
            .flatMap(SearchSensitivity.init) ?? .default
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen.rawValue)
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        paletteDraggable = defaults.bool(forKey: Key.paletteDraggable.rawValue)
        palettePositions =
            defaults.dictionary(forKey: Key.palettePosition.rawValue)
            as? [String: [Double]] ?? [:]
        paletteExpandedCenterDisplays =
            Set(defaults.stringArray(forKey: Key.paletteExpandedCenterDisplays.rawValue) ?? [])
        fileSearchEnabled = defaults.bool(forKey: Key.fileSearchEnabled.rawValue)
        // Unset seeds home; a stored empty array is a cleared list that searches nothing.
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        appleShortcutsEnabled = defaults.bool(forKey: Key.appleShortcutsEnabled.rawValue)
        settingsFileEnabled = defaults.bool(forKey: Key.settingsFileEnabled.rawValue)
    }
}
