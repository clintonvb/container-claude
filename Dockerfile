FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git python3 python3-pip ca-certificates tini curl \
 && rm -rf /var/lib/apt/lists/*

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

WORKDIR /workspace
ENTRYPOINT ["tini","--"]
CMD ["claude","--remote-control"]
