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

## License

MIT
