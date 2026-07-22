FROM docker.io/library/golang:1.26-bookworm@sha256:3f6236bd765f898a2a3c2946112b04097814c4529d44534674700cd07b9c6b4c AS zuwerk-cli-builder

RUN CGO_ENABLED=0 go install github.com/chriopter/zuwerk-cli/cmd/zuwerk@2687a10e420d9044143b7407841550a0aad425e8

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

COPY --from=zuwerk-cli-builder /go/bin/zuwerk /usr/local/bin/zuwerk
COPY docker/agent/entrypoint.sh /usr/local/bin/zuwerk-agent-entrypoint
RUN chmod 0755 /usr/local/bin/zuwerk-agent-entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/zuwerk-agent-entrypoint"]
