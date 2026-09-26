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
  if type(r.json) ~= "table" or r.json.stackFileContent == nil then
    return { success = false, error = "unexpected response shape (expected stackFileContent)" }
  end
  return { success = true, data = { stack_file = r.json.stackFileContent } }
end
