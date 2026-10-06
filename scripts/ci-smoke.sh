#!/usr/bin/env bash
set -euo pipefail

[[ $# == 1 ]] || { echo 'Usage: ci-smoke.sh <image>' >&2; exit 2; }
image="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
workspace="$repo_root/workspaces/personal"
network="agentbox-ci-$$"
container="agentbox-ci-$$"
cleanup() {
  docker rm --force "$container" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker network create "$network" >/dev/null
docker run -d --name "$container" --network "$network" \
  --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_RAW \
  --security-opt no-new-privileges:true --init \
  --mount "type=bind,src=$workspace,dst=/workspace" \
  -e STRICT_DNS=1 "$image" >/dev/null

ready=0
for ((attempt = 0; attempt < 120; attempt++)); do
  logs="$(docker logs "$container" 2>&1)"
  if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" != true ]]; then
    printf '%s\n' "$logs" >&2
    echo 'ci-smoke: container exited before readiness.' >&2
    exit 1
  fi
  if [[ "$logs" == *'Firewall OK'* ]] && docker exec -u node "$container" pgrep -x sleep >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
docker logs "$container"
[[ "$ready" == 1 ]] || { echo 'ci-smoke: startup timed out.' >&2; exit 1; }
docker exec -u node "$container" /usr/local/bin/verify.sh
docker exec -u node "$container" claude --version
docker exec -u node "$container" codex --version
docker exec -u node "$container" bash -c '! command -v sudo'
# The same strict host-path checks apply in CI because only the workspace
# subdirectory is mounted, not the runner home or checkout credentials.
echo 'ci-smoke: OK'
