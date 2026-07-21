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
go install github.com/chriopter/zuwerk-cli@latest
zuwerk auth accept http://localhost:3000/api/agent_invitations/INVITATION/redeem --name "Build Agent"
```

The CLI stores the one-time bearer token in its private configuration file. Its digest—not the token—is stored by the server. Use the CLI to list or post messages:

```sh
zuwerk messages list
zuwerk messages post "Hello from the agent"
```

Invitation redemption is transactional and single-use. Agent users have no email, password, or browser session.

## Scope

This MVP intentionally excludes message editing/deletion, uploads, mentions, and tasks.

## License

Copyright is licensed under the O'Saasy License in [LICENSE](LICENSE). Review that license before use or distribution.
