#!/usr/bin/env bash
# Scan tracked files for leaked identifying terms and generic secret patterns.
#
# - Local terms come from .leak-denylist (git-ignored, one case-insensitive
#   term per line). It is local on purpose: the list itself would be a leak.
# - Generic secret patterns are always checked, with or without the denylist.
#
# Works with the stock macOS bash 3.2 (no mapfile, no associative arrays).
# Usable as a git pre-commit hook:
#   ln -s ../../scripts/check-leaks.sh .git/hooks/pre-commit
set -euo pipefail

# Resolve the repo root through the real script path so a symlinked hook works.
script_path="${BASH_SOURCE[0]}"
if [[ -L "$script_path" ]]; then
  link_target="$(readlink "$script_path")"
  case "$link_target" in
    /*) script_path="$link_target" ;;
    *) script_path="$(dirname "$script_path")/$link_target" ;;
  esac
fi
cd "$(dirname "$script_path")/.."

denylist=".leak-denylist"
found=0

# These files quote the secret regexes themselves, so they would always match.
exclude_self=':(exclude)scripts/check-leaks.sh'
exclude_plan=':(exclude)PLAN.md'

# Generic secret patterns (extended regex, case-sensitive).
secret_patterns=(
  'sk-[A-Za-z0-9]{20,}'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_'
  '-----BEGIN .*PRIVATE KEY-----'
)

for pattern in "${secret_patterns[@]}"; do
  # git grep only looks at tracked files; -I skips binaries; exit 1 = no match.
  if git grep -nIE -e "$pattern" -- . "$exclude_self" "$exclude_plan"; then
    found=1
  fi
done

if [[ -f "$denylist" ]]; then
  while IFS= read -r term || [[ -n "$term" ]]; do
    [[ -z "${term//[[:space:]]/}" ]] && continue
    # -F: terms are literal text, not regex. -i: case-insensitive.
    if git grep -nIiF -e "$term" -- . "$exclude_self" "$exclude_plan"; then
      found=1
    fi
  done < "$denylist"
else
  echo "check-leaks: no $denylist found; only generic secret patterns were checked."
fi

if [[ $found -ne 0 ]]; then
  echo "check-leaks: FAILED (matches listed above as file:line)." >&2
  exit 1
fi

echo "check-leaks: OK"
