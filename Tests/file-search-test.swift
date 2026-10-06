import Foundation
import UniformTypeIdentifiers

@main
struct FileSearchTests {
    nonisolated(unsafe) static var failures = 0
    static let home = URL(fileURLWithPath: "/Users/test")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func result(_ path: String, folder: Bool = false) -> FileSearchResult {
        FileSearchResult(url: home.appending(path: path), isDirectory: folder, homeDirectory: home)
    }

    static func main() {
        queryGrammar()
        typeFilter()
        scopePolicy()
        pathPolicy()
        ignoreRules()
        policyResolution()
        resultModel()
        ranking()
        indexTable()

        print(failures == 0 ? "File search tests passed" : "\(failures) file search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func queryGrammar() {
        expect(
            FileSearchQuery.terms(in: "  annual\treport  ") == ["annual", "report"],
            "terms split on whitespace")
        expect(FileSearchQuery.candidateLimit == 400, "the candidate cap is fixed")
        expect(FileSearchQuery.resultLimit == 200, "the displayed result cap is fixed")
        expect(
            FileSearchQuery.matches(filename: "Résumé Final.pdf", query: "resume final"),
            "matching is case- and diacritic-insensitive")
        expect(
            !FileSearchQuery.matches(filename: "Annual Notes.pdf", query: "annual report"),
            "every term is required for a match")
    }

    static func typeFilter() {
        expect(
            FileSearchFilter.documents.contentTypes.contains(.pdf),
            "Documents names PDF outright, not only through conformance")
        expect(FileSearchFilter.all.contentTypes.isEmpty, "All Types constrains nothing")

        expect(
            FileSearchFilter.all.accepts(contentType: nil, isDirectory: false),
            "All Types admits a file whose type never resolved")
        expect(
            FileSearchFilter.folders.accepts(contentType: .folder, isDirectory: true)
                && FileSearchFilter.folders.accepts(contentType: nil, isDirectory: true),
            "Folders admits a directory whether or not its type resolved")
        expect(
            !FileSearchFilter.folders.accepts(contentType: .png, isDirectory: false),
            "Folders rejects a file")
        expect(
            FileSearchFilter.images.accepts(contentType: .png, isDirectory: false)
                && !FileSearchFilter.images.accepts(contentType: .mp3, isDirectory: false),
            "a type filter admits what conforms to it and nothing else")
        expect(
            FileSearchFilter.documents.accepts(contentType: .swiftSource, isDirectory: false),
            "source files conform to public.text, so Documents keeps them")
        expect(
            !FileSearchFilter.images.accepts(contentType: nil, isDirectory: false),
            "an unresolved type is a folder or nothing, never a guessed image")
    }

    static func scopePolicy() {
        func candidate(
            _ name: String, directory: Bool, hidden: Bool = false, package: Bool = false,
            type: UTType? = nil
        ) -> FileSearchScope.Candidate {
            FileSearchScope.Candidate(
                url: home.appending(path: name), isDirectory: directory, isHidden: hidden,
                isPackage: package, contentType: type)
        }
        let selection = FileSearchScope.select([
            candidate("Documents", directory: true),
            candidate("Developer", directory: true),
            candidate("Library", directory: true),
            candidate(".cache", directory: true, hidden: true),
            candidate("Project.xcodeproj", directory: true, package: true),
            candidate("Local.app", directory: true, package: true, type: .application),
            candidate("Notes.txt", directory: false)
        ])
        expect(
            selection.directories.map(\.lastPathComponent) == ["Documents", "Developer"],
            "only visible non-package directories become recursive Spotlight scopes")
        expect(
            selection.rootItems.map(\.url.lastPathComponent)
                == ["Documents", "Developer", "Project.xcodeproj", "Notes.txt"],
            "visible root folders, files and document packages remain direct candidates")
    }

    static func pathPolicy() {
        let shipped = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults)
        for directory in FileSearchIgnoreList.defaults {
            expect(
                FileSearchQuery.isExcludedPath(
                    "/Users/test/Documents/App/\(directory)/file.txt", ignoring: shipped),
                "\(directory) descendants are excluded")
        }
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/App/.git/config", ignoring: shipped),
            "hidden ancestor paths are excluded")
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/Applications/Example.app/Contents/Info.plist", ignoring: shipped),
            "application-bundle contents are excluded")
        expect(
            !FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/Building Plans/target-notes.txt", ignoring: shipped),
            "partial directory-name matches remain searchable")
        expect(
            !FileSearchQuery.isExcludedPath("/Users/test/Documents/Pods.txt", ignoring: shipped),
            "an excluded directory spelling is still valid as a filename")
        expect(
            !FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "an empty list still leaves the structural rules in place")
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/.hidden/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "hidden paths are structural, not a pattern the user can drop")
    }

    static func ignoreRules() {
        let list = FileSearchIgnoreList(patterns: [
            "*.tmp", "**/[Cc]ache/**", "**/build-output/**", "Archive", "  ", "with\0nul"
        ])
        expect(list.excludes(path: "/Users/test/Documents/notes.TMP"), "a name glob folds case")
        expect(
            list.excludes(path: "/Users/test/Documents/scratch.tmp/keep.txt"),
            "a name glob matches at any depth, not only the last component")
        expect(
            list.excludes(path: "/Users/test/Developer/Cache/blob"),
            "a path glob matches a bracketed alternative")
        expect(
            list.excludes(path: "/Users/test/Developer/cache/blob"),
            "a path glob folds case too")
        expect(
            list.excludes(path: "/Users/test/Developer/app/build-output/index.js"),
            "a path glob matches an interior segment")
        expect(list.excludes(path: "/Users/test/archive/old.txt"), "a literal name folds case")
        expect(
            !list.excludes(path: "/Users/test/Documents/tmp-notes.txt"),
            "a name glob is anchored to the whole component, not a substring")
        expect(
            !list.excludes(path: "/Users/test/Documents/Archived/old.txt"),
            "a literal name never matches a longer component")
        expect(
            !FileSearchIgnoreList(patterns: []).excludes(path: "/Users/test/Documents/node_modules/a"),
            "the shipped rules are supplied by the policy, not baked into the matcher")
    }

    static func policyResolution() {
        let policy = FileSearchPolicy(
            scopes: ["~", "~/Developer", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], homeDirectory: home)
        expect(policy.includesHome, "a configured home root is held apart for expansion")
        expect(
            policy.directRoots.map(\.path) == ["/Users/test/Developer", "/Volumes/Work"],
            "every other root passes through verbatim, deduplicated in order")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/run.log"),
            "a user pattern applies outside home as well")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/node_modules/a.js"),
            "the shipped rules always apply on top of the user's")

        let away = FileSearchPolicy(
            scopes: ["~/Developer"], ignorePatterns: [], homeDirectory: home)
        expect(!away.includesHome, "dropping home drops the expansion with it")
        expect(
            FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home).directRoots.isEmpty,
            "a cleared list resolves to no roots at all")
        expect(
            FileSearchScope.normalize(
                ["/Users/test/Developer", "~/Developer", "/etc"],
                homeDirectory: home) == ["~/Developer", "/etc"],
            "normalizing abbreviates home and drops the duplicate it creates")
        expect(
            FileSearchScope.expand("~", homeDirectory: home).path == "/Users/test",
            "a bare tilde expands to home itself")
    }

    static func resultModel() {
        let nested = result("Documents/Annual Report.pdf")
        expect(nested.id == "/Users/test/Documents/Annual Report.pdf", "identity is the full path")
        expect(nested.name == "Annual Report.pdf", "the full filename keeps its extension")
        expect(nested.parentPath == "~/Documents", "the parent path abbreviates home")
        expect(result("Notes.txt").parentPath == "~", "a home-root item has a bare tilde parent")
        expect(
            nested.parentName == "Documents" && result("Notes.txt").parentName == "test",
            "the parent's own name is what a folder row prefixes itself with")
    }

    static func ranking() {
        let shipped = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults)
        let candidates = [
            result("Archive/Report Annual.txt"),
            result("Archive/My Annual Report.txt"),
            result("Archive/Annual Report", folder: true),
            result("Archive/Annual Reporting Notes.txt")
        ]
        let ranked = FileSearchQuery.rank(candidates, for: "annual report", ignoring: shipped)
            .map(\.name)
        expect(ranked.first == "Annual Report", "an exact filename ranks first")
        expect(
            ranked.firstIndex(of: "Annual Reporting Notes.txt")!
                < ranked.firstIndex(of: "My Annual Report.txt")!,
            "a prefix beats a later word-start match")
        expect(ranked.last == "Report Annual.txt", "reversed terms remain present but rank last")

        let ties = FileSearchQuery.rank(
            [result("zeta/report.txt"), result("alpha/Report.txt")], for: "report",
            ignoring: shipped)
        expect(
            ties.map(\.parentPath) == ["~/alpha", "~/zeta"],
            "equal names have a deterministic path tie-break")

        let capped = (0..<205).map { result("Archive/Report \($0).txt") }
        expect(
            FileSearchQuery.rank(capped, for: "report", ignoring: shipped).count == 200,
            "ranking publishes no more than the display cap")

        expect(
            FileSearchQuery.rank(
                [result("Archive/report.txt")], for: "report",
                ignoring: FileSearchIgnoreList(patterns: ["Archive"])
            ).isEmpty,
            "ranking drops what the user's own patterns exclude")
    }

    static func indexTable() {
        let table = FileIndexTable(
            roots: ["/Users/test"],
            records: [
                (name: "", parent: .max, isDirectory: true),
                (name: "Notes.txt", parent: 0, isDirectory: false),
                (name: "Documents", parent: 0, isDirectory: true),
                (name: "Annual Report.pdf", parent: 2, isDirectory: false),
                (name: "Résumé Final.txt", parent: 2, isDirectory: false),
                (name: "Archive", parent: 0, isDirectory: true),
                (name: "report-2019.txt", parent: 5, isDirectory: false),
            ])
        let open = FileSearchIgnoreList(patterns: [])
        let found = table.search(
            query: "annual report", filter: .all, ignoring: open, homeDirectory: home)
        expect(found.map(\.name) == ["Annual Report.pdf"], "both terms must occur in the name")
        expect(found.first?.parentPath == "~/Documents", "paths rebuild through the parent chain")

        expect(
            table.search(query: "resume", filter: .all, ignoring: open, homeDirectory: home)
                .map(\.name) == ["Résumé Final.txt"],
            "the index folds case and diacritics into its match bytes")
        expect(
            table.search(query: "annual", filter: .documents, ignoring: open, homeDirectory: home)
                .map(\.name) == ["Annual Report.pdf"],
            "the documents filter runs against resolved types")
        expect(
            table.search(query: "report", filter: .folders, ignoring: open, homeDirectory: home)
                .isEmpty,
            "a folders filter admits no files")
        expect(
            table.search(query: "report", filter: .images, ignoring: open, homeDirectory: home)
                .isEmpty,
            "an images filter rejects both the PDF and the text file")
        expect(
            table.search(query: "zzz", filter: .all, ignoring: open, homeDirectory: home).isEmpty,
            "a term nobody carries finds nothing")
        expect(
            table.search(
                query: "report", filter: .all,
                ignoring: FileSearchIgnoreList(patterns: ["Archive"]), homeDirectory: home
            ).map(\.name) == ["Annual Report.pdf"],
            "the ignore list still applies at query time")

        let many = (0..<210).map { index in
            (name: "Report \(index).txt", parent: UInt32(0), isDirectory: false)
        }
        let capped = FileIndexTable(
            roots: ["/Users/test"],
            records: [(name: "", parent: .max, isDirectory: true)] + many)
        expect(
            capped.search(query: "report", filter: .all, ignoring: open, homeDirectory: home)
                .count == 200,
            "a sprawling match set still publishes no more than the display cap")

        if let stored = FileIndexTable.deserialized(table.serialized(policyKey: "k")) {
            expect(stored.policyKey == "k", "the persisted table carries its policy key")
            expect(
                stored.table.search(
                    query: "annual report", filter: .all, ignoring: open, homeDirectory: home
                ).map(\.name) == ["Annual Report.pdf"],
                "a table survives a serialization round trip")
        } else {
            expect(false, "the persisted table deserializes")
        }
    }

}
