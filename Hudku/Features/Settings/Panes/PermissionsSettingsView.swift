import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: accessibilityStatus.symbol)
                                .accessibilityHidden(true)
                            Text(accessibilityStatus.title)
                        }
                        .foregroundStyle(accessibilityStatus.tint)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                            Text("Pastes into the app you were using.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        accessibilityTrusted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
    }
}

private struct PermissionSettingsIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: IconCache.icon(forFile: path))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .id(IconCache.style.generation)
            .frame(
                width: SettingsListMetrics.iconSize,
                height: SettingsListMetrics.iconSize
            )
            .accessibilityHidden(true)
    }
}
