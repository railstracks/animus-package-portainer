# Portainer API — endpoint research

Researched 2026-09-26. Sources: upstream docs (docs.portainer.io), CE **2.41.0** handler source (verified route-by-route: `api/http/handler/stacks/*.go`), and a live CE 2.41.0 instance.

Paths below are relative to `<base_url>/api` — e.g. base `https://portainer.example.com` → `https://portainer.example.com/api/stacks`.

## Authentication

Two options; the package uses **API keys**.

### API key (recommended)
- Header: `X-API-Key: <key>`
- Keys are created per-user (UI: user → API keys, or `POST /users/{userId}/api-tokens`); role follows the user
- Available since CE 2.15; no expiry by default (revocable)
- One secret in package state: `api_key`. Scope it to a dedicated read-mostly user where possible

### JWT login (legacy — NOT used)
`POST /auth {username, password}` → `Authorization: Bearer <jwt>`. Password-shaped secrets in package state are worse than revocable API keys; skip.

## Reads — v0.1.0 package scope

| Command | Endpoint | Notes |
|---|---|---|
| status | `GET /status` | version, instance id. **Works unauthenticated** — good pre-flight |
| endpoints list | `GET /endpoints` | environments (Docker/Swarm/K8s), with pagination query params |
| stacks list | `GET /stacks` | supports `filters` JSON query (e.g. by endpointId, SwarmID, status) |
| stack get | `GET /stacks/{id}` | full stack object: status, creationDate, updateDate, git metadata, webhook field |
| stack file | `GET /stacks/{id}/file` | the compose file content (stackFileContent) |

Stack object notes: `Status` (1=active, 2=inactive), `Type` (1=swarm, 2=compose), `EndpointID`, `Webhook` (token string — present iff webhook enabled for the stack), `GitConfig` when git-backed.

## Write lane — v0.2.0 scope (design review first)

| Action | Route | Notes |
|---|---|---|
| redeploy (git) | `PUT /stacks/{id}/git/redeploy` | body: `{pullImage, prune, ...}`; redeploys a git-backed stack from its repo |
| webhook redeploy | `POST /stacks/webhooks/{webhookID}` | **unauthenticated**; token is the credential; triggers git redeploy if stack is git-backed |
| start | `POST /stacks/{id}/start` | |
| stop | `POST /stacks/{id}/stop` | |
| update definition | `PUT /stacks/{id}` | full stack-definition update (manifest + compose content) — treat as most-dangerous |

Verified against 2.41.0 source: `stack_update_git_redeploy.go` (`@router /stacks/{id}/git/redeploy [put]`), `webhook_invoke.go` (`@router /stacks/webhooks/{webhookID} [post]`), `stack_start.go`, `stack_stop.go`, `stack_update.go`.

### Security model for the write lane

- **The webhook route is unauthenticated by design** — a leaked webhook token = anyone can trigger redeploys. Package must never log or return the token; passing it is one-way.
- Write actions are exactly the owner-approval-gate class (0.4.1 #25/#106): package actions that mutate infrastructure should be declared risky so approval binds to payload content.
- **Hard fence for tests:** fixture server only. A live-instance test of any write action is a production event.

## Error shape

Portainer returns `{"message": "...", "details": "..."}` with appropriate HTTP status. Normalize to `{success=false, error=...}` carrying status + message.

## Package design notes

- `state_schema`: `api_key` (secret), `base_url` (default empty — must be set; never a public default, this is self-hosted software)
- `egress`: single domain = your Portainer host. Note: egress allowlist is per-package; a base_url pointing anywhere other than the declared host will be rejected — document that the operator must align them
- All responses JSON; no file outputs (compose file content returns as a string field)
- Version pin: developed against CE 2.41.0; routes verified in 2.41.0 source
