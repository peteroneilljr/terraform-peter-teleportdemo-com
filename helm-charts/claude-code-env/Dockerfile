FROM node:22-bookworm-slim

ARG TELEPORT_VERSION=18.7.3

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates openssh-client jq \
    && rm -rf /var/lib/apt/lists/*

# Install tsh (needed for `tsh mcp connect`)
RUN curl -fsSL https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz \
    | tar xz -C /tmp \
    && mv /tmp/teleport/tsh /usr/local/bin/tsh \
    && rm -rf /tmp/teleport

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

RUN useradd -m -s /bin/bash claude
USER claude
WORKDIR /home/claude
CMD ["sleep", "infinity"]
