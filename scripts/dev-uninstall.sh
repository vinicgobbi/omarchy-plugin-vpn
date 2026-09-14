#!/usr/bin/env bash
# Removes the test install created by dev-install.sh from the live Omarchy
# plugins directory and rescans, so the widget disappears from the bar
# cleanly instead of being left around stale.
#
# Usage: scripts/dev-uninstall.sh [-y]
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

if [[ ! -e "$dest_dir" ]]; then
  echo "$plugin_id is not installed at $dest_dir — nothing to do."
  exit 0
fi

if [[ "${1:-}" != "-y" ]]; then
  read -r -p "Remove $dest_dir ? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

rm -rf "$dest_dir"
echo "Rescanning Omarchy plugins..."
omarchy-shell shell rescanPlugins
echo "Removed $plugin_id."
