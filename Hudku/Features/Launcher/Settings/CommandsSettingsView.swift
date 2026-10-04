import SwiftUI

/// The Commands pane: the built-in catalog's rows, each hideable or bindable like an app.
struct CommandsSettingsView: View {
    var body: some View {
        Form {
            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
    }
}
