#!/usr/bin/env bash
set -euo pipefail

runtime="${1:-}"
case "$runtime" in
  claude) command="claude" ;;
  codex) command="codex" ;;
  *) echo "usage: zuwerk-agent-entrypoint <claude|codex>" >&2; exit 64 ;;
esac

mkdir -p /workspace
cat >/root/.zuwerk-agent-runtime <<EOF
runtime=$runtime
updated_at=$(date -u +%FT%TZ)
EOF

tmux has-session -t agent 2>/dev/null || \
  tmux new-session -d -s agent -c /workspace "exec $command"

exec tail -f /dev/null
