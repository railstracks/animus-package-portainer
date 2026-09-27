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
-- Content-Type is required on any request WITH a body: Portainer's JSON
-- payload parser only engages for application/json (live catch #5 — PUTs
-- parsed as empty without it, 400 "Invalid request payload").
function shared.headers(pkg)
  local h = { ["Accept"] = "application/json", ["Content-Type"] = "application/json" }
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
  -- 2xx-wide success: Portainer returns 202 for webhook delete/execute
  -- and 202/204 for other accepted-writes (found field-testing v0.2).
  if r.status >= 200 and r.status < 300 then
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

-- ==== write-lane core (v0.2, docs/WRITE-LANE-DESIGN.md) ====

-- Writes are a state gate, default-off. Guards accidental agent actions;
-- NOT a security boundary against a rogue caller (that is kernel Tier 2,
-- animus#126). Refusal is loud and names the key.
function shared.require_writes(pkg)
  local v = pkg.get_state("writes_enabled")
  if v == "true" then return true end
  return nil, "write lane disabled — set package state writes_enabled=true to arm " ..
    "(commands remain confirm-gated and audit-logged; see docs/WRITE-LANE-DESIGN.md)"
end

-- Confirm is a NAME MATCH, not a boolean: the caller must restate the
-- target's name exactly. A boolean is one hallucination away.
function shared.confirm_name(args, actual)
  local c = args and args.confirm
  if c == nil or c == "" then
    return nil, "confirm required: pass confirm=\"" .. tostring(actual) ..
      "\" (exact name of the target)"
  end
  if tostring(c) ~= tostring(actual) then
    return nil, "confirm mismatch: expected \"" .. tostring(actual) ..
      "\", got \"" .. tostring(c) .. "\" — refusing before any write"
  end
  return true
end

-- Audit every write: method, path, body length, body head. Bodies in this
-- lane contain compose content (no credentials); webhook tokens never
-- reach here (masking happens before any logging surface).
function shared.audit_write(ctx, method, path, body)
  local b = body ~= nil and tostring(body) or ""
  local head = b:sub(1, 2048)
  local trunc = #b > 2048 and ("… [" .. tostring(#b) .. " bytes total]") or ""
  ctx.log("AUDIT write " .. tostring(method) .. " " .. tostring(path) ..
          " (" .. tostring(#b) .. " bytes) " .. head .. trunc)
end

function shared.put(ctx, pkg, path, query, body, timeout_s)
  local base, err = shared.require_config(pkg)
  if base == nil then return { ok = false, error = err } end
  local r = ctx.http.put(shared.normalize_base(base) .. "/api" .. path ..
                         shared.build_query(query or {}),
                         { headers = shared.headers(pkg),
                           body = json.encode(body or {}),
                           timeout_s = timeout_s or 30 })
  return shared.interpret(r)
end

function shared.post(ctx, pkg, path, query, body, timeout_s)
  local base, err = shared.require_config(pkg)
  if base == nil then return { ok = false, error = err } end
  local r = ctx.http.post(shared.normalize_base(base) .. "/api" .. path ..
                          shared.build_query(query or {}),
                          { headers = shared.headers(pkg),
                            body = json.encode(body or {}),
                            timeout_s = timeout_s or 30 })
  return shared.interpret(r)
end

function shared.delete(ctx, pkg, path, timeout_s)
  local base, err = shared.require_config(pkg)
  if base == nil then return { ok = false, error = err } end
  local r = ctx.http.delete(shared.normalize_base(base) .. "/api" .. path,
                            { headers = shared.headers(pkg),
                              timeout_s = timeout_s or 30 })
  return shared.interpret(r)
end

-- Line diff summary for stack update presentation: counts + the changed
-- regions (unified-ish, capped). O(n*m) LCS is fine at compose-file scale.
function shared.diff_summary(old_s, new_s, cap)
  cap = cap or 40
  local function lines(s)
    local t = {}
    for l in tostring(s or ""):gmatch("([^\n]*)\n?") do t[#t+1] = l end
    if #t > 1 and t[#t] == "" then t[#t] = nil end
    return t
  end
  local a, b = lines(old_s), lines(new_s)
  local n, m = #a, #b
  -- LCS length table
  -- +1 row/col of zeros: the walk reads lcs[i+1][j] / lcs[i][j+1] at the
  -- edges (i==n or j==m); extra zeros are semantically "empty suffix = 0".
  local lcs = {}
  for i = 0, n + 1 do lcs[i] = {} for j = 0, m + 1 do lcs[i][j] = 0 end end
  for i = n-1, 0, -1 do
    for j = m-1, 0, -1 do
      if a[i+1] == b[j+1] then lcs[i][j] = lcs[i+1][j+1] + 1
      else lcs[i][j] = math.max(lcs[i+1][j], lcs[i][j+1]) end
    end
  end
  -- Walk: emit removed/added hunks
  local hunks, added, removed = {}, 0, 0
  local i, j = 1, 1
  local function flush(rem, add)
    if #rem == 0 and #add == 0 then return end
    hunks[#hunks+1] = { removed = rem, added = add }
  end
  local rem, add = {}, {}
  while i <= n or j <= m do
    if i <= n and j <= m and a[i] == b[j] then
      flush(rem, add); rem, add = {}, {}; i = i + 1; j = j + 1
    elseif j <= m and (i > n or lcs[i][j+1] >= lcs[i+1][j]) then
      add[#add+1] = b[j]; j = j + 1
    else
      rem[#rem+1] = a[i]; i = i + 1
    end
  end
  flush(rem, add)
  for _, h in ipairs(hunks) do
    removed = removed + #h.removed
    added = added + #h.added
  end
  local shown, took = {}, 0
  for _, h in ipairs(hunks) do
    if took >= cap then break end
    for _, l in ipairs(h.removed) do
      if took < cap then shown[#shown+1] = "-" .. l; took = took + 1 end
    end
    for _, l in ipairs(h.added) do
      if took < cap then shown[#shown+1] = "+" .. l; took = took + 1 end
    end
  end
  return {
    added_lines = added, removed_lines = removed,
    hunks = #hunks, truncated = (#hunks > 0 and took >= cap) or (added + removed > took),
    sample = table.concat(shown, "\n")
  }
end

-- Mask webhook tokens in any list/output surface (standing rule: tokens
-- are never logged, echoed, or error-included).
function shared.mask_webhooks(list)
  if type(list) ~= "table" then return list end
  local out = {}
  for idx, w in ipairs(list) do
    local c = {}
    for k, v in pairs(w) do
      if k == "Token" and type(v) == "string" then
        c[k] = #v > 4 and (v:sub(1,4) .. "…") or "…"
      else
        c[k] = v
      end
    end
    out[idx] = c
  end
  return out
end

return shared
