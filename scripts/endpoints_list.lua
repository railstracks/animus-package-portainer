-- endpoints list: environments (Docker/Swarm/K8s) known to this Portainer.
-- Fields (CE 2.x): Id, Name, Type (1=docker, 2=agent, 3=azure, 5/k8s...),
-- URL, GroupName, Status (1=up), Snapshots.
function run(ctx)
  local pkg = ctx.package
  local r = shared.get(ctx, pkg, "/endpoints", {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  if type(r.json) ~= "table" or (#r.json == 0 and next(r.json) ~= nil) then
    return { success = false, error = "unexpected response shape (expected array)" }
  end
  return { success = true, data = r.json }
end
