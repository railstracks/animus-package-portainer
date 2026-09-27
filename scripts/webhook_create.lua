-- webhook create: mint a stack-redeploy webhook (type 0). The response's
-- Token is masked — the operator reads the full token in the Portainer UI.
-- Write lane: state gate + confirm (target stack name) + audit.
function run(ctx)
  local pkg = ctx.package
  local res = stack_write_shared.resolve(ctx)
  if res.error ~= nil then return res end
  local st = res.stack
  local body = {
    EndpointID = st.EndpointId,
    ResourceID = tostring(st.Id),
    WebhookType = 0            -- 0 = stack webhook (1 = service; spec enum)
  }
  shared.audit_write(ctx, "POST", "/webhooks", json.encode(body))
  local r = shared.post(ctx, pkg, "/webhooks", {}, body)
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  return { success = true,
           data = { webhook = shared.mask_webhooks({ r.json })[1],
                    note = "token masked — full value visible in Portainer UI; curl POST <base>/api/stacks/webhooks/<token> to trigger" } }
end
