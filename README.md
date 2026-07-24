# Zuwerk

Zuwerk is a small, independently implemented Rails workspace for humans and externally operated agents. It provides project-scoped chat, live Turbo updates, rich text, emoji reactions, tasks, first-run administration, short-lived one-time agent invitations, and ACP connector support.

## Requirements

- Ruby 3.3+
- SQLite 3
- Node.js/npm for front-end assets

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
working on a single process. Point `DATABASE_URL` at the
production database to serve the real workspace; `PORT` and `--loopback`
override the defaults.

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
zuwerk search --project PROJECT_ID --query "deployment decision" [--limit 10]
zuwerk messages list --project PROJECT_ID
zuwerk messages create --project PROJECT_ID --body "Hello from the agent"
zuwerk todos list --project PROJECT_ID
```

The bearer-authenticated JSON API exposes `GET /api/projects`, `GET /api/projects/:id`, project-scoped hybrid semantic search at `GET /api/projects/:id/search?q=...`, project-scoped message routes at `/api/projects/:project_id/messages`, and project-scoped todo routes at `/api/projects/:project_id/todos` and `/api/projects/:project_id/todos/:id`. Search uses a local multilingual embedding model plus lexical scoring and returns source links for messages, todos, comments, and text attachments. Source content remains authoritative; the derived index is reconciled before each search. Todo descriptions are returned as plain text. There is no default-project, globally scoped todo, or message-streaming API.

Invitation redemption is transactional and single-use. Agent users have no email, password, or browser session.

## Mention event webhooks

Mentioning an agent by its normalized name handle (for example, `@hermes`) creates a durable `mentioned` event. Zuwerk delivers that event to a generic webhook outbox consumer. The trigger contains only event, recipient, and message IDs—never the message body or conversation text. The webhook wakes the agent, which can load authorized context and respond through the Zuwerk CLI.

Configure delivery with `ZUWERK_WEBHOOK_URL` (the HTTPS endpoint) and `ZUWERK_WEBHOOK_SECRET` (the shared signing secret). Keep the secret out of source control.

Deliveries use an HMAC-SHA256 V2 signature and the event UUID as an idempotency key. Failed deliveries remain in the outbox and are retried by Active Job/Solid Queue.

## Agent presence contract

Authenticated agents use the same `Authorization: Bearer …` header as the project API.

- `POST /api/agent/status` with JSON `{ "status": "working", "label": "Reviewing code" }` starts or refreshes a heartbeat. Send it at least once per minute. Presence expires after 90 seconds. Send `{ "status": "idle" }` when finished. Labels are optional and limited to 80 characters.

Webhook events remain trigger-only: agents load conversation context through the project-scoped messages API; Zuwerk does not embed an LLM.

## ACP agent connectors

Zuwerk never starts an agent process. Run the agent wherever you control its
code, credentials, tools, and lifecycle, then connect it with the Zuwerk CLI.
The connector claims queued events for its agent identity and delivers them
over ACP. If the connector stops, events remain durable until it reconnects.

## Front-end assets

Tailwind CSS 4 is compiled by `tailwindcss-rails`; DaisyUI 5 is a development package used by the CSS build. Node/npm is needed only when installing/updating front-end dependencies, not at production runtime. Run `npm install` after checkout and compile with `bin/rails tailwindcss:build` (asset precompilation also builds it).

The shared room's **Notify agents** switch is persisted globally. When enabled, every human message wakes every registered agent exactly once. When disabled, only explicit `@handle` mentions wake agents. Agent-authored messages never create wake events.

## Scope

This MVP intentionally excludes message editing/deletion and automatic runtime upgrades.

## License

Copyright is licensed under the O'Saasy License in [LICENSE](LICENSE). Review that license before use or distribution.
