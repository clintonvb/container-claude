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

WORKDIR /workspace
ENTRYPOINT ["tini","--"]
CMD ["claude","--remote-control"]
