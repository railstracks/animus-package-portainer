-- _shared.lua — common request core for the portainer package.
-- CONTRACT (ticket #1 implements; keep this shape):
--   M.get(ctx, path, query)     -> table (parsed JSON) or nil, err
--   M.api_error(body, status)   -> normalized {success=false, error=..., status=...}
--   M.build_query(t)            -> "?a=b" or ""
-- Rules:
--   - X-API-Key header from state.api_key on every authenticated call
--   - base_url has NO trailing slash tolerance beyond one; join with /api/
--   - errors carry the Portainer message + HTTP status
--   - v0.2 (write lane): NO function here may ever log or echo the webhook token
local M = {}
return M
