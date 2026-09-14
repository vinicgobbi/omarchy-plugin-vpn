#!/usr/bin/env bash
# Deploys this dev checkout into the live Omarchy plugins directory so you
# can test changes on demand, without ever editing the live/watched folder
# directly (which triggers a hot-reload on every single save).
#
# Usage: scripts/dev-install.sh
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_dir/manifest.json"

if [[ ! -f "$manifest" ]]; then
  echo "error: manifest.json not found at $manifest" >&2
  exit 1
fi

plugin_id=$(jq -r '.id // empty' "$manifest")
if [[ -z "$plugin_id" ]]; then
  echo "error: could not read .id from $manifest" >&2
  exit 1
fi

dest_dir="$HOME/.config/omarchy/plugins/$plugin_id"

echo "Installing $plugin_id -> $dest_dir"
mkdir -p "$dest_dir"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.gitignore' \
  --exclude 'scripts/' \
  --exclude 'DEVELOPMENT.md' \
  "$repo_dir/" "$dest_dir/"

echo "Rescanning Omarchy plugins..."
omarchy-shell shell rescanPlugins

echo "Done. $plugin_id is installed and reloaded for testing."
