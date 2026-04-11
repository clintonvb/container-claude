FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git python3 python3-pip ca-certificates tini curl \
 && rm -rf /var/lib/apt/lists/*

RUN userdel -r node 2>/dev/null || true \
 && useradd -m -u 1000 -s /bin/bash claude

USER claude
WORKDIR /home/claude

ENV HOME=/home/claude
ENV NPM_CONFIG_PREFIX=/home/claude/.npm-global
ENV PATH=/home/claude/.npm-global/bin:$PATH

ARG CLAUDE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION}

WORKDIR /workspace
ENTRYPOINT ["tini","--"]
CMD ["claude","--remote-control"]
