import SwiftUI

@main
struct HudkuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // Channel-aware: "Hudku", "Hudku Dev", or "Hudku Beta".
    private let appName = Bundle.main.appDisplayName

    /// The palette and every other window is AppKit-managed; this scene exists so the app menu
    /// commands have somewhere to live.
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands { appMenuCommands }
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var appMenuCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Window") {
                AppCore.shared.settingsCoordinator.closeSettings()
            }
            .keyboardShortcut("q")
        }
    }
}
