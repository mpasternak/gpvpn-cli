# global-protect-vpn

[![CI](https://github.com/mpasternak/global-protect-vpn/actions/workflows/ci.yml/badge.svg)](https://github.com/mpasternak/global-protect-vpn/actions/workflows/ci.yml)

Command-line controller for **Palo Alto GlobalProtect** on macOS. Connect, disconnect, and check status without touching the mouse — and optionally open a browser tab automatically once the tunnel is up.

Requires macOS Accessibility permissions for the terminal you run it from (**System Settings → Privacy & Security → Accessibility**).

## Installation

```bash
git clone https://github.com/mpasternak/global-protect-vpn.git
cd global-protect-vpn
cp gp.conf.sample gp.conf
# edit gp.conf with your portal, username, and post-connect URL
```

Add a convenience alias (optional):

```bash
ln -s "$PWD/gp.sh" ~/bin/gp
```

## Configuration

Copy `gp.conf.sample` to `gp.conf` and fill in:

| Variable | Description |
|---|---|
| `PORTAL` | GlobalProtect portal hostname |
| `USERNAME` | VPN username |
| `POST_CONNECT_CHECK` | Internal URL polled to detect tunnel-up |
| `POST_CONNECT_OPEN` | URL opened in Firefox once tunnel is up |
| `POST_CONNECT_TIMEOUT` | Seconds to wait before giving up (default 60) |

`gp.conf` is gitignored — your credentials and internal hostnames stay local.

## Usage

```bash
./gp.sh set-password    # save VPN password to macOS Keychain (run once)

./gp.sh status          # connected / disconnected / needs_credentials
./gp.sh connect         # connect and open browser when tunnel is up
./gp.sh disconnect      # disconnect
./gp.sh toggle          # connect if disconnected, disconnect if connected
```

### How connect works

1. Finds the GlobalProtect popup (portal screen or credential dialog).
2. If it shows the portal-confirmation screen (1 field), clicks **Connect** and waits up to 15 s for the credential dialog.
3. When the credential dialog appears (2 fields), fills username + password from Keychain and submits.
4. Polls `POST_CONNECT_CHECK` every 2 s until reachable (or timeout), then opens `POST_CONNECT_OPEN` in Firefox.

### Password storage

Passwords are stored in the macOS Keychain under service `GlobalProtect/<PORTAL>` / account `<USERNAME>`. Run `gp.sh set-password` to save or update.

## Requirements

- macOS 11+ with GlobalProtect 6.x installed
- Accessibility permission granted for your terminal
- Firefox (for post-connect browser open)
- `bash` 3.2+ (ships with macOS)

## How it works

GlobalProtect has no public CLI on macOS. This script drives the native GUI via macOS Accessibility APIs (`osascript` / System Events), detecting the correct popup window by scanning for specific button and text-field combinations rather than relying on window index order.

## License

MIT © 2026 Michał Pasternak
