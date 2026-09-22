# Contributing

## Local setup

The source of truth for this plugin lives here, **not** under
`~/.config/omarchy/plugins/`. That directory is watched by Omarchy and
hot-reloads on every file change, so editing there directly means a reload
on every single save — noisy and easy to trigger by accident mid-edit.

Instead, edit here and deploy a test build on demand:

```bash
scripts/dev-install.sh
```

This copies the plugin files (everything except `.git/`, `scripts/`, and
this file) into `~/.config/omarchy/plugins/vinicgobbi.vpn/` and runs
`omarchy-shell shell rescanPlugins` once, so you get exactly one reload,
when you actually want to test something.

To remove the test install (e.g. before switching branches or when you're
done for the day):

```bash
scripts/dev-uninstall.sh
```

Both scripts read the plugin id from `manifest.json`, so they keep working
if the plugin is ever renamed.

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

`.github/workflows/ci.yml` runs on every push (including to `main`) and
on pull requests: it validates `manifest.json`, runs Shellcheck on the
shell scripts, and lints every `.qml` file with `qmllint`, so a syntax
error can't land on `main`.

## Commits and releases

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, ...), enforced and managed
with [Commitizen](https://commitizen-tools.github.io/commitizen/) (config in
`.cz.toml`). To write a commit interactively instead of typing the prefix by
hand:

```bash
uvx --from commitizen cz commit
```

Releases are manual: run the `Bump version` workflow from the Actions tab
(`.github/workflows/bump.yml`, or `gh workflow run bump.yml`) when `main`
is ready to release. It runs `cz bump --changelog` against `main`, and
only pushes/tags/publishes a GitHub release if the commits since the last
tag are actually eligible (any `feat`/`fix`/`BREAKING CHANGE`); otherwise
it's a no-op. Don't hand-edit the version in `manifest.json` or write to
`CHANGELOG.md` directly — run `cz bump` locally
(`uvx --from commitizen cz bump --changelog`) only if you need to cut a
release outside of that automation.
