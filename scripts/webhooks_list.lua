-- webhooks list: all webhooks, TOKENS MASKED (standing rule: webhook tokens
-- are never logged, echoed, or error-included — docs/ENDPOINTS.md).
function run(ctx)
  local pkg = ctx.package
  local r = shared.get(ctx, pkg, "/webhooks", {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  if type(r.json) ~= "table" then
    return { success = false, error = "unexpected response shape (expected array)" }
  end
  return { success = true, data = shared.mask_webhooks(r.json) }
end
