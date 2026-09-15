# Development

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

## Commits and versioning

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, ...), enforced and managed
with [Commitizen](https://commitizen-tools.github.io/commitizen/) (config in
`.cz.toml`). To write a commit interactively instead of typing the prefix by
hand:

```bash
uvx --from commitizen cz commit
```

Versioning is derived from that history, not chosen by hand: `manifest.json`'s
`version` and `CHANGELOG.md` are only ever updated by `cz bump`, which the
`Bump version` GitHub Actions workflow runs automatically on `main` after CI
passes, if the commits since the last tag are eligible (any `feat`/`fix`/
`BREAKING CHANGE` — see [`bump.yml`](.github/workflows/bump.yml)). It also
tags the bump and publishes a GitHub release from the new changelog section.
Don't hand-edit the version in `manifest.json` or write to `CHANGELOG.md`
directly — run `cz bump` locally (`uvx --from commitizen cz bump --changelog`)
only if you need to cut a release outside of that automation.
