-- stack get: one stack in full — Status (1=active, 2=inactive), Type
-- (1=swarm, 2=compose), EndpointID, creation/update dates, GitConfig when
-- git-backed, Webhook token when webhooks are enabled (treat as opaque).
function run(ctx)
  local pkg = ctx.package
  local id, err = shared.int_arg(ctx.args, "stack_id")
  if err then return { success = false, error = err } end
  if id == nil then
    return { success = false, error = "stack_id required (integer)" }
  end

  local r = shared.get(ctx, pkg, "/stacks/" .. tostring(id), {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  if type(r.json) ~= "table" then
    return { success = false, error = "unexpected response shape (expected object)" }
  end
  return { success = true, data = r.json }
end
