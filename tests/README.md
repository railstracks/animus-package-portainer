# tests

Fixture-based tests, following the [animus-package-pixellab](https://github.com/railstracks/animus-package-pixellab) pattern.

⚠️ **HARD FENCE: never point any test at a live Portainer instance.** All tests run against `fixture_server.py` (a local HTTP server standing in for `/api`). A write-action test against production is a production event.

- `fixture_server.py` — canned responses: status, endpoints, stacks list/get/file; auth check on X-API-Key
- `test_commands.lua` — every command: success paths, param validation, auth-missing rejection, error normalization

Live verification (reads only) happens once, deliberately, by the maintainer.
