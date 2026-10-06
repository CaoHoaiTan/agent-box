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
