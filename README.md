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

Keyboard: `j`/`k` move the cursor, `Enter` activates, `Escape` closes, `r` refreshes, `o` opens Nextcloud settings.

The panel shows:

- **Stored** — total size of local sync folder
- **Server** — configured Nextcloud server URL
- **Recent files** — most recently modified synced files (up to 25)

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
