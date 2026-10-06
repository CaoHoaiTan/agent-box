# agent-box

Run AI coding agents (**Claude Code** and **OpenAI Codex CLI**) inside isolated
Docker containers that can only see one project folder and can only talk to a
short list of allowed internet domains.

The goal: you can let an agent edit, run and commit code without giving it
access to your SSH keys, cloud credentials, other projects, or the open
internet.

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [What it protects, and what it does not](#what-it-protects-and-what-it-does-not)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Daily usage](#daily-usage)
- [Command reference](#command-reference)
- [Configuration](#configuration)
- [Allowed domains and DNS](#allowed-domains-and-dns)
- [Review and push workflow](#review-and-push-workflow)
- [Optional Postgres and Redis](#optional-postgres-and-redis)
- [Versions and upgrades](#versions-and-upgrades)
- [Repository layout](#repository-layout)
- [FAQ](#faq)
- [Leak guard and CI](#leak-guard-and-ci)

## Why this exists

Coding agents run shell commands, read files and make network requests on your
behalf. On your normal machine that means they run with *your* permissions:
your home directory, your `~/.ssh`, your cloud config, every repository you
have cloned. A prompt-injected web page or a malicious dependency can steer the
agent into reading or sending those things.

agent-box shrinks the blast radius. The agent lives in a container with:

1. **One mounted folder** (its workspace) and nothing else from your machine.
2. **A default-deny outbound firewall** with an allowlist of domains.
3. **No privileges** to change that firewall, no `sudo`, no Docker socket.
4. **No credentials** for pushing code. You review and push yourself.

It also keeps **two separate boxes**, `personal` and `work`, so an agent
working on one cannot see the other's code or logins.

## How it works

### The big picture

```
 HOST (your Mac / Linux machine)
 ┌──────────────────────────────────────────────────────────────────┐
 │  ~/.ssh  ~/.aws  ~/.gitconfig  other projects   ← never mounted  │
 │                                                                  │
 │  workspaces/personal/            workspaces/work/                │
 │        │ bind mount                    │ bind mount              │
 │  ┌─────▼──────────────┐         ┌──────▼─────────────┐           │
 │  │ box-personal       │         │ box-work           │           │
 │  │  /workspace        │         │  /workspace        │           │
 │  │  ~/.claude (vol)   │         │  ~/.claude (vol)   │           │
 │  │  ~/.codex  (vol)   │         │  ~/.codex  (vol)   │           │
 │  │  firewall: allow-  │         │  firewall: allow-  │           │
 │  │  list only         │         │  list only         │           │
 │  └─────┬──────────────┘         └──────┬─────────────┘           │
 │   network "personal"              network "work"   (separate:    │
 │        │                               │           boxes cannot  │
 │        └──────────► internet ◄─────────┘           reach each    │
 │              (only allowlisted domains)            other)        │
 └──────────────────────────────────────────────────────────────────┘
```

### Step by step

**1. One image, two boxes.** The `Dockerfile` builds a single image based on
`node:22-bookworm-slim` (pinned by digest). It contains Git, Claude Code,
Codex CLI and the firewall tooling (`iptables`, `ipset`). `docker-compose.yml`
starts that image twice as `box-personal` and `box-work`. Each box gets its own
workspace folder, its own named volumes for agent logins, and its own Docker
network.

**2. Start as root, work as `node`.** A container's entrypoint
(`scripts/entrypoint.sh`) must run as root, because only root can install
firewall rules. It does three things:

1. runs `scripts/init-firewall.sh`; if the firewall fails, the container exits
   instead of staying up unprotected,
2. makes sure the agent config directories exist and belong to `node`,
3. runs `sleep infinity` to keep the container alive.

You never work as root. `agentbox shell` runs `docker compose exec -u node`,
so everything you or the agent do happens as the unprivileged `node` user.
There is no `sudo` in the image, `no-new-privileges` is set, and all Linux
capabilities are dropped except `NET_ADMIN` and `NET_RAW` (needed for the
firewall). The `node` user itself holds zero capabilities, so it cannot run
`iptables`.

**3. The firewall** (`scripts/init-firewall.sh`). It builds the rules in this
order on the `OUTPUT` chain (traffic leaving the container):

| Order | Rule | Purpose |
|---|---|---|
| 0 | Default policy `DROP`, flush old rules | Deny first, so a refresh never opens a gap |
| 1 | DNS (port 53) | To anywhere, or only to Docker's resolver `127.0.0.11` if `STRICT_DNS=1` |
| 2 | Loopback | Local processes talking to each other |
| 3 | `ESTABLISHED,RELATED` | Replies to connections that were already allowed |
| 4 | Destinations in ipset `agentbox-allowed` | The allowlist |
| 5 | `EXTRA_ALLOWED_CIDRS` | The box's own private service subnet (Postgres/Redis) |
| – | Everything else | Dropped. IPv6 output is dropped entirely |

The allowlist is a list of **domains** (`config/allowed-domains.txt`), but
iptables works on **IP addresses**. At startup the script resolves each domain
with `dig` and adds the IPv4 addresses to the ipset. The result is a snapshot:
if a CDN changes an IP later, run `agentbox refresh-firewall`. Finally the
script proves the firewall works by trying to reach `https://example.com`; if
that succeeds it prints `FIREWALL FAIL` and exits non-zero. On success it
prints `Firewall OK`.

**4. Isolation between boxes.** Each box has:

- its own bind-mounted workspace (`/workspace`),
- its own named volumes `*-claude` and `*-codex` holding agent logins,
- its own Docker network, so one box cannot resolve or connect to the other.

**5. Agent config and logins.** Defaults from `config/` are baked into the
image and seeded into the login volumes: Codex gets `sandbox_mode =
"danger-full-access"` (safe *only* because the container and firewall are the
sandbox) and Claude Code keeps its normal permission prompts. The image sets
`CLAUDE_CONFIG_DIR=/home/node/.claude`, so Claude's login and state live inside
the volume and survive container re-creation. Run `claude` / `codex` login once
per box.

**6. Getting code out.** The box has no SSH key, GPG key or push credentials.
The agent commits locally, inside the workspace repo. You then use
`agentbox fetch`, which fetches that branch into a *separate clean clone* on
the host, without ever running Git inside the agent-controlled folder. This
matters because an agent can write to `.git/hooks` and `.git/config`
(`core.fsmonitor`, `core.sshCommand`), which would run code the next time you
use Git there. See [Review and push workflow](#review-and-push-workflow).

## What it protects, and what it does not

**Protects against**

- Reading host files outside the workspace (home, keys, other projects).
- Reading the other box's code or logins.
- Arbitrary outbound network connections (only allowlisted IPv4 destinations).
- Privilege escalation inside the box (no `sudo`, no capabilities for `node`).
- Pushing code with your credentials (none are present).

**Does not protect against**

- Your code and prompts are sent to the model provider. That is how the agent
  works.
- Prompt injection can still send data to *allowed* domains. An IP allowlist
  also allows other sites sharing the same CDN IPs. GitHub is reachable
  (read-only only because no credentials exist).
- DNS exfiltration. With `STRICT_DNS=0` (default) DNS goes to any server;
  `STRICT_DNS=1` still forwards arbitrary names through Docker's resolver.
- Container or VM escape vulnerabilities. Keep Docker/Colima updated. Native
  Linux Docker shares the host kernel; a VM is stronger.
- Anything you put in a workspace, including `.env` files and secrets.

Read the full [threat model](SECURITY.md) before putting real code in a box.

## Requirements

- **macOS (Apple Silicon)**: Colima, Docker CLI, Compose, Buildx. Follow
  [the Colima guide](docs/macos-colima.md) first to restrict VM mounts. The
  setup was also tested on Docker Desktop; make sure only the folders you intend
  are shared with its VM.
- **Linux**: Docker Engine, Compose, Buildx. See [Linux setup](docs/linux.md).
- On the host: Bash, Git, Make, `jq`, `realpath`.
- Docker Compose 2.33.1+ (the boxes use `gw_priority` to pick their default
  route).
- Internet access for the first build, plus an account for each agent.

## Quick start

```bash
git clone https://github.com/your-org/agent-box.git   # use your fork's URL
cd agent-box
cp .env.example .env
export PATH="$PWD/bin:$PATH"     # optional: lets you type `agentbox` directly
make up                          # builds the image, starts both boxes
make verify                      # 8 isolation checks per box, expect all PASS
agentbox shell work              # open a shell inside the work box
```

Expected output of `make up`: each box logs `Firewall OK`, then
`agentbox: box-<name> ready.` A single `init-firewall: warning: no IPv4
addresses for <domain>` is harmless; it means that domain currently has no
A record and is simply skipped.

Inside the box, log in once (stored only in that box's volume):

```bash
claude                        # open the printed URL on the host, paste the code back
# or
codex login --device-auth     # open the printed link on the host, enter the code
```

Codex device login may need to be enabled in account settings or by a workspace
admin; see [troubleshooting](docs/troubleshooting.md). Never copy Git push
credentials or production secrets into a box.

## Daily usage

1. Put a project in a box's workspace, **cloned on the host** (so your host
   credentials stay on the host):
   ```bash
   git clone git@github.com:your-org/project.git workspaces/work/project
   ```
2. Enter the box, create an `ai/<task>` branch and start the agent:
   ```bash
   agentbox shell work
   cd /workspace/project
   git switch -c ai/task
   claude        # or: codex
   ```
3. The agent commits locally only.
4. Back on the host, fetch into a separate clean clone, review, then push from
   there:
   ```bash
   agentbox fetch work project ai/task ../project-review
   ```
5. Stop the boxes when done: `agentbox down` (keeps logins and data).

Do not open workspace folders in a host editor's normal mode. In VS Code use
**Dev Containers: Attach to Running Container** and open `/workspace`.

## Command reference

Every subcommand supports `--help`. `<box>` is `personal` or `work`.

| Command | What it does |
|---|---|
| `agentbox up [box]` | Build and start one or both boxes, wait until the firewall is OK and the entrypoint is done (120 s limit per box) |
| `agentbox down [box]` | Stop the box(es); containers and volumes are kept |
| `agentbox shell <box>` | Open `zsh` as the `node` user |
| `agentbox verify <box>` | Run the 8 isolation checks as `node`; non-zero exit on any failure |
| `agentbox refresh-firewall <box>` | Re-resolve the allowlist and rebuild the firewall (as root) |
| `agentbox reset <box>` | After typing `reset <box>`, remove that box and its login volumes. Workspace files are kept |
| `agentbox fetch <box> <repo> <branch> <clean-clone>` | Safely fetch an agent branch into a clean clone for review |

Make targets: `up`, `down`, `shell-personal`, `shell-work`, `verify`, `lint`,
`leaks`. Limit to one box with `make up BOX=work`.

**What `verify` checks**

1. `api.anthropic.com` is reachable
2. `api.openai.com` is reachable
3. `example.com` is blocked
4. No SSH content and no host home paths visible
5. `/var/run/docker.sock` does not exist
6. `iptables -L` fails (not root)
7. `sudo` is absent
8. `/workspace` is writable

(401/403 responses count as reachable; verify does not test model access.)

## Configuration

Copy `.env.example` to `.env` (git-ignored) and edit:

| Variable | Default | Meaning |
|---|---|---|
| `PERSONAL_WORKSPACE` | `./workspaces/personal` | Host folder mounted in `box-personal` |
| `WORK_WORKSPACE` | `./workspaces/work` | Host folder mounted in `box-work` |
| `BOX_CPUS` | `4` | CPU limit per box |
| `BOX_MEMORY` | `4g` | Memory limit per box |
| `STRICT_DNS` | `0` | `1` = port 53 only to Docker's resolver |
| `*_POSTGRES_PASSWORD`, `*_REDIS_PASSWORD` | `changeme` | Optional services only |
| `PERSONAL_SERVICES_SUBNET`, `WORK_SERVICES_SUBNET` | `172.30.10.0/24`, `172.30.20.0/24` | Private subnets for optional services |

After changing `.env`, run `agentbox up` to recreate the containers.

## Allowed domains and DNS

Edit `config/allowed-domains.txt` (one domain per line, `#` for comments), then
rebuild and refresh:

```bash
agentbox up
agentbox refresh-firewall personal
agentbox refresh-firewall work
```

`refresh-firewall` alone only re-resolves the list already inside the image; it
cannot see edits you made on the host. Keep the list as short as possible.

`STRICT_DNS=0` allows port 53 to any destination, which lets a malicious agent
smuggle data out through DNS queries. `STRICT_DNS=1` limits port 53 to Docker's
embedded resolver, which reduces but does not eliminate this.

## Review and push workflow

`agentbox fetch <box> <repo> <branch> <clean-clone>` is the only supported way
to bring agent commits back to the host. The helper (`scripts/safe-fetch.sh`):

- runs Git **only** inside your clean clone, with hooks and `fsmonitor`
  disabled, submodules skipped and fetched objects verified,
- never runs Git inside the workspace repo,
- refuses to touch `main`, or clones that are inside a workspace,
- prints the commits, changed files, and a **warning list** of risky paths
  (`package.json`, lockfiles, `*.sh`, `Makefile`, `Dockerfile`, `.github/`,
  `.husky/`, `.vscode/`, `.claude/`, `.codex/`),
- prints the exact commands to review and push, and **never pushes**.

You then review the diff and push from the clean clone with your own keys.
Fetched commits keep their original signatures; to sign with your key,
cherry-pick with `-S` into a new branch. Full details: [workflow](docs/workflow.md).

## Optional Postgres and Redis

A compose profile `services` adds disposable Postgres 16 and Redis 7 per box.
Each box's services sit on an `internal: true` network attached only to that
box, so the other box cannot reach them, and the box's firewall allows only its
own services subnet. Use development data only, never real or shared company
databases.

```bash
COMPOSE_PROFILES=services bin/agentbox up
```

See [optional services](docs/optional-services.md).

## Versions and upgrades

| Component | Pinned default |
|---|---|
| Base image | `node:22-bookworm-slim`, pinned by tag and multi-arch digest |
| `CODEX_VERSION` | `0.160.1` (npm package `@openai/codex`) |
| `CLAUDE_CODE_VERSION` | `2.1.285` (official installer accepts a version) |

To upgrade, change the `ARG` defaults (and the base digest if desired), then:

```bash
agentbox up
make verify
```

Or override at build time:

```bash
docker compose build --build-arg CODEX_VERSION=<version> --build-arg CLAUDE_CODE_VERSION=<version>
```

Existing login volumes keep their settings across upgrades.

## Repository layout

```
bin/agentbox            main CLI
Dockerfile              the single image
docker-compose.yml      two boxes, networks, volumes, optional services
.dockerignore           keeps workspaces/.env/.git out of the build context
config/                 allowed-domains.txt, codex-config.toml, claude-settings.json
scripts/entrypoint.sh   root: firewall, config ownership, sleep
scripts/init-firewall.sh  iptables + ipset rules and self-test
scripts/verify.sh       isolation self-test (runs inside a box)
scripts/safe-fetch.sh   host-side safe fetch into a clean clone
scripts/check-leaks.sh  denylist and secret scan
scripts/lint.sh         ShellCheck + Hadolint (local or pinned Docker images)
scripts/ci-smoke.sh     CI firewall/isolation smoke test
docs/                   macOS/Linux setup, workflow, services, troubleshooting
workspaces/             one folder per box; contents are git-ignored
```

## FAQ

**Can I skip Claude Code's permission prompts?** Claude keeps its prompts by
default. Inside a box only, you can set
`"permissions": {"defaultMode": "bypassPermissions"}` in
`/home/node/.claude/settings.json`. The trade-off: the agent then runs any
command without asking, and the only barriers left are the container, the
firewall and the workspace mount. Codex's default `danger-full-access` relies on
the same boundaries and must never be used on a host machine.

**Why is a domain not reachable?** Add it to `config/allowed-domains.txt`,
run `agentbox up`, then `agentbox refresh-firewall <box>`. If an allowed
domain stops working, its CDN IPs probably changed; refresh the firewall. See
[troubleshooting](docs/troubleshooting.md).

**Can the agent push to GitHub?** No credentials are supplied, so pushes fail.
Putting a token into a workspace defeats that boundary.

**Is this a hard security boundary?** It is strong isolation for accidents and
prompt injection, not a guarantee. Containers share a kernel; a VM-based runtime
(Colima, Docker Desktop) adds a layer. See [SECURITY.md](SECURITY.md).

**Where are my agent logins stored?** In named Docker volumes
(`*-claude`, `*-codex`) on the Docker VM disk, one pair per box.
`agentbox reset <box>` deletes them.

## Leak guard and CI

`scripts/check-leaks.sh` scans tracked files for generic secret patterns and
for terms in an optional local, git-ignored `.leak-denylist` file (one
case-insensitive term per line, e.g. names you never want committed). Without
the file, only the generic patterns are checked. Install it as a hook:

```bash
ln -s ../../scripts/check-leaks.sh .git/hooks/pre-commit
make leaks
```

CI (`.github/workflows/ci.yml`) runs ShellCheck and Hadolint, the generic leak
scan, validates Compose, builds `linux/amd64` and `linux/arm64`, and runs the
firewall and isolation smoke test on amd64. It uses no model credentials,
publishes nothing, and uses only SHA-pinned official `actions/*` and `docker/*`
actions.

## License

MIT, see [LICENSE](LICENSE).
