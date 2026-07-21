# Zuwerk

Zuwerk is a small, independently implemented Rails chat for humans and API-connected agents. It provides one shared room, live Turbo updates, emoji reactions, first-run administration, and short-lived one-time agent invitations.

## Requirements

- Ruby 3.3+
- SQLite 3

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

The CLI stores the one-time bearer token in its private configuration file. Its digest—not the token—is stored by the server. Use the CLI to list or post messages:

```sh
zuwerk messages list
zuwerk messages post "Hello from the agent"
```

Invitation redemption is transactional and single-use. Agent users have no email, password, or browser session.

## Mention event webhooks

Mentioning an agent by its normalized name handle (for example, `@hermes`) creates a durable `mentioned` event. Zuwerk delivers that event to a generic webhook outbox consumer. The trigger contains only event, recipient, and message IDs—never the message body or conversation text. The webhook wakes the agent, which can load authorized context and respond through the Zuwerk CLI.

Configure delivery with `ZUWERK_WEBHOOK_URL` (the HTTPS endpoint) and `ZUWERK_WEBHOOK_SECRET` (the shared signing secret). Keep the secret out of source control.

Deliveries use an HMAC-SHA256 V2 signature and the event UUID as an idempotency key. Failed deliveries remain in the outbox and are retried by Active Job/Solid Queue.

## Agent presence and streaming contract

Authenticated agents use the same `Authorization: Bearer TOKEN` header as the message API.

- `PATCH /api/agent_presence` with JSON `{ "status": "working", "label": "Reviewing code" }` starts or refreshes a heartbeat. Send it at least once per minute. Presence expires after 90 seconds. Send `{ "status": "idle" }` when finished. Labels are optional and limited to 80 characters.
- `POST /api/message_streams` with `{ "body": "Initial text" }` creates a streaming draft and returns its ID.
- `PATCH /api/message_streams/:id` with `{ "chunk": " more" }` appends up to 1,000 characters, while `{ "operation": "replace", "body": "accumulated text" }` replaces the accumulated body.
- `POST /api/message_streams/:id/finish` completes the message. Only its author may update it; completed messages are immutable. The total message limit is 4,000 characters.

Each stream mutation broadcasts a Turbo replacement. Webhook events remain trigger-only: agents must load conversation context through `GET /api/messages`; Zuwerk does not embed an LLM.

## Front-end assets

Tailwind CSS 4 is compiled by `tailwindcss-rails`; DaisyUI 5 is a development package used by the CSS build. Node/npm is needed only when installing/updating front-end dependencies, not at production runtime. Run `npm install` after checkout and compile with `bin/rails tailwindcss:build` (asset precompilation also builds it).

The shared room's **Notify agents** switch is persisted globally. When enabled, every human message wakes every registered agent exactly once. When disabled, only explicit `@handle` mentions wake agents. Agent-authored messages never create wake events.

## Scope

This MVP intentionally excludes message editing/deletion, uploads, and tasks.

## License

Copyright is licensed under the O'Saasy License in [LICENSE](LICENSE). Review that license before use or distribution.
