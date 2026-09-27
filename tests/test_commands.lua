-- test_commands.lua — integration tests for every command script (plain lua5.4).
-- Stubs: ctx.http.get captures requests and returns fixtures; json.encode is a
-- compact serializer (matches the pixellab harness pattern).
-- Amendment vs ticket #3 spec: in-process stubs instead of fixture_server.py —
-- follows the proven animus-package-pixellab house pattern; zero live-network
-- anything, zero process management. Run: lua tests/test_commands.lua

shared = dofile("scripts/_shared.lua")   -- global: command scripts reference it

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local function ser(t)
  if type(t) == "table" then
    if is_array(t) then
      local parts = {}
      for _, v in ipairs(t) do parts[#parts + 1] = ser(v) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = '"' .. tostring(k) .. '":' .. ser(t[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(t) == "string" then
    return '"' .. (t:gsub('["\\]', function(c) return "\\" .. c end)) .. '"'
  elseif type(t) == "boolean" then
    return tostring(t)
  else
    return string.format("%.17g", t)
  end
end

json = { encode = ser, decode_safe = function() return nil end }

local captured, fixture
local queue, logs = {}, {}

local function nextfix()
  return table.remove(queue, 1) or fixture
end

local function mkctx(args, state)
  state = state or { base_url = "https://p.example.com", api_key = "KEY1" }
  queue, logs = {}, {}
  return {
    now = 1758900000000,
    package = { get_state = function(k) return state[k] end },
    args = args or {},
    log = function(s) logs[#logs + 1] = s end,
    http = {
      get = function(url, opts)
        captured = { verb = "GET", url = url, headers = opts.headers, timeout = opts.timeout_s }
        return nextfix()
      end,
      put = function(url, opts)
        captured = { verb = "PUT", url = url, headers = opts.headers, body = opts.body, timeout = opts.timeout_s }
        return nextfix()
      end,
      post = function(url, opts)
        captured = { verb = "POST", url = url, headers = opts.headers, body = opts.body, timeout = opts.timeout_s }
        return nextfix()
      end,
      delete = function(url, opts)
        captured = { verb = "DELETE", url = url, headers = opts.headers, timeout = opts.timeout_s }
        return nextfix()
      end
    }
  }
end

dofile("scripts/_stack_write_shared.lua")  -- sets the global itself

-- write-lane test fixtures ---------------------------------------------------
local function fix_stack()
  return { status = 200, json = { Id = 11, Name = "animus_test_node", Status = 2,
                                  EndpointId = 3, Type = 2 } }
end
local function fix_stack_started()
  return { status = 200, json = { Id = 11, Name = "animus_test_node", Status = 1, EndpointId = 3 } }
end

local function load_cmd(name)
  local chunk = assert(loadfile("scripts/" .. name .. ".lua"))
  chunk()                      -- executes: defines the global run(ctx)
  return run
end

local failures = 0
local function check(label, cond, extra)
  if not cond then
    print("FAIL  " .. label .. (extra and (" — " .. tostring(extra)) or ""))
    failures = failures + 1
  else
    print("ok    " .. label)
  end
end

local status_cmd      = load_cmd("status")
local endpoints_cmd   = load_cmd("endpoints_list")
local stacks_cmd      = load_cmd("stacks_list")
local stack_get_cmd   = load_cmd("stack_get")
local stack_file_cmd  = load_cmd("stack_file")

-- ---- status ----------------------------------------------------------------
fixture = { status = 200, json = { Version = "2.41.0", InstanceID = "8f61bbe5" } }
local r = status_cmd(mkctx({}, { base_url = "https://p.example.com" }))
check("status success", r.success == true and r.data.version == "2.41.0")
check("status url", captured.url == "https://p.example.com/api/status", captured.url)
check("status sends no api key", captured.headers["X-API-Key"] == nil)

r = status_cmd(mkctx({}, {}))
check("status without base_url fails clean",
      r.success == false and r.error:find("base_url") ~= nil)

fixture = { status = 502, body = "bad gateway" }
r = status_cmd(mkctx({}, { base_url = "https://p.example.com" }))
check("status 5xx normalized",
      r.success == false and r.http_status == 502 and r.error:find("server error") ~= nil)

-- ---- endpoints list ----------------------------------------------------------
fixture = { status = 200, json = {
  { Id = 1, Name = "local", Type = 1, URL = "unix:///var/run/docker.sock" },
  { Id = 2, Name = "swarm", Type = 1, URL = "tcp://10.0.0.5:2377" }
} }
r = endpoints_cmd(mkctx())
check("endpoints success", r.success == true and #r.data == 2 and r.data[2].Name == "swarm")
check("endpoints url", captured.url == "https://p.example.com/api/endpoints")
check("endpoints auth header", captured.headers["X-API-Key"] == "KEY1")

fixture = { status = 401, json = { message = "Unauthorized" } }
r = endpoints_cmd(mkctx())
check("endpoints 401 normalized",
      r.success == false and r.error:find("api_key") ~= nil and r.error:find("Unauthorized") ~= nil)

fixture = { status = 200, json = { weird = true } }
r = endpoints_cmd(mkctx())
check("endpoints non-array rejected",
      r.success == false and r.error:find("array") ~= nil)

-- ---- stacks list ------------------------------------------------------------
fixture = { status = 200, json = {
  { Id = 1, Name = "animus_rpg", Status = 1, Type = 2, EndpointId = 1 },
  { Id = 2, Name = "kestral-lab", Status = 1, Type = 1, EndpointId = 1 },
  { Id = 3, Name = "retired", Status = 2, Type = 2, EndpointId = 2 }
} }
r = stacks_cmd(mkctx())
check("stacks no-filter success", r.success == true and #r.data == 3)
check("stacks no query", captured.url:find("%?") == nil, captured.url)

r = stacks_cmd(mkctx({ endpoint_id = 1 }))
check("stacks endpoint_id filter url",
      captured.url:find("filters=%%7B%%22EndpointID%%22%%3A1%%7D$") ~= nil,
      captured.url)

r = stacks_cmd(mkctx({ name = "animus_rpg" }))
check("stacks name filter url",
      captured.url:find("filters=%%7B%%22Name%%22%%3A%%22animus_rpg%%22%%7D$") ~= nil,
      captured.url)

r = stacks_cmd(mkctx({ endpoint_id = "nope" }))
check("stacks junk endpoint_id rejected", r.success == false and r.error:find("endpoint_id") ~= nil)

fixture = { status = 403, json = { message = "access denied" } }
r = stacks_cmd(mkctx())
check("stacks 403 normalized",
      r.success == false and r.error:find("forbidden") ~= nil and r.error:find("access denied") ~= nil)

-- ---- stack get --------------------------------------------------------------
fixture = { status = 200, json = {
  Id = 11, Name = "animus_rpg", Status = 1, Type = 2, EndpointId = 1,
  CreationDate = 1745000000, UpdateDate = 1790430000,
  Webhook = "wh_abc123", GitConfig = { URL = "https://github.com/x/y" }
} }
r = stack_get_cmd(mkctx({ stack_id = 11 }))
check("stack get success",
      r.success == true and r.data.Id == 11 and r.data.GitConfig.URL ~= nil)
check("stack get url", captured.url == "https://p.example.com/api/stacks/11")

r = stack_get_cmd(mkctx({}))
check("stack get missing id rejected", r.success == false and r.error:find("stack_id") ~= nil)

r = stack_get_cmd(mkctx({ stack_id = "1.5" }))
check("stack get non-integer rejected", r.success == false)

r = stack_get_cmd(mkctx({ stack_id = "999" }))
-- (still a valid REQUEST shape; server decides — fixture now 404)
fixture = { status = 404, json = { message = "Stack not found" } }
r = stack_get_cmd(mkctx({ stack_id = "999" }))
check("stack get 404 normalized",
      r.success == false and r.error:find("not found") ~= nil and r.http_status == 404)

-- ---- stack file -------------------------------------------------------------
fixture = { status = 200, json = { StackFileContent = "services:\n  a:\n    image: x\n" } }
r = stack_file_cmd(mkctx({ stack_id = 11 }))
check("stack file success (live PascalCase shape)",
      r.success == true and r.data.stack_file:find("services:") ~= nil)
fixture = { status = 200, json = { stackFileContent = "services:\n  b:\n    image: y\n" } }
r = stack_file_cmd(mkctx({ stack_id = 11 }))
check("stack file success (lowercase shape)",
      r.success == true and r.data.stack_file:find("image: y") ~= nil)
check("stack file url", captured.url == "https://p.example.com/api/stacks/11/file")

fixture = { status = 200, json = { wrong = "shape" } }
r = stack_file_cmd(mkctx({ stack_id = 11 }))
check("stack file wrong shape rejected",
      r.success == false and r.error:find("stackFileContent") ~= nil)

r = stack_file_cmd(mkctx({ stack_id = "" }))
check("stack file empty id rejected", r.success == false)

-- ---- config gate applies to all authenticated commands -----------------------
fixture = { status = 200, json = {} }
local nocfg = mkctx({}, {})
check("endpoints gates on config", endpoints_cmd(nocfg).success == false)
check("stacks gates on config", stacks_cmd(nocfg).success == false)
check("stack get gates on config", stack_get_cmd(nocfg).success == false)
check("stack file gates on config", stack_file_cmd(nocfg).success == false)

-- every command shares timeout 10 (v0.1.0 fence: no caller override)
status_cmd(mkctx({}, { base_url = "https://p.example.com" }))
check("timeout 10 everywhere", captured.timeout == 10)


-- ==== write lane (v0.2) =====================================================

-- stack start: gates ordered — writes disabled → refuse BEFORE any HTTP
do
  local start = load_cmd("stack_start")
  local ctx = mkctx({ stack_id = 11, confirm = "animus_test_node" }, { writes_enabled = "false", base_url = "https://p.example.com", api_key = "KEY1" })
  captured = nil
  local r = start(ctx)
  check("start: writes gate refuses", r.success == false)
  check("start: gate names the key", (r.error or ""):find("writes_enabled", 1, true) ~= nil)
  check("start: gate fires before any http", captured == nil, tostring(captured and captured.url))

  -- writes armed, no confirm → refuses after resolve, before write
  ctx = mkctx({ stack_id = 11 }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack() }
  local r2 = start(ctx)
  check("start: confirm required", (r2.error or ""):find("confirm required") ~= nil)
  check("start: error carries target name", (r2.error or ""):find("animus_test_node", 1, true) ~= nil)

  -- wrong confirm
  ctx = mkctx({ stack_id = 11, confirm = "postgres" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack() }
  local r3 = start(ctx)
  check("start: confirm mismatch refused", (r3.error or ""):find("confirm mismatch") ~= nil)

  -- correct: POST /stacks/11/start?endpointId=3
  ctx = mkctx({ stack_id = 11, confirm = "animus_test_node" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack(), fix_stack_started() }
  local r4 = start(ctx)
  check("start: success", r4.success == true)
  check("start: url shape", captured.verb == "POST" and
        captured.url == "https://p.example.com/api/stacks/11/start?endpointId=3", captured.url)
  check("start: audit line written", #logs == 1 and logs[1]:find("/start") ~= nil)
end

-- stack stop: same spine
do
  local stop = load_cmd("stack_stop")
  local ctx = mkctx({ stack_id = 11, confirm = "animus_test_node" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack(), fix_stack_started() }
  local r = stop(ctx)
  check("stop: success", r.success == true)
  check("stop: url shape", captured.url == "https://p.example.com/api/stacks/11/stop?endpointId=3", captured.url)
  check("stop: audit", #logs == 1)
end

-- stack redeploy: non-git → local refusal, no write; git → PUT with Prune=false
do
  local red = load_cmd("stack_redeploy")
  local ctx = mkctx({ stack_id = 11, confirm = "animus_test_node" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack() }
  local r = red(ctx)
  check("redeploy: non-git refused locally", (r.error or ""):find("not git%-backed") ~= nil)
  check("redeploy: no write issued", #logs == 0)

  local gitstack = fix_stack(); gitstack.json.GitConfig = { URL = "https://git" }
  ctx = mkctx({ stack_id = 11, confirm = "animus_test_node" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { gitstack, fix_stack_started() }
  local r2 = red(ctx)
  check("redeploy: git success", r2.success == true)
  check("redeploy: url", captured.verb == "PUT" and
        captured.url == "https://p.example.com/api/stacks/11/git/redeploy", captured.url)
  check("redeploy: prune pinned false", captured.body:find('"Prune":false') ~= nil)
end

-- stack update: identical → no write; changed → PUT + diff
do
  local upd = load_cmd("stack_update")
  local cur = { status = 200, json = { StackFileContent = "services:\n  a:\n    image: x\n" } }
  local ctx = mkctx({ stack_id = 11, confirm = "animus_test_node",
                      content = "services:\n  a:\n    image: x\n" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack(), cur }
  local r = upd(ctx)
  check("update: identical content no-op", r.success == true and r.data.changed == false)
  check("update: no write on no-op", captured.verb == "GET")

  ctx = mkctx({ stack_id = 11, confirm = "animus_test_node",
                content = "services:\n  a:\n    image: y\n" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { fix_stack(), cur, fix_stack_started() }
  local r2 = upd(ctx)
  check("update: changed success", r2.success == true and r2.data.changed == true)
  check("update: url carries endpointId", captured.verb == "PUT" and
        captured.url == "https://p.example.com/api/stacks/11?endpointId=3", captured.url)
  check("update: diff says 1 removed 1 added",
        r2.data.diff.removed_lines == 1 and r2.data.diff.added_lines == 1)
  check("update: diff sample has both lines",
        r2.data.diff.sample:find("image: x") ~= nil and r2.data.diff.sample:find("image: y") ~= nil)
  check("update: audit", #logs == 1 and logs[1]:find("?endpointId=3") ~= nil)
end

-- webhooks list: tokens masked
do
  local wl = load_cmd("webhooks_list")
  fixture = { status = 200, json = {
    { Id = 1, Token = "supersecret-token-abc", ResourceId = "11", EndpointId = 3, Type = 0 },
    { Id = 2, Token = "anothersecret", ResourceId = "11", EndpointId = 3, Type = 0 } } }
  local r = wl(mkctx())
  check("webhooks: success", r.success == true)
  check("webhooks: token masked", r.data[1].Token == "supe…" and r.data[2].Token == "anot…")
  check("webhooks: no full token anywhere",
        json.encode(r.data):find("supersecret%-token%-abc", 1) == nil and
        json.encode(r.data):find("anothersecret", 1, true) == nil)
end

-- webhook create: REMOVED from v0.2.0 — live catch #4: the OpenAPI enum {0,1}
-- is stale on CE 2.41.0; source: `_ = iota; ServiceWebhook` (1). Stack webhooks
-- are stack auto-update config (PUT /stacks/{id}/git AutoUpdate), not POST /webhooks.
-- Service webhooks (type 1) are out of this package's identity. Redesign = v0.2.x.

-- webhook delete: unknown id → not found, no DELETE; confirm=id → DELETE
do
  local wd = load_cmd("webhook_delete")
  fixture = { status = 200, json = { { Id = 9, Token = "t", ResourceId = "11", EndpointId = 3 } } }
  local ctx = mkctx({ webhook_id = 42, confirm = "42" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  local r = wd(ctx)
  check("webhook delete: unknown refused", (r.error or ""):find("not found") ~= nil)
  check("webhook delete: no DELETE issued", captured.verb ~= "DELETE")

  ctx = mkctx({ webhook_id = 9 }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { { status = 200, json = { { Id = 9, Token = "t", ResourceId = "11", EndpointId = 3 } } },
            { status = 202, json = {} } }
  local r2 = wd(ctx)
  check("webhook delete: confirm required", (r2.error or ""):find("confirm required") ~= nil)

    ctx = mkctx({ webhook_id = 9, confirm = "9" }, { writes_enabled = "true", base_url = "https://p.example.com", api_key = "KEY1" })
  queue = { { status = 200, json = { { Id = 9, Token = "t", ResourceId = "11", EndpointId = 3 } } },
            { status = 202, json = {} } }
  local r3 = wd(ctx)
  check("webhook delete: success", r3.success == true)
  check("webhook delete: url", captured.verb == "DELETE" and
        captured.url == "https://p.example.com/api/webhooks/9", captured.url)
end

print(failures == 0 and "ALL COMMAND TESTS PASSED" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
