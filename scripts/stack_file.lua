-- stack file: the stack's compose definition (stackFileContent string,
-- passed through verbatim — no re-interpretation).
function run(ctx)
  local pkg = ctx.package
  local id, err = shared.int_arg(ctx.args, "stack_id")
  if err then return { success = false, error = err } end
  if id == nil then
    return { success = false, error = "stack_id required (integer)" }
  end

  local r = shared.get(ctx, pkg, "/stacks/" .. tostring(id) .. "/file", {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  -- Live catch (CE 2.41.0, field-tested): GET /stacks/{id}/file returns
  -- PascalCase "StackFileContent" while most other endpoints are lowercase.
  -- Accept both; the value passes through verbatim either way.
  local content = (type(r.json) == "table") and
    (r.json.stackFileContent or r.json.StackFileContent)
  if content == nil then
    return { success = false, error = "unexpected response shape (expected stackFileContent)" }
  end
  return { success = true, data = { stack_file = content } }
end
