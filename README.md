# agent-box

Run AI coding agents (Claude Code, OpenAI Codex CLI) inside isolated Docker
containers with an outbound network allowlist.

> Work in progress. Full documentation is added in a later phase.

## Leak guard

`scripts/check-leaks.sh` scans tracked files for generic secret patterns and,
if present, for terms in a local, git-ignored `.leak-denylist` file (one
case-insensitive term per line).

Install it as a git pre-commit hook:

```bash
ln -s ../../scripts/check-leaks.sh .git/hooks/pre-commit
```

## Pinned versions

Set at build time via `ARG`s in the `Dockerfile`:

| ARG | Default | Notes |
|---|---|---|
| `CODEX_VERSION` | `0.160.1` | npm package `@openai/codex` |
| `CLAUDE_CODE_VERSION` | `2.1.285` | passed to the official installer (`stable`, `latest` or `X.Y.Z`) |

Override with `docker build --build-arg CODEX_VERSION=... .`. The base image is
pinned by tag and digest.

## Skipping Claude Code permission prompts (opt-in)

By default `config/claude-settings.json` keeps Claude Code's normal permission
prompts. Inside a box you may set `"permissions": {"defaultMode": "bypassPermissions"}`
in `/home/node/.claude/settings.json`. Trade-off: the agent then runs any
command without asking, and the only barriers left are the container, the
firewall and the workspace mount. Anything in the workspace can be modified or
sent to allowlisted domains without your review.

## Outbound firewall

At startup, the root entrypoint resolves the domains in
`config/allowed-domains.txt` to IPv4 addresses and installs an outbound default
`DROP` policy. IPv6 outbound traffic is blocked. If firewall setup or its
blocked-destination self-test fails, the container exits. Agent configuration
defaults are copied on first start; existing settings and logins are preserved.

`STRICT_DNS=0` (default) allows TCP and UDP port 53 to any destination. This
permits DNS exfiltration: an agent could encode workspace data in DNS queries
to an external resolver. `STRICT_DNS=1` restricts port 53 to Docker's embedded
resolver, `127.0.0.11`. Use a user-defined Docker network for that resolver;
strict mode may fail to resolve domains on the default bridge. Docker's resolver
can still forward arbitrary DNS names, so strict mode does not eliminate DNS
exfiltration.

The firewall permits established connections and loopback traffic (with the
DNS restriction above). Allowlisting IPs also allows other domains that share
those IPs. CDN addresses may change; rerun `/usr/local/bin/init-firewall.sh`
as root in the box to refresh them. Refreshing rebuilds the rules and IP set;
established connections remain allowed. `EXTRA_ALLOWED_CIDRS` accepts
comma-separated IPv4 CIDRs for optional local services; add only subnets the
box should reach.

## Two workspaces

Copy `.env.example` to `.env` to customize workspace paths and resource limits,
then start both boxes:

```bash
docker compose up -d --build
docker compose logs
docker compose exec -u node box-personal zsh
docker compose exec -u node box-work zsh
```

Each box mounts only its configured workspace, has separate named volumes for
agent settings and logins, and uses its own Docker network. Neither box can
resolve the other's service name. Both drop all capabilities except `NET_ADMIN`
and `NET_RAW`, enable `no-new-privileges`, and limit CPUs, memory and processes.
Always use `-u node` for interactive commands.

Default settings are prepared with `node` ownership during the image build, so
Docker can initialize fresh login volumes without granting runtime `CHOWN`.
Existing volumes retain their settings when the image is rebuilt. Stop both
boxes with `docker compose down`; this keeps their login volumes.

## Command line

Run `bin/agentbox` from any directory, or add this repository's `bin` directory
to your `PATH`. Each command supports `--help`:

```bash
bin/agentbox up                 # build/start both boxes and wait for readiness
bin/agentbox up work            # just the work box
bin/agentbox shell work         # zsh as node
bin/agentbox verify personal
bin/agentbox verify work
bin/agentbox refresh-firewall work
bin/agentbox down               # stop both; keep settings and logins
bin/agentbox reset personal     # requires typing: reset personal
```

`reset` deletes only the selected box and its two login volumes. It keeps the
workspace and the other box. It requires `jq` on the host to read Compose's
resolved volume names. No confirmation, EOF or any other response cancels it.

`verify` reports eight PASS/FAIL checks and exits nonzero on failure. HTTP
authentication errors from provider endpoints count as reachable. Its SSH
check rejects any content in `/home/node/.ssh`, even if created inside the box;
keep SSH keys on the host. The workspace write probe is removed afterwards.

`bin/agentbox fetch <box> <repo> <branch> <clean-clone-path>` accepts a repo
directory within that box's workspace and requires host `jq`. Its safe-fetch
helper is implemented in phase 6; until then, it exits with an explicit error.

`make up`, `make down`, `make shell-personal`, `make shell-work`, `make verify`,
`make lint` and `make leaks` wrap the CLI and scripts. Use `BOX=personal` or
`BOX=work` with `make up` and `make down` to select one box. `make lint` uses
host ShellCheck/Hadolint when available, otherwise pinned tool images through
Docker, with source passed on stdin.
