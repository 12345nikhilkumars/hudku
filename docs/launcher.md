# Launcher

## The hotkey

No hotkey is bound by default. Bind one in Settings > General, or summon the palette from
Spotlight or `open -a Hudku`. Once bound, the shortcut toggles the palette from anywhere, and
`Tab` rings between the launcher and clipboard history.

## Find, Do, Done

- **Find**: apps and commands by fuzzy search, files with `@name` or `?name`, emoji with
  `:name`, clipboard entries on the clipboard tab.
- **Do**: calculations (`2+2`, `sqrt(144)`), conversions (`10 usd in eur`, `100 km/h`,
  `20c to f`), colors (`#ff5733`), dictionary pages (`def word` or `define word`), Apple
  Shortcuts, system actions, the uninstaller.
- **Done**: the palette closes the moment the action lands.

## Keywords

| Typed | What appears |
| --- | --- |
| `:smile` (or a bare `:`) | Emoji rows, favourites first; `Enter` copies |
| `def word`, `define word` | The full definition page in place; `Enter` copies it |
| `@word`, `?word` | Files and folders under your search scopes, by name |
| `#ff5733` | The color card; `Enter` copies in the current format |
| arithmetic, units, currencies, dates, time zones | The calculator card |
| a web address | An "open in browser" row |

## Rows and keys

`↑`/`↓` move the highlight, `Enter` runs the primary action, `⌘K` opens the actions menu,
`⌘,` opens Settings, `Esc` dismisses the palette. Favorites pin to the top of an empty query,
and `⌘1` through `⌘0` launch the first ten rows. Per-app hotkeys, aliases, and visibility live
in each app's actions menu.

## Hyper Key

Settings > General can turn Caps Lock into a Hyper key (⇧⌃⌥⌘ suffix), which frees up single
letters for app hotkeys. It needs Accessibility; see [permissions](permissions.md).
