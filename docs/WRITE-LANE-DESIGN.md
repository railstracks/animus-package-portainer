# Write-Lane Design (v0.2) — #5 review document

**Status: design complete, Tier 1 proceeding under announce-veto.** Reviewer of record: Kestrel;
co-gate: Melvin (veto window on this document).

## What exists vs. what's asked

The kernel ships one gate today (#106, merged pre-0.4): **install-level, content-bound approval**
— `approval_status` on the package row, `content_hash` over the security-relevant surface; any
content change returns the package to pending. That gate covers *malicious/changed code*.

#5 asks about a different axis: **per-action approval** — stopping the agent from *right-now*
doing something risky with *already-approved* code. Nothing in the kernel does this. The design
space below is scoped by one hard architectural fact:

> Payload-binding cannot happen at dispatch time. The Lua script composes the request (URL,
> method, body) at runtime — the kernel sees it only when the script calls the HTTP layer
> (`DoHttp` → `ExecuteScoped`). Therefore any real payload-bound gate must live **at the egress
> layer**, per actual request, not on the command declaration.

## Threat model (be honest about which tier answers which threat)

| Threat | Tier 1 (package) | Tier 2 (kernel) |
|---|---|---|
| (a) Accidental agent action (wrong stack, fat-fingered confirm) | **mitigated** — disabled-by-default + confirm arg + diff echo | also mitigated |
| (b) Agent gone rogue / prompt-injected | **NOT mitigated** (agent can pass `confirm=true` itself) — docs must say so | **mitigated** — approval originates out-of-band |
| (c) Malicious package code | covered by #106 (content-bound) + egress scope + no-DELETE fence | same |

v0.2.0 blast radius with fences in place: **availability only** (start/stop/redeploy/update on
non-delete actions; volumes untouched; no prune). Recoverable by construction.

## Tier 1 — package-level, ships in v0.2.0 (no kernel dependency)

1. **Writes are a state gate, default-off.** New state field `writes_enabled` (boolean, default
   `false`). Every write command's first line refuses loudly if unset — naming the state key and
   the risk class, same refusal style as the v0.1 auth gate.
2. **`confirm` argument on every write command.** Type string, must equal the target's name
   (`confirm="animus_test_node"`), not a boolean — a boolean `true` is one hallucination away;
   a name-match forces the caller to restate *what* it is about to touch.
3. **Diff presentation for `stack update`.** The command fetches the current file first
   (`GET /stacks/{id}/file`), computes a line diff in-Lua, and includes `{current_lines,
   new_lines, changed}` in the result alongside the write confirmation. The operator sees what
   changed, not just that something did. (The write still happens in the same call — this is UX
   honesty, not a gate; Tier 2 makes the pause real.)
4. **Audit everything.** Every write emits a kernel log line (the sandbox `log` surface) with
   method, path, `?endpointId=`, and body SHA256 — payloads with secrets excepted (none in v0.2's
   scope; webhook tokens never logged per the standing rule).
5. **Fences carried forward, unchanged:** no DELETE anywhere, no prune (see Q1), no webhook
   invoke in v0.2 (see Q2), fixture-only tests (live writes = production events; the field test
   is the exception and targets dormant/scratch stacks only).

## Tier 2 — kernel per-invocation gate (files as animus issue; not v0.2-blocking)

- Manifest gains `writes_gated: true` (package-level; granularity rationale above).
- `DoHttp` intercepts write-method calls (POST/PUT/DELETE) on gated packages: first attempt
  returns a structured `approval_required` result carrying a digest of (method, path, body);
  the execute surfaces it; the digest queues with TTL.
- **Approval surface is out-of-band by construction:** admin route
  `POST /api/v1/api/packages/{id}/approvals/{digest}` and/or a chat-flow where the *human's*
  message routes through the kernel (never the agent's own channel). Approved digests pass on
  retry; identical payload only (content-bound, same philosophy as #106).
- Retry semantics: script re-executes and re-issues the same request → digest match → passes.
  A different payload = different digest = new approval. This *is* payload-binding.
- Open questions for Tier 2 (filed with the kernel issue, not blocking): TTL length, approval
  fan-out (one digest vs session), whether reads on write-gated packages also want digest
  pinning (no — only write methods).

## The ticket's four questions, answered

**Q1 — gate declaration & payload binding.** See above: package-level declaration, egress-layer
digest binding, per-invocation. **Prune risk split: dissolved by fence** — `redeploy` ships
with `prune=false` fixed (no parameter exposed). `prune=true` deletes orphans; deletion-class
actions stay out of v0.2 entirely. No split to design.

**Q2 — webhook invoke.** Deferred to Tier 2's arrival (it's the ideal first test case: the token
is a credential-shaped *argument*, must never be logged, and the invoke path bypasses API-key
audit richness). v0.2 ships webhook **list (tokens masked)** and **delete**; create was dropped
in the field test (live catch #4: only ServiceWebhook type exists on
`POST /webhooks`; stack webhooks are auto-update config — redesign in v0.2.x) — an operator wanting keyless redeploy can create the webhook and curl it from their
own surface.

**Q3 — update definition.** In, with the diff-presentation design (Tier 1 §3). Field data: this
is the mechanism that made tonight's EXTRA_ARGS fix durable across Portainer UI redeploys — an
operator-agent that can edit the stored stack definition *through the API* is exactly the
self-hosted-companion value prop. Risk is the highest in the lane (full compose content), which
the diff echo + name-confirm + state gate address proportionally at this blast radius.

**Q4 — confirmation shape.** `confirm="<target-name>"` string-match, not boolean (Tier 1 §2),
plus the state gate. When Tier 2 lands, `confirm` remains as the accidental-action guard inside
the approval flow (belt-and-braces), not the gate itself.

## Field test plan (v0.2.0 close-out)

Targets chosen for zero blast radius: `animus_test_node` + `animus_working_copy` (both status 2
= inactive, no consumers) for start/stop/redeploy; a scratch stack created via **direct** Portainer
API (not the package) for `stack update` + teardown by the same direct path. Cycle:
install → writes-refused-without-state (negative) → enable writes → confirm-negative (wrong name)
→ start/stop/redeploy on dormant stack → update on scratch stack with diff echo → verify stored
definition changed → delete package (game master stays clean; Melvin's standing cleanup rule).
The API key: re-vaulted for the cycle only.

## Sequencing

1. This document → #5 (open for Melvin's veto window; proceeding on Tier 1 meanwhile)
2. Package v0.2.0 Tier 1 implementation + fixture tests
3. Field test per above → tag → registry
4. Kernel Tier 2 issue filed (animus) — implementation as its own arc
5. v0.2.1 flips to kernel gating when Tier 2 lands (state gate stays as defense-in-depth)
