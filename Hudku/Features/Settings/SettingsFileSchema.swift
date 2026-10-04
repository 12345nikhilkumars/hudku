import Foundation

/// Where each settings.json key lives; exhaustive, so a new key fails to build until it is bound.
@MainActor
enum SettingsFileSchema {
    static func bindings(settings: AppSettings) -> [SettingsFileBinding] {
        var bindings: [SettingsFileBinding] = []
        for key in SettingsFileKey.allCases {
            bindings.append(binding(for: key, settings: settings))
        }
        return bindings
    }

    private static func binding(
        for key: SettingsFileKey, settings: AppSettings
    ) -> SettingsFileBinding {
        func bind<Root: AnyObject, Value: SettingsFileValue>(
            _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
            accept: @escaping (Value) -> Value? = { $0 }
        ) -> SettingsFileBinding {
            SettingsFileBinding(key, root, path, accept: accept)
        }

        switch key {
        case .popToRootTimeout: return bind(settings, \.popToRootTimeout)
        case .escapeKeyBehavior: return bind(settings, \.escapeKeyBehavior)
        case .autoSwitchInputSource: return bind(settings, \.autoSwitchInputSourceID)
        case .appearance: return bind(settings, \.appearance)
        case .interfaceSize: return bind(settings, \.interfaceSize)
        case .compactMode: return bind(settings, \.compactMode)
        case .showFavoritesInCompactMode: return bind(settings, \.showFavoritesInCompactMode)
        case .openOnCursorScreen: return bind(settings, \.openOnCursorScreen)
        case .paletteDraggable: return bind(settings, \.paletteDraggable)
        case .hyperKey: return bind(settings, \.hyperKey)
        case .hyperKeyIncludesShift: return bind(settings, \.hyperKeyIncludesShift)
        case .hyperKeyQuickPress: return bind(settings, \.hyperKeyQuickPress)
        case .calcNumberStyle: return bind(settings, \.calcNumberStyle)
        case .launcherShowsSuggestions: return bind(settings, \.launcherShowsSuggestions)
        case .rootSearchSensitivity: return bind(settings, \.rootSearchSensitivity)
        case .searchScopes: return bind(settings, \.searchScopes) { SearchScopes.normalize($0) }
        case .appleShortcutsEnabled: return bind(settings, \.appleShortcutsEnabled)
        case .fileSearchEnabled: return bind(settings, \.fileSearchEnabled)
        case .fileSearchScopes: return bind(settings, \.fileSearchScopes)
        case .fileSearchIgnorePatterns: return bind(settings, \.fileSearchIgnorePatterns)
        case .clipboardEnabled: return bind(settings, \.clipboardEnabled)
        case .clipboardRetention: return bind(settings, \.clipboardRetention)
        case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)
        case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)
        case .emojiSkinTone: return bind(settings, \.emojiSkinTone)
        case .emojiGridColumns: return bind(settings, \.emojiGridColumns)
        }
    }
}

extension PopToRootTimeout: SettingsFileRawValue {}
extension EscapeKeyBehavior: SettingsFileRawValue {}
extension AppAppearance: SettingsFileRawValue {}
extension InterfaceSize: SettingsFileRawValue {}
extension HyperKeyPhysicalKey: SettingsFileRawValue {}
extension HyperKeyQuickPress: SettingsFileRawValue {}
extension CalcNumberStyle: SettingsFileRawValue {}
extension SearchSensitivity: SettingsFileRawValue {}
extension ClipboardDefaultAction: SettingsFileRawValue {}
extension EmojiSkinTone: SettingsFileRawValue {}
extension EmojiGridColumns: SettingsFileRawValue {}

extension ClipboardRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .forever: "forever"
        }
    }
}
