import Darwin
import Foundation

/// gitignore-flavoured: a bare pattern matches any component, one with `/` the path.
struct FileSearchIgnoreList: Sendable, Equatable {
    /// Compiled in, not stored, so changing the shipped rules reaches existing installs.
    /// Hidden trees (`.git`, `.venv`, `.next`, …) are already excluded structurally.
    static let defaults = [
        "node_modules", "DerivedData", "build", "dist", "target", "Pods", "__pycache__",
        "venv", "vendor", "bower_components", "out", "coverage",
        // Development caches and build artifacts: high file counts, low search value.
        "go", "Carthage", "obj", "site-packages", "Packages", ".build",
    ]

    private let literalNames: Set<String>
    private let nameGlobs: [Glob]
    private let pathGlobs: [Glob]
    /// The raw patterns, as configured; the index key hashes these to detect changes.
    let patterns: [String]

    init(patterns: [String]) {
        var literalNames: Set<String> = []
        var nameGlobs: [Glob] = []
        var pathGlobs: [Glob] = []
        var kept: [String] = []
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            // An interior NUL would silently truncate the pattern once it reaches `fnmatch`.
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { continue }
            kept.append(trimmed)
            if trimmed.contains("/") {
                pathGlobs.append(Glob(trimmed))
            } else if trimmed.contains(where: Glob.isMetacharacter) {
                nameGlobs.append(Glob(trimmed))
            } else {
                literalNames.insert(trimmed.lowercased())
            }
        }
        self.literalNames = literalNames
        self.nameGlobs = nameGlobs
        self.pathGlobs = pathGlobs
        self.patterns = kept
    }

    func excludes(path: String) -> Bool {
        for component in path.split(separator: "/") {
            let name = String(component)
            if literalNames.contains(name.lowercased()) { return true }
            if nameGlobs.contains(where: { $0.matches(name) }) { return true }
        }
        return pathGlobs.contains { $0.matches(path) }
    }
}

/// One compiled pattern; `fnmatch` runs without `FNM_PATHNAME`, so `*` spans `/`.
private struct Glob: Sendable, Equatable {
    let pattern: String
    private let terminated: ContiguousArray<CChar>

    init(_ pattern: String) {
        self.pattern = pattern
        terminated = pattern.utf8CString
    }

    static func isMetacharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    func matches(_ candidate: String) -> Bool {
        terminated.withUnsafeBufferPointer { pattern in
            candidate.withCString { fnmatch(pattern.baseAddress!, $0, FNM_CASEFOLD) == 0 }
        }
    }
}
