import Foundation

/// Every key settings.json holds, in the order the file lists them; the raw value is its path.
enum SettingsFileKey: String, CaseIterable, Sendable {
    // Spelled out, so renaming a case can never rename a key in someone's file.
    case popToRootTimeout = "general.popToRootSeconds"
    case escapeKeyBehavior = "general.escapeKeyBehavior"
    case autoSwitchInputSource = "general.autoSwitchInputSource"
    case appearance = "appearance.theme"
    case interfaceSize = "appearance.interfaceSize"
    case compactMode = "appearance.compactMode"
    case showFavoritesInCompactMode = "appearance.showFavoritesInCompactMode"
    case openOnCursorScreen = "appearance.followCursorAcrossDisplays"
    case paletteDraggable = "appearance.dragToReposition"
    case hyperKey = "hyperKey.key"
    case hyperKeyIncludesShift = "hyperKey.includesShift"
    case hyperKeyQuickPress = "hyperKey.quickPress"
    case calcNumberStyle = "calculator.numberStyle"
    case launcherShowsSuggestions = "search.showsSuggestions"
    case rootSearchSensitivity = "search.sensitivity"
    case searchScopes = "applications.searchScopes"
    case appleShortcutsEnabled = "appleShortcuts.enabled"
    case fileSearchEnabled = "fileSearch.enabled"
    case fileSearchScopes = "fileSearch.scopes"
    case fileSearchIgnorePatterns = "fileSearch.ignorePatterns"
    case clipboardEnabled = "clipboard.enabled"
    case clipboardRetention = "clipboard.retentionDays"
    case clipboardDefaultAction = "clipboard.defaultAction"
    case clipboardDisabledApps = "clipboard.disabledApps"
    case emojiSkinTone = "emoji.skinTone"
    case emojiGridColumns = "emoji.gridColumns"

    /// The top-level object the key sits in.
    var section: String { String(rawValue.prefix { $0 != "." }) }

    /// The key's name inside its section.
    var name: String { String(rawValue.drop { $0 != "." }.dropFirst()) }

    /// Every section, in file order.
    static let sections: [String] = allCases.reduce(into: []) { sections, key in
        if sections.last != key.section { sections.append(key.section) }
    }
}
