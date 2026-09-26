-- portainer / shared helpers (inlined at build time — the sandbox has no require)
--
-- Portainer CE/BE API: <base_url>/api (auth: X-API-Key header from state).
-- v0.1.0 is read-only scope. v0.2 write-lane rule (non-negotiable): nothing
-- here may ever log, echo, or error-include a webhook token.

local shared = {}

-- ---------------------------------------------------------------------------
-- State / config
-- ---------------------------------------------------------------------------

-- base_url is operator-supplied (self-hosted software, no public default).
-- Returns nil, err when unset. "***" = redacted placeholder from admin UI.
function shared.require_config(pkg)
  local base = pkg.get_state("base_url")
  if base == nil or base == "" or base == "***" then
    return nil, "base_url is not set (your Portainer instance root, e.g. https://portainer.example.com)"
  end
  return base
end

-- Strip trailing slashes and any trailing /api segment (scripts add /api).
function shared.normalize_base(u)
  u = string.gsub(tostring(u), "/+$", "")
  u = string.gsub(u, "/api$", "")
  return u
end

-- Auth header only when a key is configured (status works without one).
function shared.headers(pkg)
  local h = { ["Accept"] = "application/json" }
  local k = pkg.get_state("api_key")
  if k ~= nil and k ~= "" and k ~= "***" then
    h["X-API-Key"] = tostring(k)
  end
  return h
end

-- ---------------------------------------------------------------------------
-- Argument coercion
-- ---------------------------------------------------------------------------

function shared.int_arg(a, k)
  local v = a[k]
  if v == nil or v == "" then return nil end
  local n = tonumber(v)
  if n == nil then return nil, k .. " must be a number, got: " .. tostring(v) end
  if math.floor(n) ~= n then return nil, k .. " must be an integer" end
  return math.floor(n)
end

-- ---------------------------------------------------------------------------
-- Query building (values percent-encoded; the filters param carries JSON)
-- ---------------------------------------------------------------------------

local function hex(c) return string.format("%%%02X", string.byte(c)) end

function shared.url_encode(s)
  return (tostring(s):gsub("[^%w%.%-%_%~]", hex))
end

-- t: flat table of query params (values scalar). Returns "" or "?a=b&c=d".
-- nil/empty values are skipped.
function shared.build_query(t)
  local parts = {}
  for _, k in ipairs(t.__order or {}) do
    local v = t[k]
    if v ~= nil and v ~= "" then
      parts[#parts + 1] = shared.url_encode(k) .. "=" .. shared.url_encode(v)
    end
  end
  if #parts == 0 then return "" end
  return "?" .. table.concat(parts, "&")
end

-- ---------------------------------------------------------------------------
-- HTTP + error mapping
-- ---------------------------------------------------------------------------

-- GET <base>/api<path>. Returns {ok=true, json=..., body=...} or
-- {ok=false, error=..., http_status=...} with Portainer message surfaced.
function shared.get(ctx, pkg, path, query)
  local base, err = shared.require_config(pkg)
  if base == nil then return { ok = false, error = err } end
  local r = ctx.http.get(shared.normalize_base(base) .. "/api" .. path ..
                         shared.build_query(query or {}),
                         { headers = shared.headers(pkg), timeout_s = 10 })
  return shared.interpret(r)
end

function shared.interpret(r)
  if r == nil then return { ok = false, error = "no response from transport" } end
  if r.error ~= nil and r.error ~= "" then
    return { ok = false, error = "transport error: " .. tostring(r.error),
             http_status = r.status }
  end
  if r.status == 200 then
    return { ok = true, json = r.json, body = r.body }
  end
  local why
  if r.status == 401 then
    why = "unauthorized — check api_key (Portainer UI: user → API keys)"
  elseif r.status == 403 then
    why = "forbidden — this key's user lacks access to the resource"
  elseif r.status == 404 then
    why = "not found"
  elseif r.status >= 500 then
    why = "Portainer server error"
  else
    why = "HTTP " .. tostring(r.status)
  end
  local detail = ""
  if r.json ~= nil and type(r.json) == "table" and r.json.message ~= nil then
    detail = " — " .. tostring(r.json.message)
  elseif r.body ~= nil and r.body ~= "" then
    detail = " — " .. tostring(r.body):sub(1, 300)
  end
  return { ok = false, error = why .. detail, http_status = r.status }
end

return shared
