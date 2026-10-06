# Pinned by tag AND digest (multi-arch index: linux/amd64 + linux/arm64).
FROM node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c

ARG CODEX_VERSION=0.160.1
# Passed to the official installer, which accepts stable|latest|X.Y.Z.
ARG CLAUDE_CODE_VERSION=2.1.285

# Fail a piped command if any stage fails (curl | bash below).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apt versions are not pinned: Debian removes old versions from the mirrors,
# which would break reproducible rebuilds. The base image digest is pinned.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git curl ca-certificates iptables ipset dnsutils ripgrep jq zsh less procps openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force

# Root-owned, read-only for node: the agent must not be able to edit the
# firewall scripts or the allowlist it runs under.
RUN mkdir -p /etc/agent-box/defaults && chmod 755 /etc/agent-box /etc/agent-box/defaults
COPY --chown=root:root --chmod=755 scripts/entrypoint.sh scripts/init-firewall.sh scripts/verify.sh /usr/local/bin/
COPY --chown=root:root --chmod=644 config/allowed-domains.txt /etc/agent-box/allowed-domains.txt
COPY --chown=root:root --chmod=644 config/codex-config.toml config/claude-settings.json /etc/agent-box/defaults/

# The workspace and agent home dirs must exist and belong to node so named
# volumes mounted on them inherit the right ownership.
RUN mkdir -p /workspace /home/node/.claude /home/node/.codex \
    && chown node:node /workspace /home/node/.claude /home/node/.codex

# hadolint ignore=DL3066
# Named users are clearer than uid 1000/0; the image defines both.
USER node
# Keep Claude Code's state (incl. the login in .claude.json) inside the
# volume-mounted ~/.claude, otherwise logins vanish when a box is recreated.
ENV CLAUDE_CONFIG_DIR=/home/node/.claude
ENV PATH="/home/node/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}"

WORKDIR /workspace

# Starts as root only so the entrypoint can install firewall rules; all
# interactive work uses `exec -u node`. There is deliberately no sudo.
# hadolint ignore=DL3002
USER root
# Seed named login volumes at build time: runtime intentionally lacks CHOWN and
# DAC_OVERRIDE, so root cannot populate directories owned by node on first boot.
RUN cp /etc/agent-box/defaults/codex-config.toml /home/node/.codex/config.toml \
    && cp /etc/agent-box/defaults/claude-settings.json /home/node/.claude/settings.json \
    && chown -R node:node /home/node/.codex /home/node/.claude
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
