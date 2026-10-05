import Foundation

/// The two surfaces stay reachable one way; Tab is skipped to the launcher when one is off.
@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteTabAction, _ expected: PaletteTabAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) - got \(actual), want \(expected)")
        }
    }

    static func main() {
        expect(
            PaletteTabAction.resolve(mode: .launcher, clipboardEnabled: true),
            .carryQuery(.clipboard),
            "the launcher hands the query to the clipboard, and one search narrows both lists")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, clipboardEnabled: true),
            .carryQuery(.launcher),
            "the clipboard closes the ring")

        // Off, the clipboard has no launcher command and no hotkey; the ring must not strand a reader there.
        expect(
            PaletteTabAction.resolve(mode: .launcher, clipboardEnabled: false),
            .carryQuery(.launcher),
            "with the clipboard off, the launcher rings back onto itself")

        // A sub-screen is reached by a command or a hotkey, so Tab leaves rather than ringing on.
        for mode in [
            PaletteMode.emoji, .calculatorHistory, .dictionary, .uninstall
        ] {
            expect(
                PaletteTabAction.resolve(mode: mode, clipboardEnabled: true),
                .carryQuery(.launcher),
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }

        // Two presses from the launcher have to land back on it, or the ring is a dead end.
        var mode = PaletteMode.launcher
        var visited: [PaletteMode] = []
        for _ in 0..<2 {
            switch PaletteTabAction.resolve(mode: mode, clipboardEnabled: true) {
            case .carryQuery(let next): mode = next
            }
            visited.append(mode)
        }
        if visited == [.clipboard, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: two presses ring back to the launcher - got \(visited)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
