#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
  if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
    echo 'Usage: verify.sh (run inside a box as node)'
    exit 0
  fi
  echo 'verify: unexpected arguments; use --help.' >&2
  exit 2
fi

failures=0
workspace_probe=''
cleanup() {
  if [[ -n "$workspace_probe" ]]; then
    rm -f -- "$workspace_probe"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

reachable() {
  # Auth errors (401/403) still prove connectivity; do not use curl --fail.
  # Proxy variables must not redirect the probe to an allowlisted proxy.
  curl --noproxy '*' --silent --output /dev/null --connect-timeout 5 --max-time "$2" "$1"
}

isolated_home() {
  local path ssh_entry
  [[ "$HOME" == /home/node && ! -e /Users && ! -L /Users ]] || return 1
  [[ ! -L "$HOME/.ssh" ]] || return 1
  if [[ -e "$HOME/.ssh" ]]; then
    [[ -d "$HOME/.ssh" ]] || return 1
    ssh_entry="$(find "$HOME/.ssh" -mindepth 1 -print -quit)" || return 1
    [[ -z "$ssh_entry" ]] || return 1
  fi
  for path in /home/* /home/.[!.]* /home/..?*; do
    [[ -e "$path" || -L "$path" ]] || continue
    [[ "$path" == /home/node ]] || return 1
  done
}

unprivileged_firewall() {
  local output
  [[ $EUID -ne 0 ]] || return 1
  command -v iptables >/dev/null 2>&1 || return 1
  if output="$(iptables -L 2>&1)"; then
    return 1
  fi
  [[ "$output" == *'Permission denied'* || "$output" == *'must be root'* || "$output" == *'Operation not permitted'* ]]
}

writable_workspace() {
  workspace_probe="$(mktemp /workspace/.agentbox-verify.XXXXXX)" || return 1
  printf 'agentbox write check\n' > "$workspace_probe" || return 1
  rm -f -- "$workspace_probe" || return 1
  workspace_probe=''
}

if reachable https://api.anthropic.com 10; then pass 'api.anthropic.com reachable'; else fail 'api.anthropic.com reachable'; fi
if reachable https://api.openai.com 10; then pass 'api.openai.com reachable'; else fail 'api.openai.com reachable'; fi
if reachable https://example.com 5; then fail 'example.com blocked'; else pass 'example.com blocked'; fi
if isolated_home; then pass 'no SSH content or other host home paths'; else fail 'no SSH content or other host home paths'; fi
if [[ ! -e /var/run/docker.sock && ! -L /var/run/docker.sock ]]; then pass 'no Docker socket'; else fail 'no Docker socket'; fi
if unprivileged_firewall; then pass 'iptables denied to non-root user'; else fail 'iptables denied to non-root user'; fi
if command -v sudo >/dev/null 2>&1; then fail 'sudo absent'; else pass 'sudo absent'; fi
if writable_workspace; then pass '/workspace writable'; else fail '/workspace writable'; fi

if [[ "$failures" -ne 0 ]]; then
  echo "verify: $failures check(s) failed." >&2
  exit 1
fi
echo 'verify: all 8 checks passed.'
