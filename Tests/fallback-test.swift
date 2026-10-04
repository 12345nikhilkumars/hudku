// The fallback list's pure half: identity, stored order, and the section header's elision.

import Foundation

@main
@MainActor
struct FallbackTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)\(detail.isEmpty ? "" : " - \(detail)")")
        }
    }

    static func main() {
        identity()
        ordering()
        headers()
        verbs()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Identity

    static func identity() {
        // The id *is* the row's entry id, which is what lets a stored order name a live row.
        for builtin in Fallback.Builtin.allCases {
            let fallback = Fallback.builtin(builtin)
            check(
                "\(builtin.rawValue) is its command's id", fallback.id == builtin.command.rawValue,
                "got \(fallback.id)")
            check(
                "\(builtin.rawValue) round-trips", Fallback(id: fallback.id) == fallback,
                "got \(String(describing: Fallback(id: fallback.id)))")
        }

        // Every built-in's id must be distinct, or one would silently take another's stored slot.
        let ids = Set(Fallback.Builtin.allCases.map { Fallback.builtin($0).id })
        check("built-in ids are distinct", ids.count == Fallback.Builtin.allCases.count)

        // A command with no fallback of its own must not resolve to one.
        check("a plain command is not a fallback", Fallback(id: CommandID.about.rawValue) == nil)
        check("nonsense is not a fallback", Fallback(id: "banana") == nil)
        check("a bare uuid is not a fallback", Fallback(id: UUID().uuidString) == nil)
    }

    // MARK: - Ordering

    static func ordering() {
        let files = Fallback.builtin(.searchFiles)

        check(
            "the offered fallback survives an empty stored order",
            Fallback.ordered([files], by: []) == [files])

        // A stored id with nothing behind it is skipped rather than resurrected, and does not
        // shift the fallback that is still offered.
        check(
            "a stored id with nothing behind it is skipped",
            Fallback.ordered([files], by: ["command:define", files.id]) == [files])

        check("nothing available is nothing offered", Fallback.ordered([], by: [files.id]).isEmpty)
    }

    // MARK: - Header

    static func headers() {
        check(
            "a short query is quoted whole",
            Fallback.sectionTitle(query: "todo") == "Use “todo” with…",
            "got \(Fallback.sectionTitle(query: "todo"))")

        let long = String(repeating: "a", count: 200)
        let title = Fallback.sectionTitle(query: long, limit: 20)
        // The point of the elision: the header must still say what the section is for.
        check("a long query still ends in the verb", title.hasSuffix("” with…"), "got \(title)")
        check("a long query is elided", title.contains("…a"), "got \(title)")
        check("a long query is bounded by the limit", title.count <= 20 + 13, "got \(title.count)")

        // The boundary is exact equality, so a query at the limit is never touched.
        let exact = String(repeating: "b", count: 20)
        check(
            "a query at the limit is kept whole",
            Fallback.sectionTitle(query: exact, limit: 20) == "Use “\(exact)” with…")

        // The shipped limit has to clear a real URL, which is the query this was drawn against.
        let url = "https://github.com/vgnshiyer/py-apple-books.git"
        check(
            "the default limit keeps a repository URL whole",
            Fallback.sectionTitle(query: url) == "Use “\(url)” with…",
            "got \(Fallback.sectionTitle(query: url))")
    }

    // MARK: - Verbs

    static func verbs() {
        let verbs = Fallback.Builtin.allCases.map { Fallback.builtin($0).openVerb }
        check("every fallback names its own action", verbs.allSatisfy { !$0.isEmpty })
        check("the verbs are distinct", Set(verbs).count == verbs.count, "got \(verbs)")
    }
}
