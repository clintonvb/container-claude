FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git curl wget ca-certificates tini \
      python3 python3-pip python3-venv \
      ripgrep fd-find jq \
      less vim-tiny \
      unzip zip tree \
      procps iputils-ping dnsutils \
 && ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# Install ttyd (browser-based terminal). Needed for interactive flows like
# `claude auth login` because SSH -> sudo -> docker exec chains mangle the
# TTY chain and CLIs that read from /dev/tty (for OAuth codes, passwords,
# etc.) can't receive input. A real browser terminal sidesteps all of it.
# Static binary from upstream GitHub releases — no Debian package lag.
ARG TTYD_VERSION=1.7.7
RUN curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
 && chmod +x /usr/local/bin/ttyd

# Rename the base image's node user to claude. Preserves UID 1000 and the
# /etc/passwd entry, which Claude Code relies on for home directory lookups.
RUN usermod -l claude -d /home/claude -m node \
 && groupmod -n claude node

USER claude
WORKDIR /home/claude

ENV HOME=/home/claude
ENV PATH=/home/claude/.local/bin:$PATH

# Install Claude Code via Anthropic's official installer (native binary).
# Previously used `npm install -g @anthropic-ai/claude-code` but that path
# hangs inside containers on interactive login flows. The native install
# is what Anthropic recommends and is what HolyClaude / other containerised
# setups use successfully.
RUN curl -fsSL https://claude.ai/install.sh | bash

# Claude Code writes several files directly in $HOME (e.g. ~/.claude.json,
# ~/.claude.json.lock), not just inside ~/.claude/. When the container runs
# with a user: override (e.g. user: "1031:100" to match host bind mount
# ownership), UID 1031 isn't in the claude group and can't write to /home/claude.
# Re-group the home directory to the standard `users` group (GID 100) and add
# group-write so any host user in group 100 can write there. The claude user
# (UID 1000) still has full access as owner.
USER root
RUN chown -R claude:users /home/claude \
 && chmod -R g+w /home/claude
USER claude

# Symlink /home/claude/.claude.json and .claude.json.lock into the bind-mounted
# /home/claude/.claude/ folder so they persist across container recreations.
# Claude writes these at the home directory level (not inside .claude/), so
# without the symlinks every new container starts with a fresh first-run wizard
# (theme selection, trust prompts, etc.) which can't complete in a headless
# remote-control process, causing crash-loops. Symlink targets don't need to
# exist at build time — they'll be created inside the bind mount on first write.
RUN ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json \
 && ln -sf /home/claude/.claude/.claude.json.lock /home/claude/.claude.json.lock

COPY --chown=claude:users server.js /home/claude/server.js
COPY --chown=claude:users entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

WORKDIR /workspace
EXPOSE 3000
ENTRYPOINT ["tini","--"]
CMD ["/home/claude/entrypoint.sh"]
