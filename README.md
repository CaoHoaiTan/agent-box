# agent-box

Run Claude Code and OpenAI Codex CLI in isolated Docker containers with an outbound network allowlist. Personal and work boxes have separate workspaces, agent login volumes and networks. Review changes and push from an independent host clone using the safe-fetch helper.

## Protection and limits

Only the selected workspace is mounted into each box; host SSH/GPG keys, cloud credentials, other projects and the Docker socket are excluded. Agents run as `node`, without sudo, and outbound IPv4 is allowlisted while outbound IPv6 is blocked. Containers start as root only to set up the firewall.

Code and prompts still go to the model provider. Prompt injection can use allowlisted destinations, shared CDN IPs and DNS to send data out. Runtime escape vulnerabilities remain possible. Read the [threat model](SECURITY.md) before placing code in a box.

## Requirements

- macOS on Apple Silicon: Colima, Docker CLI, Compose and Buildx; follow [the Colima setup](docs/macos-colima.md) first to restrict VM mounts.
- Linux: Docker Engine, Compose and Buildx; see [Linux setup](docs/linux.md).
- Bash, Git, Make, `jq` and `realpath` on the host. Recent macOS includes realpath; older systems can install GNU coreutils.
- Compose 2.33.1 or newer for explicit default gateway selection.
- Network access for builds and an agent account for interactive use.

## Quick start

After setting up Docker/Colima, run on the host:

```bash
git clone https://github.com/your-org/agent-box.git
cd agent-box
cp .env.example .env
export PATH="$PWD/bin:$PATH"
make up
make verify
agentbox shell work
```

Replace `your-org/agent-box` with your fork's URL. Both boxes must log `Firewall OK`; `make verify` must report all eight checks passing for each box. The CLI waits for firewall and entrypoint readiness and returns nonzero on startup failure. Change workspace paths, CPUs and memory in `.env` if needed.

Inside the box, start and log in to either agent:

```bash
claude
# Or:
codex login --device-auth
codex
```

Open the printed login link in your host browser. For Claude, paste a login code into the container terminal when prompted. Codex device login may require enabling device-code authentication in account settings or asking your workspace admin; see [official OpenAI authentication guidance](https://learn.chatgpt.com/docs/auth) and [Claude authentication guidance](https://code.claude.com/docs/en/authentication). Logins stay in each box's own named volumes. Never copy Git push credentials or production secrets into a box.

## Daily usage

```bash
agentbox up work
agentbox shell personal
agentbox verify work
agentbox refresh-firewall work
agentbox down                    # stop both, retain data
agentbox reset personal          # typed confirmation; wipe personal agent logins
agentbox fetch work project ai/task ../project-review
```

Every subcommand supports `--help`. Fetch requires a trusted, independent clone outside both workspaces with a local `main` branch. It prints commit, file and risky-path summaries and review/push commands; it never pushes. Follow the [review workflow](docs/workflow.md) instead of running host Git or opening a host editor in an agent-modified workspace.

Make targets: `up`, `down`, `shell-personal`, `shell-work`, `verify`, `lint`, `leaks`. Select one box with `make up BOX=work` or `make down BOX=personal`. Lint uses local ShellCheck/Hadolint, or pinned tool images with source on stdin and no host directory mounts.

The SSH verification check refuses any content in `/home/node/.ssh`, including keys created inside the box. Workspace write probes are removed afterwards. Reset keeps workspace files, the other box and optional database volumes. Any response other than the exact requested phrase, including EOF, cancels it.

## Allowed domains and DNS

Edit `config/allowed-domains.txt` (one domain per line, `#` comments), then rebuild/recreate to copy the file into the image:

```bash
agentbox up
agentbox refresh-firewall personal
agentbox refresh-firewall work
```

Refresh alone re-resolves the image's current allowlist; it cannot read edits made only on the host. Unresolved domains warn and are omitted. Refresh may interrupt new requests; established connections remain allowed. An IP allowlist also permits other domains sharing those IPs.

`STRICT_DNS=0` allows TCP/UDP port 53 to any destination and permits DNS exfiltration. `STRICT_DNS=1` restricts port 53 to Docker's embedded resolver, which still forwards arbitrary names; strict mode does not eliminate DNS exfiltration. Set it in `.env` and run `agentbox up` to recreate containers. DNS restrictions precede loopback rules.

## Versions and upgrades

| Component | Pinned default |
|---|---|
| Base image | `node:22-bookworm-slim`, multi-architecture digest in Dockerfile |
| `CODEX_VERSION` | `0.160.1` (`@openai/codex` npm package) |
| `CLAUDE_CODE_VERSION` | `2.1.285` (official native installer accepts a version) |

Change ARG defaults and the base digest when upgrading, then run `agentbox up` and `make verify`. For a build override:

```bash
docker compose build --build-arg CODEX_VERSION=0.160.1 --build-arg CLAUDE_CODE_VERSION=2.1.285
docker compose up -d
make verify
```

Defaults are seeded with node ownership during build so fresh login volumes work with only NET_ADMIN/NET_RAW. Existing volumes retain settings on upgrades. CI checks installed versions; updates made after startup can differ from image defaults.

## FAQ

**Can I bypass permission prompts?** Claude retains prompts by default. Inside the box only, set `"permissions": {"defaultMode": "bypassPermissions"}` in `/home/node/.claude/settings.json` to opt in. Commands then run without asking; container/firewall boundaries remain. Codex's default `danger-full-access` relies on those boundaries and must never be copied to host configuration.

**Can I use a local database?** The optional `services` profile gives each box private Postgres/Redis; see [optional services](docs/optional-services.md). Use disposable development data only.

**Why does login/network access fail?** Check logs, DNS and allowlisted hosts; see [troubleshooting](docs/troubleshooting.md). HTTP 401/403 counts as reachable; verify does not test paid model access.

**Can I push from a box?** No Git push credentials are supplied. Manually putting a token in a workspace defeats that boundary. Push from the reviewed clean clone.

## Leak guard and CI

`scripts/check-leaks.sh` scans tracked files for generic secret patterns and optional identifying terms from a git-ignored `.leak-denylist` file (one literal, case-insensitive term per line). Populate it privately; without it, only generic patterns are checked. Install a hook:

```bash
ln -s ../../scripts/check-leaks.sh .git/hooks/pre-commit
make leaks
```

CI lints scripts/Dockerfile, runs the generic leak scan, builds both architectures on native runners and runs isolation checks on amd64. It uses no model credentials, publishes no image and uses only SHA-pinned official actions. See [GitHub runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
