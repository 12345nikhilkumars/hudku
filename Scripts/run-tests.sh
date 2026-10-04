#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/hudku-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall the suite.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((HUDKU_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$HUDKU_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${HUDKU_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
only="${1:-}"

# `--index` merges each harness's compile command into .compile instead of running anything.
# xcodebuild never compiles the harnesses, so without this nothing in Tests/ resolves in an editor.
# The source lists below are the only copy, which is why this lives here rather than in its own script.
emit_db=0
DB="${TMPDIR:-/tmp}/hudku-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run [slow] [-O] [index] <name> <source...> — queue the harness. `slow` dispatches it in the first
# wave; `index` claims editor flags for a harness that is compiled by hand rather than by the suite.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths throughout: sourcekit-lsp resolves the command itself and does not apply
    # `directory` to relative arguments, so a relative path there silently yields no index.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Claim every file under `Tests/`: the harness and any helper compiled beside it. A shipped
        # source stays unclaimed, because it would get this short command instead of the app's full
        # one and `.compile` is last-wins — but the app never compiles anything in `Tests/`.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Hudku/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
run file-search-test       $L/SearchRelevance.swift \
                           Hudku/Features/FileSearch/Model/*.swift
run file-search-session-test Hudku/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Hudku/Features/FileSearch/Model/*.swift \
                             Hudku/Features/FileSearch/Service/*.swift
run index file-search-performance Hudku/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Hudku/Features/FileSearch/Model/*.swift \
                           Hudku/Features/FileSearch/Service/FileSearchService.swift
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Hudku/Platform/AppDisplayName.swift \
                           Hudku/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run apple-shortcut-test    Hudku/Features/AppleShortcuts/Model/*.swift
run calc-test              Hudku/Features/Calculator/Model/*.swift
run index calc-performance Hudku/Features/Calculator/Model/*.swift
run clipboard-test         Hudku/Features/Clipboard/Model/ClipboardStore.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFilter.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Hudku/Features/Clipboard/Model/ColorValue.swift \
                           Hudku/Features/Clipboard/Model/ColorFormat.swift \
                           Hudku/Features/Clipboard/Model/ColorSpaces.swift
run clipboard-search-test  Hudku/Features/Clipboard/Model/*.swift
run paste-sequence-test    Hudku/Features/Clipboard/Model/*.swift
run clipboard-text-test    Hudku/Features/Clipboard/Model/*.swift \
                           Hudku/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Hudku/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Hudku/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Hudku/Platform/ProcessExit.swift
run pasteboard-test        Hudku/Platform/PasteboardFiles.swift \
                           Hudku/Features/Clipboard/Model/ClipboardStore.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFilter.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Hudku/Features/Clipboard/Model/ColorValue.swift \
                           Hudku/Features/Clipboard/Model/ColorFormat.swift \
                           Hudku/Features/Clipboard/Model/ColorSpaces.swift \
                           Hudku/Features/Clipboard/Service/ClipboardManager.swift \
                           Hudku/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Hudku/Platform/PasteboardFiles.swift \
                           Hudku/Features/Clipboard/Model/ClipboardStore.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFilter.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Hudku/Features/Clipboard/Model/ColorValue.swift \
                           Hudku/Features/Clipboard/Model/ColorFormat.swift \
                           Hudku/Features/Clipboard/Model/ColorSpaces.swift \
                           Hudku/Features/Clipboard/Service/ClipboardManager.swift
run emoji-test             Hudku/Features/Emoji/Model/EmojiCatalog.swift \
                           Hudku/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Hudku/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Hudku/Features/Emoji/Model/EmojiCatalog.swift \
                           Hudku/Features/Emoji/Model/EmojiData.generated.swift \
                           Hudku/Features/Emoji/Service/EmojiIndex.swift \
                           Hudku/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Hudku/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Hudku/Features/Launcher/Model/SearchRelevance.swift \
                           Hudku/Platform/AppPaths.swift Hudku/Platform/Memo.swift
run index emoji-search-performance \
                           Hudku/Features/Emoji/Model/EmojiCatalog.swift \
                           Hudku/Features/Emoji/Model/EmojiData.generated.swift \
                           Hudku/Features/Emoji/Service/EmojiIndex.swift \
                           Hudku/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Hudku/Features/Launcher/Model/SearchRelevance.swift \
                           Hudku/Platform/AppPaths.swift Hudku/Platform/Memo.swift
run palette-selection-test Hudku/Features/PaletteRowIndex.swift \
                           Hudku/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Hudku/Platform/Appearance.swift \
                           Hudku/DesignSystem/Theme.swift \
                           Hudku/DesignSystem/InterfaceMetrics.swift \
                           Hudku/Features/Settings/AppAppearance.swift
run interface-size-test    Hudku/Platform/Appearance.swift \
                           Hudku/DesignSystem/Theme.swift \
                           Hudku/DesignSystem/InterfaceMetrics.swift \
                           Hudku/Features/Settings/InterfaceSize.swift 
run palette-placement-test Hudku/Platform/Appearance.swift \
                           Hudku/DesignSystem/Theme.swift \
                           Hudku/DesignSystem/InterfaceMetrics.swift \
                           Hudku/Features/Settings/InterfaceSize.swift \
                           Hudku/Palette/PalettePlacement.swift
run scroll-reveal-test     Hudku/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         Hudku/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    Hudku/DesignSystem/Interaction/KeyboardFocus.swift
run hover-arming-test      Hudku/Palette/HoverArming.swift \
                           Hudku/Palette/PaletteState.swift \
                           Hudku/Palette/PaletteMode.swift \
                           Hudku/Features/Emoji/Model/EmojiCatalog.swift \
                           Hudku/Features/Clipboard/Model/ClipboardStore.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFilter.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Hudku/Features/FileSearch/Model/FileSearchFilter.swift \
                           Hudku/Features/Clipboard/Model/ColorValue.swift \
                           Hudku/Features/Clipboard/Model/ColorFormat.swift \
                           Hudku/Features/Clipboard/Model/ColorSpaces.swift 
run palette-escape-test    Hudku/Palette/PaletteMode.swift \
                           Hudku/Palette/PaletteEscapeAction.swift \
                           Hudku/Palette/CommandEscapeTap.swift \
                           Hudku/Features/Settings/EscapeKeyBehavior.swift 
run palette-navigation-test Hudku/Palette/PaletteState.swift \
                           Hudku/Palette/PaletteMode.swift \
                           Hudku/Palette/HoverArming.swift \
                           Hudku/Features/Emoji/Model/EmojiCatalog.swift \
                           Hudku/Features/Clipboard/Model/ClipboardStore.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFilter.swift \
                           Hudku/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Hudku/Features/FileSearch/Model/FileSearchFilter.swift \
                           Hudku/Features/Clipboard/Model/ColorValue.swift \
                           Hudku/Features/Clipboard/Model/ColorFormat.swift \
                           Hudku/Features/Clipboard/Model/ColorSpaces.swift 
run palette-filter-test    Hudku/Palette/PaletteMode.swift \
                           Hudku/Palette/PaletteFilterAction.swift 
run action-menu-search-test Hudku/Palette/ActionMenuSearchQuery.swift \
                            Hudku/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  Hudku/Palette/PaletteShortcut.swift
run ascii-layout-test      Hudku/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       Hudku/Palette/PaletteMode.swift \
                           Hudku/Palette/PaletteTabAction.swift 
run fallback-test          Hudku/Features/Launcher/Model/Fallback.swift \
                           Hudku/Features/Launcher/Model/CommandID.swift \
                           Hudku/Features/HotKeys/Model/HotKeyAction.swift \
                           Hudku/Features/SystemActions/Model/SystemAction.swift 
run dictionary-test        Hudku/Features/Dictionary/Model/DictionaryEntry.swift \
                           Hudku/Features/Dictionary/Model/DictionaryMarkup.swift
run hotkey-test            Hudku/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Hudku/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Hudku/Features/HotKeys/Model/GlobeTapDetector.swift \
                           Hudku/Features/HotKeys/Model/HotKeyBinding.swift \
                           Hudku/Features/HotKeys/Model/HotKeySpelling.swift \
                           Hudku/Features/HotKeys/Model/HyperKey.swift \
                           Hudku/Platform/ASCIIKeyboardLayout.swift \
                           Hudku/Features/HotKeys/Service/KeyShortcut.swift \
                           Hudku/Features/HotKeys/Model/HotKeyAction.swift \
                           Hudku/Features/Launcher/Model/CommandID.swift \
                           Hudku/Features/SystemActions/Model/SystemAction.swift 
run callout-test          Hudku/Platform/Appearance.swift \
                           Hudku/DesignSystem/Theme.swift \
                           Hudku/DesignSystem/InterfaceMetrics.swift \
                           Hudku/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Hudku/Platform/Appearance.swift \
                           Hudku/Platform/Images/IconCache.swift
run entry-icon-test        Hudku/Platform/Appearance.swift \
                           Hudku/Platform/Images/IconCache.swift \
                           Hudku/Platform/Images/FileIconStamp.swift
run system-action-test     Hudku/Features/SystemActions/Model/SystemAction.swift
run volume-test            Hudku/Features/SystemActions/Model/VolumeLevel.swift
run uninstall-test         Hudku/Features/Uninstall/Model/UninstallTarget.swift \
                           Hudku/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Hudku/Features/Uninstall/Model/UninstallRules.swift \
                           Hudku/Features/Uninstall/Model/UninstallProtection.swift \
                           Hudku/Features/Uninstall/Model/UninstallPlan.swift
run settings-file-test     Hudku/Features/Settings/Model/*.swift \
                           Hudku/Features/Settings/Service/SettingsFileMonitor.swift \
                           Hudku/Features/Settings/Service/SettingsFileRepository.swift \
                           Hudku/Platform/AppPaths.swift
run settings-history-test  Hudku/Features/Settings/SettingsTab.swift \
                           Hudku/Features/Settings/SettingsHistory.swift \
                           Hudku/Features/Settings/SettingsAnchor.swift \
                           Hudku/Features/Settings/SettingsNavigationState.swift \
                           Hudku/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${HUDKU_TEST_JOBS:-$(sysctl -n hw.ncpu)}"
export HUDKU_TEST_TIMEOUT="${HUDKU_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! { sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; echo "dispatch $?"; } | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
