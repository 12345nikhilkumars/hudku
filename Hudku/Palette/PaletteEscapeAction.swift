import Foundation

/// Ordered like a bare backspace: a screen is only left once the search field is empty.
enum PaletteEscapeAction: Equatable {
    case clearMenuQuery
    case closeMenu
    case clearQuery
    case goBack
    case hidePalette

    static func resolve(
        menuOpen: Bool, menuQuery: String, query: String, canGoBack: Bool,
        behavior: EscapeKeyBehavior
    ) -> Self {
        if menuOpen { return menu(query: menuQuery) }
        if !query.isEmpty { return .clearQuery }
        guard behavior == .navigateBackOrClose else { return .hidePalette }
        return canGoBack ? .goBack : .hidePalette
    }

    static func menu(query: String) -> Self {
        query.isEmpty ? .closeMenu : .clearMenuQuery
    }
}
