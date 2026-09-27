# animus-package-portainer

Portainer API package for [Animus](https://github.com/railstracks/animus) — observability and redeploy control of your own Docker infrastructure through the Portainer CE/BE API.

**Status: v0.2.0 — shipped, live-verified** (field-tested against a real self-hosted Portainer CE 2.41.0, Sept 26 2026; all five reads green + negatives: 401 mapping, arg validation, egress denial).

## Scope staging

| Phase | Scope | Status |
|---|---|---|
| v0.1.0 | Authenticated reads: status, environments, stacks, stack file | **Shipped** |
| v0.2.0 | Stack lifecycle writes: start/stop, git redeploy, webhooks (list + delete, tokens masked), update definition (diff echo) | **Shipped + field-verified** (workstation Portainer CE 2.41.0, Sept 27): state gate + confirm-name + audit + diff echo. Kernel gate = animus#126 |
| v0.3.0 | Observability reads: system info, endpoint summary/inspect, snapshot, docker-proxy (containers/inspect/logs/stats, images, volumes, networks), dashboard, tags, custom templates, settings read | **Devex lane — unblocked** (pure reads, no gate dependency) — issue #6 |
| v0.4.0 | Control writes via proxy: container restart/start/stop, image pull/delete, container delete, tags CRUD | **Do-not-start** until v0.2 gate pattern proven in production — issue #8 |

Full map incl. the 199 fenced operations and their reasons: `docs/ENDPOINTS.md`.

## Why this package

- We run Portainer ourselves (workstation + midas-srv) — the package's first consumer is our own ops
- Write actions are the ideal stress test for the owner-approval gate on risky package actions (a redeploy can restart production services)
- Portainer's API-key auth + REST surface is exactly the pixellab shape, but write-side

## Research

- [docs/ENDPOINTS.md](docs/ENDPOINTS.md) — full API surface research (auth options, read/write endpoints, security model)
- Upstream docs: https://docs.portainer.io (API section); local instance swagger at `/api/docs`

## Development

Same layout as [animus-package-pixellab](https://github.com/railstracks/animus-package-pixellab).

⚠️ **Testing fence (hard):** all automated tests run against a local fixture server. NEVER point tests at a live Portainer instance — a mistaken redeploy test against production is exactly the failure this package exists to prevent.

## License

MIT
