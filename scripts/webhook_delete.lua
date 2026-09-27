-- webhook delete: remove a webhook by id. Confirm = the webhook id string
-- (what webhooks list shows; ids are the natural handle for these objects).
-- Write lane gates apply.
function run(ctx)
  local pkg = ctx.package
  local ok, err = shared.require_writes(pkg)
  if not ok then return { success = false, error = err } end
  local wid, aerr = shared.int_arg(ctx.args, "webhook_id")
  if aerr then return { success = false, error = aerr } end
  if wid == nil then
    return { success = false, error = "webhook_id required (integer)" }
  end
  -- Resolve via list (no GET /webhooks/{id} route exists).
  local lst = shared.get(ctx, pkg, "/webhooks", {})
  if not lst.ok then
    return { success = false, error = lst.error, http_status = lst.http_status }
  end
  local found
  if type(lst.json) == "table" then
    for _, w in ipairs(lst.json) do
      if w.Id == wid then found = w break end
    end
  end
  if found == nil then
    return { success = false, error = "webhook " .. tostring(wid) .. " not found" }
  end
  local okc, cerr = shared.confirm_name(ctx.args, tostring(wid))
  if not okc then return { success = false, error = cerr } end
  shared.audit_write(ctx, "DELETE", "/webhooks/" .. tostring(wid), "")
  local r = shared.delete(ctx, pkg, "/webhooks/" .. tostring(wid))
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  return { success = true,
           data = { webhook_id = wid, action = "delete",
                    stack_id = found.ResourceId } }
end
