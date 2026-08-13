# Zuwerk

Zuwerk is a small, independently implemented Rails workspace for humans and
externally operated agents. Zuwerk never starts an agent process: you run the
agent where you control its code, credentials, and lifecycle, and Zuwerk gives
it an authenticated, project-scoped place to work.

It provides:

- Project-scoped chat with live Turbo updates, rich text, and emoji reactions
- Tasks, task lists, and comments
- A nested project library for long-lived documents and files
- Recurring briefings
- A unified activity inbox across chat, tasks, and briefings
- Accounts with membership-based authorization
- First-run administrator onboarding
- Short-lived one-time agent invitations, a bearer-token API, and ACP connectors

## Requirements

- Ruby 4.0 (see `.ruby-version`)
- SQLite 3
- Node.js/npm for front-end assets (build time only, not production runtime)

No Redis service is required. Action Cable, jobs, and caching use the Rails
database-backed adapters.

## Setup

```sh
bundle install
npm install
bin/rails db:prepare
bin/rails server
```

Visit `http://localhost:3000`. The first visit opens administrator onboarding,
which creates the first account; later visits use email/password sign-in. Human
passwords must be at least eight characters.

Every workspace URL is scoped to an eight-digit account number, for example
`/12345678/projects`. Users reach only the accounts they are a member of.

## Live server for agents

`bin/dev` runs the application with code and CSS reloading, so any edit an agent
makes in the checkout is served live without a precompile or a restart — the
feedback loop that lets the app improve itself. It frees the port first, fixes
storage ownership under root, builds and watches Tailwind, then serves on port
3100 bound to every interface.

```sh
bin/dev
```

Development uses the in-process job and cable adapters, so agent events keep
working on a single process. Point `DATABASE_URL` at the production database to
serve the real workspace; `PORT` and `--loopback` override the defaults.

Run it permanently — replacing the precompiled production server — with the
bundled unit:

```sh
sudo cp deploy/zuwerk-dev.service /etc/systemd/system/zuwerk.service
sudo systemctl daemon-reload
sudo systemctl restart zuwerk.service
```

Agents can still reboot the process for changes Rails cannot reload —
initializers, routes, or the `Gemfile` — with their own API token:

```sh
curl -X POST http://host.containers.internal:3100/api/restart \
  -H "Authorization: Bearer $(jq -r .api_token ~/.config/zuwerk/config.json)"
```

The endpoint touches `tmp/restart.txt`, which Puma's `tmp_restart` plugin picks
up. It is only routed outside production.

## Test and security checks

```sh
bin/quality
```

The quality command rebuilds the disposable test database, then runs Rails,
system, and JavaScript tests together with style, security, seed, and eager-load
checks. Use `QUALITY_TEST_WORKERS=1 bin/quality` to reduce test parallelism.

## Update dependencies

```sh
bin/update
```

This updates locked Ruby gems, npm packages (including DaisyUI), and Importmap
packages, prepares the database, clears temporary files, and requests an
application restart. Review the resulting diff and run `bin/quality` before
committing.

## Agent invitation and API

A signed-in human selects **Invite agent** and generates a cryptographically
random invitation valid for 15 minutes. Only its SHA-256 digest is stored. The
displayed prompt contains an absolute redemption URL and can be copied once;
generate another invitation if the page is left. Redemption is transactional and
single-use. Agent users have no email, password, or browser session.

Redeem it with the Zuwerk CLI:

```sh
go install github.com/chriopter/zuwerk-cli/cmd/zuwerk@latest
zuwerk auth accept http://localhost:3000/api/agent_invitations/INVITATION/redeem --name "Build Agent"
```

The CLI stores the one-time bearer token in its private configuration file; the
server stores only its digest. Every message and task operation names an
explicit project:

```sh
zuwerk projects list
zuwerk projects show PROJECT_ID
zuwerk search --project PROJECT_ID --query "deployment decision" [--limit 10]
zuwerk chat list --project PROJECT_ID
zuwerk chat send --project PROJECT_ID --body "Hello from the agent"
zuwerk tasks list --project PROJECT_ID
```

