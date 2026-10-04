import AppKit
import SwiftUI

struct AboutView: View {
    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    // Cached, and read from the bundle: the app icon is generic until LaunchServices registers.
    @MainActor private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()

    private static let iconSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    hero
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                }
                .settingsAnchor(.aboutAbout)
            }
            .formStyle(.grouped)
            .settingsScrollTarget(.about)

            // Outside the form, so the copyright stays pinned to the bottom edge.
            footer
                .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Bundle.main.appDisplayName)
                    .font(.title.weight(.bold))
                Text(Self.version)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .background(
                        Capsule().fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("A tiny, native macOS launcher.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        Text("Released under AGPL-3.0")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
