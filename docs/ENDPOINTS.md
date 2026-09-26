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
| stack file | `GET /stacks/{id}/file` | the compose file content — **response key is `StackFileContent` (PascalCase) on CE 2.41.0 live**, unlike most other endpoints |

PUT /stacks/{id} (update definition) **requires `?endpointId=` query param** on CE 2.41.0 live (400 otherwise); PUT response Status=3 means "deploying" (1=active, 2=inactive).

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

---

# Full API map (CE 2.41.0) — v0.2+ staging

Source: the versioned OpenAPI spec at `api-docs.portainer.io/versions/ce/2.41.0/openapi.yaml`
(32 group files, **241 enumerated operations**), plus the docker-proxy passthrough below.
Mechanically enumerated from the artifact — this is the complete surface, not a recall list.

## Lane: v0.2 — Stack lifecycle (writes, approval-gated; blocked on #5 design review)

| Op | Route | Notes |
|---|---|---|
| start | `POST /stacks/{id}/start` | reversible |
| stop | `POST /stacks/{id}/stop` | availability impact |
| redeploy git | `PUT /stacks/{id}/git/redeploy` | source-of-truth driven |
| redeploy webhook | `POST /stacks/webhooks/{webhookID}` | token auth, no API key |
| webhooks list | `GET /webhooks` | ⚠️ returns `Token` fields — must be masked in command output |
| webhook create/delete | `POST /webhooks` / `DELETE /webhooks/{id}` | enables keyless redeploy |
| update definition | `PUT /stacks/{id}` | verified live: requires `?endpointId=` query param; response `Status:3` = deploying |

Deferred within the lane: `PUT /stacks/{id}/git` (git config update), `POST /stacks/{id}/migrate`,
all 9 `POST /stacks/create/*` variants (arbitrary-infrastructure creation — needs its own review),
`PUT /stacks/{id}/associate`. Never: `DELETE /stacks*` (standing fence from #5).

## Lane: v0.3 — Observability (pure reads, no gates needed)

Docker API is reached through Portainer's **endpoint proxy** (wildcard-routed, NOT part of the 241
enumerated ops): `/endpoints/{id}/docker/<docker-api-path>` — same host, same auth. Verified
shape: raw Docker JSON responses.

| Command | Route | Notes |
|---|---|---|
| system info | `GET /system/info` | |
| system version | `GET /system/version` | |
| endpoint get | `GET /endpoints/{id}` | full inspect incl. snapshots |
| endpoints summary | `GET /endpoints/summary` | richer than list |
| snapshot refresh | `POST /endpoints/{id}/snapshot` | "write" but benign refresh — spec: ungated, document |
| docker dashboard | `GET /docker/{environmentId}/dashboard` | single-call aggregate (running/stopped counts, stacks) |
| containers list | `GET /endpoints/{id}/docker/containers/json` | pass `all=1` + `filters` JSON through |
| container inspect | `GET /endpoints/{id}/docker/containers/{cid}/json` | |
| container logs | `GET /endpoints/{id}/docker/containers/{cid}/logs?tail=N&stdout=1&stderr=0&follow=0` | ⚠️ single-stream = UNFRAMED text (`r.body`); both streams requested = docker multiplexed framing — spec pins stdout-only |
| container stats | `GET /endpoints/{id}/docker/containers/{cid}/stats?stream=false` | one-shot JSON |
| images list | `GET /endpoints/{id}/docker/images/json` | |
| volumes list | `GET /endpoints/{id}/docker/volumes` | |
| networks list | `GET /endpoints/{id}/docker/networks` | |
| tags list | `GET /tags` | |
| custom templates | `GET /custom_templates` + `GET /custom_templates/{id}/file` | read-only prep for future create UX |
| settings read | `GET /settings` | read-only; PUT stays fenced |

## Lane: v0.4 — Control (gated writes via the proxy; do-not-start until v0.2 gate pattern proven)

| Op | Route | Risk class |
|---|---|---|
| container restart/start/stop | `POST /endpoints/{id}/docker/containers/{cid}/restart|start|stop` | reversible, per-container |
| image pull | `POST /endpoints/{id}/docker/images/create?fromImage=` | disk consumption, low |
| image delete | `DELETE /endpoints/{id}/docker/images/{name}` | approval gate |
| container delete | `DELETE /endpoints/{id}/docker/containers/{cid}` | approval gate + prune=false semantics |
| tags create/delete | `POST /tags` / `DELETE /tags/{id}` | organizational, gate-lite |

## FENCED — out of scope for this package (documented do-not-touch)

| Group (ops) | Why fenced |
|---|---|
| `users` (13), `teams` (5), `team_memberships` (5), `roles` (1), `resource_controls` (3) | RBAC surface = privilege escalation vector |
| `auth` (3), `ldap` (1) | session/credential management — package uses API keys, nothing to gain |
| `registries` (7) | registry credentials vault surface |
| `ssl` (2), `upload/tls` (1) | TLS private-key upload/management |
| `backup` (2) | instance-level destructive |
| `system/upgrade` (1 of system's 5) | kernel-level destructive |
| `websocket` (4) | interactive exec/attach — ultimate ungated action; kernel has no ws client anyway (#122 adjacent) |
| `kubernetes` (66) + `helm` (11) | k8s is a separate surface; this package's identity is Docker/Swarm self-hosted. If ever needed: separate package (`portainer-k8s`) per shape-diversity principle |
| `edge_stacks`/`edge_jobs`/`edge_groups`/`edge` (25 total) | Edge-compute fleet topology ≠ our deployment shape |
| `intel`/open_amt (6) | hardware management, niche |
| `motd` (1), `gitops` (3), `templates` (2), `settings` PUT | trivial value or global-mutation risk |

**Enumeration coverage check:** 241 spec ops = v0.2 (7 ops) + v0.3 (17) + v0.4 (6) + deferred stacks
(12) + fenced (199). Nothing unaccounted. Docker-proxy passthrough routes beyond the listed v0.3/v0.4
set (e.g. build, exec create, swarm join) inherit the v0.4 fence by default.
