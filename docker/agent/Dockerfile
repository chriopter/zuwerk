FROM docker.io/library/node:22-bookworm@sha256:175215a1f306ed5df592434b99cc2019f70624373fe49cb659240a618a846aed

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash ca-certificates curl git less procps tmux \
    && npm install --global \
      @anthropic-ai/claude-code@2.1.217 \
      @openai/codex@0.145.0 \
      @agentclientprotocol/claude-agent-acp@0.60.0 \
      @agentclientprotocol/codex-acp@1.1.5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/agent/entrypoint.sh /usr/local/bin/zuwerk-agent-entrypoint
RUN chmod 0755 /usr/local/bin/zuwerk-agent-entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/zuwerk-agent-entrypoint"]
