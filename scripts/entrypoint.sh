#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'entrypoint: must run as root.' >&2
  exit 1
fi

# Any firewall failure aborts startup before the container becomes usable.
/usr/local/bin/init-firewall.sh

mkdir -p /home/node/.codex /home/node/.claude
# Fresh Docker volumes inherit the image's node-owned defaults. Only repair
# ownership when needed; Compose deliberately grants no CHOWN capability.
for directory in /home/node/.codex /home/node/.claude; do
  if [[ "$(stat -c '%U:%G' "$directory")" != node:node ]]; then
    chown -hR node:node "$directory"
  fi
done
if [[ ! -e /home/node/.codex/config.toml ]]; then
  cp /etc/agent-box/defaults/codex-config.toml /home/node/.codex/config.toml
fi
if [[ ! -e /home/node/.claude/settings.json ]]; then
  cp /etc/agent-box/defaults/claude-settings.json /home/node/.claude/settings.json
fi
for settings in /home/node/.codex/config.toml /home/node/.claude/settings.json; do
  if [[ "$(stat -c '%U:%G' "$settings")" != node:node ]]; then
    chown -h node:node "$settings"
  fi
done

exec sleep infinity
