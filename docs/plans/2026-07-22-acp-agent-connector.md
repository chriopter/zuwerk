# ACP Agent Connector Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Let Zuwerk dispatch queued chat and todo work to locally running Hermes, Claude, and Codex ACP agents through `zuwerk connect`, preserve exact permission requests for human approval, and show truthful live work state in chat and todo views.

**Architecture:** The Go CLI gains a long-running Action Cable client which owns one stdio ACP adapter and forwards bounded NDJSON lines bidirectionally. Rails remains the control plane: `AgentEvent` is the durable turn, `AgentApproval` is the audit record, and an in-process remote ACP registry connects the Action Cable channel to the existing ACP client contract. Existing hosted-container ACP remains supported. The first release deliberately supports one connector and one in-flight turn per agent, queues later events, fails closed on disconnect, and uses correlated product API publications as durable outcomes.

**Tech Stack:** Go 1.26, `github.com/coder/websocket`, Rails 8, Action Cable/Solid Cable, Active Job/Solid Queue, Turbo Streams, Minitest/Capybara.

---

## Wire contract

- Endpoint: existing `/cable` Action Cable WebSocket.
- Authentication: `Authorization: Bearer <agent API token>` header. Tokens never appear in URLs, logs, close reasons, or output.
- Subscription identifier: `{"channel":"AgentConnectorChannel"}`.
- One active connector per agent. A replacement connection closes/rejects the older registration safely.
- Server to connector Action Cable message: `{type:"acp", line:"<one JSON-RPC object>"}`.
- Connector to server Action Cable perform payload: `{type:"acp", line:"<one JSON-RPC object>"}`.
- ACP line maximum: 10 MiB. The Rails inbound transport additionally permits at most 100 queued messages and 20 MiB queued bytes in total. Exactly one complete JSON object is accepted per line/frame; malformed, oversized, or queue-overflow input poisons the live transport, wakes blocked readers, and fails the turn closed.
- Ping/heartbeat: connector emits `{type:"heartbeat"}` every 30 seconds; server stores last seen. Connector reconnects with bounded exponential backoff and jitter while keeping the ACP process only when no request was in flight. If transport drops during a turn or approval, that turn fails closed and its ACP process is replaced.
- Rails owns request IDs and preserves request and option IDs as arbitrary JSON-compatible values without string coercion (including numbers, strings, booleans, arrays, objects, and JSON `null` option IDs).
- ACP lifecycle: `initialize` protocol v2; lazy `session/new` per project/todo origin; `session/prompt`; `session/cancel` notification and drain on cancellation; optional runtime mode only when advertised.

## Durable states

`AgentEvent.state`:

`queued -> running -> waiting_for_approval -> running -> completed`

and terminal `failed` or `cancelled`. Existing acknowledgement/publication columns remain compatible. Only `running` renders a spinner; queued and waiting render distinct non-spinner labels.

`AgentApproval.state`: `pending -> approved|rejected|expired`. The exact runtime option IDs and kinds are persisted. Only a human may resolve. Duplicate identical resolution is idempotent; a conflicting second decision fails. Disconnect expires the pending request and never auto-allows.

## Task 1: Go connector tracer bullet

**Files:**
- Modify: `/root/git/zuwerk-cli/cmd/zuwerk/main.go`
- Create: `/root/git/zuwerk-cli/cmd/zuwerk/connect.go`
- Create: `/root/git/zuwerk-cli/cmd/zuwerk/connect_test.go`
- Modify: `/root/git/zuwerk-cli/go.mod`
- Create: `/root/git/zuwerk-cli/go.sum`
- Modify: `/root/git/zuwerk-cli/README.md`

**TDD slices:**
1. Parse only `zuwerk connect -- <adapter> [args...]`; preserve every existing command.
2. Convert HTTP(S) server URLs to WS(S) `/cable` without token in URL.
3. Authenticate Action Cable with Bearer header and subscribe to `AgentConnectorChannel`.
4. Start one ACP child, bridge server `acp` messages to child stdin and child stdout NDJSON to Action Cable in order.
5. Reject malformed/oversized lines; bound all reads.
6. Stop cleanly on context/SIGINT/SIGTERM, child exit, rejected subscription, or permanent auth failure.
7. Reconnect transient sockets with bounded backoff; do not duplicate child output.
8. Emit heartbeat without concurrent WebSocket writers.
9. Verify token redaction in all errors.
10. Run `gofmt -w .`, `go test -race ./...`, `go vet ./...`, `go build ./...`.

