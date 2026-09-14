# VPN Manager

An [Omarchy](https://omarchy.org/) bar widget that gives you a single icon
and popup panel to view and toggle both **Tailscale** and any
**NetworkManager VPN connection** (OpenVPN, WireGuard, etc.), including
inline credential prompts when a connection needs them.

## Features

- One bar icon that lights up when anything is connected.
- **Tailscale**: toggle up/down, see connection status, your Tailscale IP,
  DNS name, and online/offline peers.
- **NetworkManager VPN profiles**: toggle any configured connection on/off,
  see live status (connected / connecting / disconnected).
- **Import `.ovpn` profiles**: pick a `.ovpn`/`.conf` file from the desktop
  file picker and import it straight into NetworkManager, no terminal
  needed. If the file has `dhcp-option DNS`/`DOMAIN` lines — which
  NetworkManager's OpenVPN import silently drops — you're asked whether to
  apply them to the new connection (recommended: yes).
- **Rename/delete profiles**: rename or remove any NetworkManager VPN
  connection right from its row, with an inline confirmation before
  deleting.
- Inline credential prompt (same style as the Omarchy Wi-Fi panel) when a
  VPN connection needs a username/password/private-key password that
  NetworkManager doesn't already have cached — only asks for what's
  actually missing.
- STATUS section with IP, DNS, gateway, and uptime for every active
  connection.
- Detects when you're not set as the Tailscale operator and shows the
  `sudo tailscale set --operator=<user>` command to fix it.
- Configurable refresh interval.

## Requirements

- `tailscale` CLI installed and on `PATH` (optional — the widget still
  works for NetworkManager VPNs if Tailscale isn't installed).
- `nmcli` (NetworkManager) for VPN connection management.
- `NetworkManager-openvpn` (the nmcli/NM OpenVPN plugin) to import and
  connect `.ovpn` profiles.
- `omarchy file select` (bundled with Omarchy) for the import file picker.

## Install

```bash
omarchy plugin add https://github.com/vinicgobbi/omarchy-plugin-vpn.git --enable
```

This clones the plugin into `~/.config/omarchy/plugins/vinicgobbi.vpn/` and
adds it to your bar. If you'd rather add it manually:

```bash
git clone https://github.com/vinicgobbi/omarchy-plugin-vpn.git \
  ~/.config/omarchy/plugins/vinicgobbi.vpn
omarchy plugin enable vinicgobbi.vpn
```

Saving changes under `~/.config/omarchy/plugins/` hot-reloads automatically;
if something doesn't pick up, force it with:

```bash
omarchy-shell shell rescanPlugins
```

## Usage

- Click the VPN icon in the bar to open the panel.
- **Tailscale** row: flip the switch to connect/disconnect (or log in, if
  you're logged out).
- **VPN (NetworkManager)** section: one row per connection NetworkManager
  knows about — flip a switch to connect/disconnect it.
- Click **Import .ovpn profile…** to pick a `.ovpn`/`.conf` file from the
  desktop file picker; it's imported into NetworkManager and shows up in the
  list right away. Opening the native file picker closes this popup (same as
  clicking outside it) — the widget reopens itself automatically once the
  import finishes, so you land back on the result instead of having to
  reopen it by hand. If the file carries its own DNS server(s) or search
  domain(s), a card appears asking whether to apply them to the imported
  connection — **Apply (recommended)** sets `ipv4.dns`/`ipv4.dns-search` on
  it, **Skip** leaves it as NetworkManager imported it.
- Each profile row has a pencil (rename) and trash (delete) icon next to its
  switch. Rename expands an inline field; delete expands an inline
  confirmation — both can be cancelled without effect.
- If a connection needs credentials, a form expands inline under that row
  asking only for what's missing (username, password, and/or private key
  password). Submit to connect, or cancel to back out.
- Press `r` while the panel is focused to force a refresh.
- The **STATUS** section (only shown when something is connected) lists IP,
  DNS, gateway, and uptime per connection.

## Settings

Configurable from the bar widget's settings (or directly in
`~/.config/omarchy/shell.json`):

| Setting | Description | Default |
|---|---|---|
| `refreshIntervalSec` | How often (in seconds, 3–300) the widget polls Tailscale/NetworkManager status | `10` |

## Updating / Removing

```bash
omarchy plugin update vinicgobbi.vpn
omarchy plugin remove vinicgobbi.vpn
```

## Troubleshooting

- **"Tailscale: você não é o operator configurado"** — Tailscale commands
  need root or an operator user. Run the suggested
  `sudo tailscale set --operator=<you>` once in a terminal.
- **VPN toggle fails with a credentials error** — the inline form should
  open automatically; if it doesn't, check that the connection is properly
  configured in NetworkManager (`nmcli connection show <name>`).
- Nothing showing up under "VPN (NetworkManager)"? Confirm the connection
  exists via `nmcli connection show` — only entries of type `vpn` or
  `wireguard` are listed.
- **Importing a `.ovpn` profile fails** — make sure `NetworkManager-openvpn`
  is installed (`nmcli connection import type openvpn file <path>` needs
  it), and that the file is a valid OpenVPN client config.

## License

MIT
