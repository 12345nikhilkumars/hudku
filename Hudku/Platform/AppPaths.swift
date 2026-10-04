import Foundation

/// The per-channel storage roots. Keyed by bundle id so a Dev build never shares a stable's dirs.
enum AppPaths {
    static func caches(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.hudku.app"
    ) -> URL {
        root(.cachesDirectory, bundleID: bundleID)
    }

    static func applicationSupport(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.hudku.app"
    ) -> URL {
        root(.applicationSupportDirectory, bundleID: bundleID)
    }

    /// `~/.config/hudku/settings.json`; another channel suffixes the folder, as `hudku-dev`.
    static func settingsFile(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.hudku.app"
    ) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: configFolderName(bundleID: bundleID), directoryHint: .isDirectory)
            .appending(path: "settings.json", directoryHint: .notDirectory)
    }

    private static func configFolderName(bundleID: String) -> String {
        let stable = "com.hudku.app"
        if bundleID == stable { return "hudku" }
        guard bundleID.hasPrefix(stable + ".") else { return bundleID }
        return "hudku-" + bundleID.dropFirst(stable.count + 1)
    }

    private static func root(
        _ directory: FileManager.SearchPathDirectory, bundleID: String
    ) -> URL {
        let url = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
