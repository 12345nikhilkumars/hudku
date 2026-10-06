# Settings

The gear in the palette (or `⌘,`) opens Settings. Panes:

- **General**: appearance, interface size, the summon hotkey, Hyper Key, launch at login.
- **Applications**: per-app visibility, aliases, hotkeys, favorites.
- **System Settings** and **System Actions**: which system panes and actions are searchable.
- **Commands**: enable, alias, and hide built-in commands.
- **Apple Shortcuts**: search and run your shortcuts, with aliases and hotkeys.
- **Clipboard**: history size, text search, disabled applications.
- **File Search**: enable file search, manage scopes and ignore patterns.
- **Permissions**: what macOS has granted so far.
- **About**: version and links.

## settings.json

With the file mirror on (Settings > General), every setting mirrors to
`~/.config/hudku/settings.json`: edit the file and Hudku applies the change live; change a
pane and the file updates. Problems (unknown keys, wrong types) surface as a message in the
palette, and the file is rewritten from the stores, so it self-heals.
