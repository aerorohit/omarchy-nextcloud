# Nextcloud

Omarchy bar widget for Nextcloud. The bar shows a cloud glyph and clicking opens a panel with a sync toggle, storage usage, server info, and recent synced files.

## Install

```bash
omarchy plugin add https://github.com/aerorohit/omarchy-nextcloud.git --enable
```

If the bar does not pick it up automatically:

```bash
omarchy restart shell
```

## Usage

Click the widget to open the panel. The toggle switch **pauses/resumes** Nextcloud syncing via D-Bus.

- **Left-click** — open/close the panel
- **Right-click** — refresh status
- **Middle-click** — open Nextcloud desktop client

Keyboard: `j`/`k` move the cursor, `Enter` activates, `Escape` closes, `r` refreshes, `o` opens the Nextcloud desktop app, `i` installs it when missing.

The panel shows:

- **Stored** — total size of local sync folder
- **Server** — configured Nextcloud server URL
- **Recent files** — most recently modified synced files (up to 25)
- **Action row** — opens the Nextcloud desktop app; if the desktop client is
  not installed, the row instead offers to install it (runs
  `omarchy-pkg-add nextcloud-client` in a terminal)

## Tray icon

While the widget is on the bar, the desktop client's own tray icon is hidden
(added to the `omarchy.tray` widget's `hidden` list in `shell.json`) so sync
status lives in one place. Disabling or removing the plugin restores the
client's tray icon automatically.

## Configure

```bash
omarchy bar set aerorohit.nextcloud refreshIntervalSec 120
omarchy bar move aerorohit.nextcloud --section right
```

## Remove

```bash
omarchy plugin remove aerorohit.nextcloud
```

## Dependencies

- `nextcloud-client` — the Nextcloud desktop sync client must be installed and configured

## License

MIT — see [LICENSE](LICENSE).
