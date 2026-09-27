-- stack stop: deactivate a stack. Availability impact only — volumes and
-- definitions untouched. Write lane: state gate + confirm + audit.
function run(ctx)
  local pkg = ctx.package
  local res = stack_write_shared.resolve(ctx)
  if res.error ~= nil then return res end
  local st = res.stack
  shared.audit_write(ctx, "POST", "/stacks/" .. st.Id .. "/stop?endpointId=" ..
                     tostring(st.EndpointId), "")
  local r = shared.post(ctx, pkg, "/stacks/" .. tostring(st.Id) .. "/stop",
                        { endpointId = st.EndpointId, __order = { "endpointId" } }, {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  return { success = true,
           data = { stack = st.Name, action = "stop",
                    status = (r.json ~= nil and r.json.Status) or nil } }
end
