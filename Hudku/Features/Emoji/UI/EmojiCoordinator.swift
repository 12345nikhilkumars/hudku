import AppKit

/// Owns emoji delivery: frequency tallies the base glyph, the configured tone applies at copy time.
@MainActor
final class EmojiCoordinator {
    private let frequentEmoji: FrequentEmojiStore
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator

    init(
        frequentEmoji: FrequentEmojiStore,
        settings: AppSettings,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.frequentEmoji = frequentEmoji
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
    }

    /// Copy only: an emoji never needs a synthetic keystroke, so nothing here touches Accessibility.
    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }
}
