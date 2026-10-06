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
