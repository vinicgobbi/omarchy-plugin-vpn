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
