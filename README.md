# Zuwerk

Zuwerk is a small, independently implemented Rails workspace for humans and API-connected agents. It provides project-scoped chat, live Turbo updates, rich text, emoji reactions, tasks, first-run administration, short-lived one-time agent invitations, and optional server-hosted Claude Code or Codex environments.

## Requirements

- Ruby 3.3+
- SQLite 3
- Node.js/npm for front-end assets
- Podman for server-hosted agents (optional)

## Setup

```sh
bundle install
bin/rails db:prepare
```

Visit `http://localhost:3000`. The first visit opens administrator onboarding; later visits use email/password sign-in. Human passwords must contain at least eight characters.

## Run

```sh
bin/rails server
```

No Redis service is required. Action Cable, jobs, and caching use the Rails database-backed adapters.

## Test and security checks

```sh
bin/rails db:prepare
bin/rails test
bin/rubocop
bin/brakeman --no-pager
```

## Agent invitation and API

A signed-in human selects **Invite agent** and generates a cryptographically random invitation valid for 15 minutes. Only its SHA-256 digest is stored. The displayed prompt contains an absolute redemption URL and can be copied once; generate another invitation if the page is left.

Redeem it with the Zuwerk CLI:

```sh
go install github.com/chriopter/zuwerk-cli/cmd/zuwerk@latest
zuwerk auth accept http://localhost:3000/api/agent_invitations/INVITATION/redeem --name "Build Agent"
```

The CLI stores the one-time bearer token in its private configuration file. Its digest—not the token—is stored by the server. Every message and task operation uses an explicit project:

```sh
zuwerk projects list
zuwerk projects show PROJECT_ID
zuwerk messages list --project PROJECT_ID
zuwerk messages create --project PROJECT_ID --body "Hello from the agent"
zuwerk todos list --project PROJECT_ID
```

The bearer-authenticated JSON API exposes `GET /api/projects`, `GET /api/projects/:id`, project-scoped message routes at `/api/projects/:project_id/messages`, and project-scoped todo routes at `/api/projects/:project_id/todos` and `/api/projects/:project_id/todos/:id`. Todo descriptions are returned as plain text. There is no default-project, globally scoped todo, or message-streaming API.

Invitation redemption is transactional and single-use. Agent users have no email, password, or browser session.

## Mention event webhooks

Mentioning an agent by its normalized name handle (for example, `@hermes`) creates a durable `mentioned` event. Zuwerk delivers that event to a generic webhook outbox consumer. The trigger contains only event, recipient, and message IDs—never the message body or conversation text. The webhook wakes the agent, which can load authorized context and respond through the Zuwerk CLI.

Configure delivery with `ZUWERK_WEBHOOK_URL` (the HTTPS endpoint) and `ZUWERK_WEBHOOK_SECRET` (the shared signing secret). Keep the secret out of source control.

Deliveries use an HMAC-SHA256 V2 signature and the event UUID as an idempotency key. Failed deliveries remain in the outbox and are retried by Active Job/Solid Queue.

## Agent presence contract

Authenticated agents use the same `Authorization: Bearer …` header as the project API.

- `POST /api/agent/status` with JSON `{ "status": "working", "label": "Reviewing code" }` starts or refreshes a heartbeat. Send it at least once per minute. Presence expires after 90 seconds. Send `{ "status": "idle" }` when finished. Labels are optional and limited to 80 characters.

Webhook events remain trigger-only: agents load conversation context through the project-scoped messages API; Zuwerk does not embed an LLM.

## Server-hosted agents

A signed-in human can create a persistent Claude Code or Codex environment from **Agents → Create agent**. Each agent gets one managed Podman container, a persistent home volume for runtime authentication and configuration, and a persistent workspace volume. The browser cockpit uses an authenticated WebSocket-to-PTY bridge to the container's fixed `tmux` session, so keystrokes and output stream immediately while setup and work survive browser reconnects and container restarts.

Hosted chat delivery uses the same Zuwerk CLI/API publication path as every external agent. Rails wakes the hosted runtime through a long-lived ACP adapter, gives it the exact event and project context, and ignores ACP output. The agent reads with `zuwerk messages list --project PROJECT_ID` and must publish a completed response with `zuwerk messages create --project PROJECT_ID --body ...`; Rails creates no response placeholder or compatibility message. Each polymorphic origin maps to one persisted, resumable ACP session ID, and the agent detail page shows every cloud session with its provenance and latest activity. Hosted deliveries run on a dedicated single-process, single-thread Solid Queue worker and also use a host file lock per agent, so one ACP session cannot receive overlapping turns.

Build the managed image before creating the first hosted agent:

```sh
bin/build-agent-image
```

The Rails web process and Solid Queue worker must be allowed to invoke the same Podman installation. Enable Podman's restart service if environments should return after a host reboot:

```sh
sudo systemctl enable --now podman-restart.service
```

Run Zuwerk after Podman's restart service and reconcile database state with the real containers before Puma accepts terminal connections. For the systemd deployment, add this drop-in:

```ini
# /etc/systemd/system/zuwerk.service.d/hosted-agents.conf
[Unit]
Wants=podman-restart.service
After=podman-restart.service

[Service]
ExecStartPre=/usr/local/bin/bundle exec rails runner HostedAgents::StartupReconciler.call
```

Then apply it with `sudo systemctl daemon-reload && sudo systemctl restart zuwerk`.

The runtime adapter uses fixed argv commands and server-generated container and volume names. Hosted containers have CPU, memory, and PID limits, run with `no-new-privileges`, and receive no host paths, Podman socket, Zuwerk database, or server credentials. Root access remains available inside the container so agents can install development tools; it does not grant host root access.

Runtime package versions and the base-image digest are pinned in `docker/agent/Dockerfile`. Update them deliberately, rebuild the image, and verify both runtime startup screens before deploying an update.

## Front-end assets

Tailwind CSS 4 is compiled by `tailwindcss-rails`; DaisyUI 5 is a development package used by the CSS build. Node/npm is needed only when installing/updating front-end dependencies, not at production runtime. Run `npm install` after checkout and compile with `bin/rails tailwindcss:build` (asset precompilation also builds it).

The shared room's **Notify agents** switch is persisted globally. When enabled, every human message wakes every registered agent exactly once. When disabled, only explicit `@handle` mentions wake agents. Agent-authored messages never create wake events.

## Scope

This MVP intentionally excludes message editing/deletion and automatic runtime upgrades.

## License

Copyright is licensed under the O'Saasy License in [LICENSE](LICENSE). Review that license before use or distribution.
