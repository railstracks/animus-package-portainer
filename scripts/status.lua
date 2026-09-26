-- status: Portainer version + instance id (works WITHOUT an API key — pre-flight)
function run(ctx)
  local pkg = ctx.package
  local r = shared.get(ctx, pkg, "/status", {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  return {
    success = true,
    data = {
      version = r.json.Version,
      instance_id = r.json.InstanceID
    }
  }
end
