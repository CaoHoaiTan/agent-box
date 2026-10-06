#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'entrypoint: must run as root.' >&2
  exit 1
fi

# Any firewall failure aborts startup before the container becomes usable.
/usr/local/bin/init-firewall.sh

mkdir -p /home/node/.codex /home/node/.claude
if [[ ! -e /home/node/.codex/config.toml ]]; then
  cp /etc/agent-box/defaults/codex-config.toml /home/node/.codex/config.toml
fi
if [[ ! -e /home/node/.claude/settings.json ]]; then
  cp /etc/agent-box/defaults/claude-settings.json /home/node/.claude/settings.json
fi
# Named login volumes may initially be root-owned. Include existing login files.
chown -R node:node /home/node/.codex /home/node/.claude

exec sleep infinity