## Task 2: Rails connector transport and durable turn

**Files:**
- Modify: `app/channels/application_cable/connection.rb`
- Create: `app/channels/agent_connector_channel.rb`
- Create: `app/services/agent_connectors/registry.rb`
- Create: `app/services/agent_connectors/transport.rb`
- Modify/Create migrations and models for connector presence and `AgentEvent.state` timestamps.
- Modify: `app/jobs/deliver_agent_event_job.rb`
- Modify: `app/models/agent_event.rb`
- Modify: `app/services/hosted_agents/acp_client.rb`
- Modify: `app/services/hosted_agents/acp_pool.rb`
- Modify: `app/services/hosted_agents/chat_bridge.rb`
- Add focused channel/model/service/job tests.

**TDD slices:**
1. Cable accepts a valid agent Bearer token and still accepts human session auth for browser channels; rejects all others.
2. Agent channel registers exactly one bounded transport per agent and records presence/heartbeat.
3. Transport forwards exact NDJSON in both directions and fails blocked readers on disconnect.
4. `AgentEvent` validates transitions and atomically claims one running/waiting event per recipient; later events remain queued FIFO.
5. Dispatcher prefers a live connector, falls back to existing hosted-container ACP or webhook, and never dispatches one event twice.
6. ACP client accepts an injected transport, protocol v2, lazy sessions, update callbacks, typed permission request IDs, cancel/drain, and bounded timeouts.
7. Completion requires one correlated project message/todo comment; failure releases the agent and schedules the next queued event.

## Task 3: Human approvals

**Files:**
- Create migration/model `AgentApproval`.
- Create controller/routes for human-only approval resolution.
- Modify ACP client/turn coordinator to wait on the exact request and option.
- Add model/controller/service/system tests.

**TDD slices:**
1. Persist bounded title/tool/details/options with unique event+request correlation.
2. Transition turn to `waiting_for_approval`; never auto-select `allow_once`.
3. Human chooses an offered option; exact option ID returns to same live request and turn resumes.
4. Same decision is idempotent; conflicting/invalid/agent-token decisions fail.
5. Disconnect/cancel expires pending approval and sends cancelled only when the original process is still live.

## Task 4: Chat and todo live UI

**Files:** relevant chat/todo partials, Turbo broadcasts, CSS, and system tests.

**Requirements:**
- Chat header shows the active agent with spinner only in `running`.
- Todo card/detail shows the same concrete turn spinner while running.
- `queued`, `waiting for approval`, `failed`, and completed are visually and semantically distinct.
- Approval card appears in the originating chat/todo, with exact Allow/Reject buttons and accessible live-region behavior.
- Turbo updates all surfaces without reload; completion removes spinner and appends correlated publication exactly once.

## Task 5: Runtime simulations

Create deterministic fake ACP adapters for `hermes`, `claude`, and `codex` that exercise initialize/new/prompt, status and tool updates, permission request, selected/rejected outcome, final correlated publication, cancellation, malformed output, EOF, and reconnect. Drive each through the real Go connector plus Rails cable endpoint where feasible; otherwise combine a real connector integration test with Rails protocol tests. Verify chat and todo spinner transitions in Capybara for every runtime label.

## Task 6: Release gates

- CLI: `gofmt`, `go test -race ./...`, `go vet ./...`, `go build ./...`.
- Rails: full model/integration/job/service/system/JavaScript suite, RuboCop, Brakeman, Bundler Audit, `git diff --check`.
- Independent spec and code-quality review; fix every critical/important issue.
- Stage only scoped files; signed commits in both repositories; push `main` only after both trees are clean and all gates green.
- Deploy CLI binary and Rails migrations/assets/service; verify `/up`, connector registration, and browser chat/todo smoke flows.
