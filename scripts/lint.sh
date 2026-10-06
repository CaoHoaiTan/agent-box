#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
shell_files=("$repo_root/bin/agentbox" "$repo_root"/scripts/*.sh)

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${shell_files[@]}"
else
  # Send source on stdin; lint tools do not need any host directories mounted.
  for script in "${shell_files[@]}"; do
    echo "ShellCheck: ${script#"$repo_root/"}"
    docker run --rm -i koalaman/shellcheck:v0.10.0 - < "$script"
  done
fi

if command -v hadolint >/dev/null 2>&1; then
  hadolint "$repo_root/Dockerfile"
else
  docker run --rm -i hadolint/hadolint:v2.12.0-alpine < "$repo_root/Dockerfile"
fi
echo 'lint: OK'
