# animus-package-portainer

Portainer API package for [Animus](https://github.com/railstracks/animus) — observability and redeploy control of your own Docker infrastructure through the Portainer CE/BE API.

**Status: scaffold** — scope staged, docs researched, tickets filed. Not yet published to the Animus Registry.

## Scope staging

| Phase | Scope | Status |
|---|---|---|
| v0.1.0 | Authenticated reads: status, environments, stacks, stack file | **Buildable now** |
| v0.2.0 | Write lane: stack redeploy (git/redeploy + webhook token), start/stop | **Design review first** — approval-gate class actions against live infra |

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
