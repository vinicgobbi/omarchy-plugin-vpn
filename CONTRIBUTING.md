# Contributing

## Local setup

`omarchy plugin validate .` rejects a plugin folder that contains a
symlink, so a plain `ln -s` of this repo into
`~/.config/omarchy/plugins/` won't load. Clone it there instead
(a real, separate working copy — like `omarchy plugin add` would
leave):

```bash
git clone "$(pwd)" ~/.config/omarchy/plugins/vinicgobbi.vpn
omarchy plugin enable vinicgobbi.vpn
```

To pick up local edits without re-cloning, add this repo as a remote
in the installed copy and pull:

```bash
git -C ~/.config/omarchy/plugins/vinicgobbi.vpn remote add dev "$(pwd)"
git -C ~/.config/omarchy/plugins/vinicgobbi.vpn pull dev main
```

`BarWidget.qml` (the plugin's entry point, `VpnService.qml` included)
hot-reloads on its own once the installed copy is updated.

Validate the manifest before publishing:

```bash
omarchy plugin validate .
```

## Structure

- `manifest.json` — plugin metadata (id, kind, entry point) and the
  `barWidget.defaults` / `schema` for the refresh-interval setting
- `BarWidget.qml` — the bar icon and popup: Tailscale row, the
  NetworkManager VPN list (toggle/rename/delete), inline credential
  prompts, the import flow, and the STATUS section
- `VpnService.qml` — polls Tailscale and NetworkManager and exposes a
  single merged model; also detects when a connection needs credentials
  NetworkManager doesn't already have cached and figures out which fields
  are actually missing
- `import-profile` — shell script the popup shells out to: picks a
  `.ovpn`/`.conf` file via `omarchy file select` and imports it into
  NetworkManager

## CI

`.github/workflows/ci.yml` runs on every push to `main` (and on pull
requests): it validates `manifest.json`, runs Shellcheck on any shell
scripts, and lints every `.qml` file with `qmllint`, so a syntax error
can't land on `main`.

## Commits and releases

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
and are checked with [Commitizen](https://commitizen-tools.github.io/commitizen/):

```bash
pipx install commitizen
cz commit   # interactive, conventional-commits-compliant commit
```

Releases are manual: run `.github/workflows/release.yml` from the
Actions tab (`Run workflow`, on `main`). It only runs when dispatched
against `main`, and uses Commitizen to bump `manifest.json`'s version
and the changelog based on the commit types since the last release,
tags it (`vX.Y.Z`), and publishes a GitHub Release with the changelog
entry. If there's nothing to bump (no `feat`/`fix`/`BREAKING CHANGE`
commits since the last release), it's a no-op — no tag, no release.
