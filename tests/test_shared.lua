-- test_shared.lua — unit tests for _shared.lua (plain lua5.4).
-- Run: lua tests/test_shared.lua

shared = dofile("scripts/_shared.lua")

local failures = 0
local function check(label, cond, extra)
  if not cond then
    print("FAIL  " .. label .. (extra and (" — " .. tostring(extra)) or ""))
    failures = failures + 1
  else
    print("ok    " .. label)
  end
end

local function mkpkg(state)
  return { get_state = function(k) return (state or {})[k] end }
end

-- require_config ------------------------------------------------------------
local base, err = shared.require_config(mkpkg({}))
check("require_config rejects empty", base == nil and err ~= nil)
base, err = shared.require_config(mkpkg(nil))
check("require_config rejects nil state", base == nil)
base = shared.require_config(mkpkg({ base_url = "***" }))
check("require_config rejects redacted placeholder", base == nil)
base = shared.require_config(mkpkg({ base_url = "https://p.example.com" }))
check("require_config accepts url", base == "https://p.example.com")

-- normalize_base ------------------------------------------------------------
check("normalize strips trailing slash",
      shared.normalize_base("https://p.example.com/") == "https://p.example.com")
check("normalize strips trailing /api",
      shared.normalize_base("https://p.example.com/api") == "https://p.example.com")
check("normalize strips slash after api",
      shared.normalize_base("https://p.example.com/api/") == "https://p.example.com")
check("normalize keeps path prefixes alone",
      shared.normalize_base("https://p.example.com:9443") == "https://p.example.com:9443")

-- headers -------------------------------------------------------------------
local h = shared.headers(mkpkg({ api_key = "K1" }))
check("headers carry X-API-Key", h["X-API-Key"] == "K1")
h = shared.headers(mkpkg({}))
check("headers omit key when unset", h["X-API-Key"] == nil)
h = shared.headers(mkpkg({ api_key = "***" }))
check("headers omit redacted key", h["X-API-Key"] == nil)

-- int_arg -------------------------------------------------------------------
check("int_arg parses", shared.int_arg({ stack_id = "7" }, "stack_id") == 7)
check("int_arg parses typed", shared.int_arg({ stack_id = 7 }, "stack_id") == 7)
local v, e = shared.int_arg({ stack_id = "x" }, "stack_id")
check("int_arg rejects junk", v == nil and e ~= nil)
v, e = shared.int_arg({ stack_id = "1.5" }, "stack_id")
check("int_arg rejects non-integer", v == nil and e ~= nil)
check("int_arg nil when absent", shared.int_arg({}, "stack_id") == nil)

-- url_encode ----------------------------------------------------------------
check("url_encode escapes JSON",
      shared.url_encode('{"EndpointID":3}') == '%7B%22EndpointID%22%3A3%7D',
      shared.url_encode('{"EndpointID":3}'))
check("url_encode leaves safe", shared.url_encode("a-b_c.d~e") == "a-b_c.d~e")

-- build_query ---------------------------------------------------------------
check("build_query empty", shared.build_query({ __order = {} }) == "")
check("build_query skips empties",
      shared.build_query({ __order = { "a", "b" }, a = "", b = nil }) == "")
check("build_query joins",
      shared.build_query({ __order = { "a", "b" }, a = "1", b = "2" }) == "?a=1&b=2")
check("build_query encodes JSON",
      shared.build_query({ __order = { "filters" }, filters = '{"EndpointID":3}' })
        == "?filters=%7B%22EndpointID%22%3A3%7D")

-- interpret (error mapping) -------------------------------------------------
local r = shared.interpret(nil)
check("interpret nil response", r.ok == false and r.error ~= nil)
r = shared.interpret({ error = "conn refused" })
check("interpret transport error", r.ok == false and r.error:find("transport") ~= nil)
r = shared.interpret({ status = 200, json = { Version = "2.41.0" } })
check("interpret ok", r.ok == true and r.json.Version == "2.41.0")
r = shared.interpret({ status = 401, json = { message = "Unauthorized" } })
check("interpret 401 surfaces message",
      r.ok == false and r.error:find("unauthorized") and r.error:find("Unauthorized"))
r = shared.interpret({ status = 404, body = '{"message":"Stack not found"}' })
check("interpret 404 falls back to body", r.ok == false and r.error:find("not found"))

-- get (config gate + url build) ---------------------------------------------
local captured
local stub_ctx = {
  http = { get = function(url, opts)
    captured = { url = url, headers = opts.headers, timeout = opts.timeout_s }
    return { status = 200, json = {} }
  end }
}
r = shared.get(stub_ctx, mkpkg({}), "/status", {})
check("get gates on config", r.ok == false and r.error:find("base_url") ~= nil)
r = shared.get(stub_ctx, mkpkg({ base_url = "https://p.example.com/api/" }),
               "/stacks/1/file", {})
check("get builds /api path", captured.url == "https://p.example.com/api/stacks/1/file",
      captured.url)
check("get timeout is 10", captured.timeout == 10)
r = shared.get(stub_ctx, mkpkg({ base_url = "https://p.example.com" }),
               "/stacks", { __order = { "filters" }, filters = '{"EndpointID":3}' })
check("get appends encoded query",
      captured.url == "https://p.example.com/api/stacks?filters=%7B%22EndpointID%22%3A3%7D",
      captured.url)

print(failures == 0 and "ALL SHARED TESTS PASSED" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
