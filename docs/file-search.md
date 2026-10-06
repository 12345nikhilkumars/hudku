# File search

Typing `@word` or `?word` in the launcher answers with files and folders by name, inline in
the palette. Behind it is Hudku's own name index: no Spotlight, no daemon, no per-query round
trip.

## What gets indexed

- Every visible folder in your home, except `Library`.
- iCloud Drive and cloud storage folders inside `Library`.
- Any additional scopes you add in Settings > File Search.

Skipped everywhere: hidden files, `.app` bundles, other bundles' contents, and the built-in
ignore list:

    node_modules  DerivedData  build  dist  target  Pods  __pycache__
    venv  vendor  bower_components  out  coverage
    go  Carthage  obj  site-packages  Packages  .build

Your own patterns in Settings > File Search add to that list.

## How it stays current

The index is built once (about 1.7 s for 79k entries on a typical developer Mac), written to
`~/Library/Application Support/com.hudku.app/FileIndex.bin`, and loaded from disk on later
launches. FSEvents watches the scopes and folds changed names back in shortly after they
change. Deleting the `.bin` file forces a rebuild on the next `@` search.

## Permissions

The first build reads your home directly, so macOS asks once for the protected folders it
touches (Documents, Desktop, Downloads). Answer Allow and the index covers them; nothing more
is requested. If the prompts are dismissed, grant them later in System Settings > Privacy &
Security > Files and Folders, then relaunch Hudku.

## Performance

Typical terms answer in 0.6 to 3 ms and the worst single letters in about 7 ms, at a few
megabytes of memory while file search is in use. The full comparison with Spotlight, Tinycast,
and Raycast is in [PERFORMANCE.md](../PERFORMANCE.md).
