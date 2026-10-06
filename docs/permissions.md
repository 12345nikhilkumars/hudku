# Permissions

Hudku is an accessory app and asks only for what a feature needs, when it needs it.

| Permission | Used by | When |
| --- | --- | --- |
| Accessibility | Clipboard paste-back, Hyper Key | Granted lazily on first use |
| Camera | The camera panel | When the camera opens |
| Files and Folders | The file index (Documents, Desktop, Downloads) | Once, on the first `@` search |

Builds are ad-hoc signed, so macOS may forget a grant after you install a new build. If
paste-back stops working after an update, re-grant Accessibility in System Settings > Privacy
& Security > Accessibility, then relaunch Hudku.
