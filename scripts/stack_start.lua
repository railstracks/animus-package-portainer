-- stack start: activate a stopped stack. Write lane: state gate + confirm
-- + audit (docs/WRITE-LANE-DESIGN.md). Requires ?endpointId= (CE 2.41 live).
function run(ctx)
  local pkg = ctx.package
  local res = stack_write_shared.resolve(ctx)
  if res.error ~= nil then return res end
  local st = res.stack
  shared.audit_write(ctx, "POST", "/stacks/" .. st.Id .. "/start?endpointId=" ..
                     tostring(st.EndpointId), "")
  local r = shared.post(ctx, pkg, "/stacks/" .. tostring(st.Id) .. "/start",
                        { endpointId = st.EndpointId, __order = { "endpointId" } }, {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  return { success = true,
           data = { stack = st.Name, action = "start",
                    status = (r.json ~= nil and r.json.Status) or nil } }
end
