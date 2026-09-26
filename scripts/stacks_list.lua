-- stacks list: all stacks, optional filters (server-side via ?filters= JSON).
-- Portainer filter keys are PascalCase: EndpointID, SwarmID, Name.
function run(ctx)
  local pkg = ctx.package
  local a = ctx.args

  local filters = {}
  local endpoint_id, err = shared.int_arg(a, "endpoint_id")
  if err then return { success = false, error = err } end
  if endpoint_id ~= nil then filters.EndpointID = endpoint_id end
  if a.name ~= nil and a.name ~= "" then filters.Name = tostring(a.name) end

  local query = { __order = { "filters" } }
  if next(filters) ~= nil then
    query.filters = json.encode(filters)
  end

  local r = shared.get(ctx, pkg, "/stacks", query)
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  if type(r.json) ~= "table" or (#r.json == 0 and next(r.json) ~= nil) then
    return { success = false, error = "unexpected response shape (expected array)" }
  end
  return { success = true, data = r.json }
end