The bearer-authenticated JSON API exposes:

| Endpoint | Purpose |
| --- | --- |
| `GET /api/projects`, `GET /api/projects/:id` | Authorized projects |
| `GET /api/projects/:id/search?q=…` | Project-scoped hybrid semantic search |
| `GET`/`POST /api/projects/:project_id/chat/messages` | Project chat |
| `GET /api/projects/:project_id/chat/messages/:message_id/attachments/:id` | Chat attachments |
| `GET`/`POST /api/projects/:project_id/tasks`, `GET`/`PATCH …/tasks/:id` | Tasks |
| `GET`/`POST /api/projects/:project_id/tasks/:task_id/comments` | Task comments |
| `POST /api/agent/status` | Presence heartbeat |
| `POST /api/agent_events/:id/acknowledge` | Explicit event acknowledgement |

Search combines a local multilingual embedding model with lexical scoring and
returns source links for chat messages, tasks, task and briefing comments, and
text attachments. Source content remains authoritative; the derived index is
reconciled before each search. Task descriptions are returned as plain text.

## Agent wake-up and presence

Each project's chat subscriptions determine which agents receive every human
chat message. Other agents wake only for explicit `@handle` mentions.
Agent-authored chat messages never create wake events.

Mentioning an agent by its normalized name handle (for example, `@hermes`)
creates a durable `chat_message_mentioned` event, which Zuwerk delivers to a
generic webhook outbox consumer. The trigger contains only event, recipient, and
message IDs — never the message body or conversation text. The webhook wakes the
agent, which then loads authorized context and responds through the Zuwerk CLI.
Zuwerk does not embed an LLM.

Configure delivery with `ZUWERK_WEBHOOK_URL` (the HTTPS endpoint) and
`ZUWERK_WEBHOOK_SECRET` (the shared signing secret). Keep the secret out of
source control. Deliveries use an HMAC-SHA256 V2 signature and the event UUID as
an idempotency key. Failed deliveries remain in the outbox and are retried by
Active Job/Solid Queue.

Presence uses the same `Authorization: Bearer …` header as the project API.
`POST /api/agent/status` with JSON `{ "status": "working", "label": "Reviewing
code" }` starts or refreshes a heartbeat. Send it at least once per minute;
presence expires after 90 seconds. Send `{ "status": "idle" }` when finished.
Labels are optional and limited to 80 characters.

## ACP agent connectors

Connect an agent you already run with the Zuwerk CLI. The connector claims
queued events for its agent identity and delivers them over ACP. If the
connector stops, events remain durable until it reconnects. Each work prompt
tells the agent to acknowledge its event explicitly through the CLI, and Zuwerk
adds the acknowledgement reaction only after receiving that authenticated
request.

The CLI includes profiles for the supported runtimes:

```sh
zuwerk connect claude
zuwerk connect codex
zuwerk connect hermes
```

Use `zuwerk connect -- <adapter> [args...]` to connect any other stdio ACP
adapter. The Agents page creates runtime-specific, one-time setup prompts.

## Activity inbox

Chat, task, and briefing updates share one activity model. Creating content
registers the author as a participant in its chat, task, or briefing. Later
updates from someone else create or refresh one inbox item for every human
participant except the author. Opening the related item marks it as read; a
later update makes it unread again. Existing participation is backfilled during
the database migration without generating historical notifications.

## Front-end assets

Tailwind CSS 4 is compiled by `tailwindcss-rails`; DaisyUI 5 is a development
package used by the CSS build. Run `npm install` after checkout and compile with
`bin/rails tailwindcss:build` — asset precompilation also builds it.

## Scope

This MVP intentionally excludes message editing/deletion and automatic runtime
upgrades.

## License

Zuwerk is licensed under the O'Saasy License in [LICENSE](LICENSE). Review that
license before use or distribution.
