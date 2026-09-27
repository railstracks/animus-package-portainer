-- Shared spine for stack write commands (inlined after _shared.lua by build.py)
stack_write_shared = {}

-- Shared spine for stack write commands: writes-gate → arg check → resolve
-- target (read) → confirm name-match → audit → write. Fails before any
-- network write on every gate miss (docs/WRITE-LANE-DESIGN.md).
function stack_write_shared.resolve(ctx)
  local pkg = ctx.package
  local ok, err = shared.require_writes(pkg)
  if not ok then return { success = false, error = err } end
  local id, aerr = shared.int_arg(ctx.args, "stack_id")
  if aerr then return { success = false, error = aerr } end
  if id == nil then
    return { success = false, error = "stack_id required (integer)" }
  end
  -- Resolve first: the confirm gate matches the target's real name.
  local r = shared.get(ctx, pkg, "/stacks/" .. tostring(id), {})
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  if type(r.json) ~= "table" or r.json.Name == nil then
    return { success = false, error = "unexpected stack shape (no Name)" }
  end
  local okc, cerr = shared.confirm_name(ctx.args, r.json.Name)
  if not okc then return { success = false, error = cerr, stack = r.json.Name } end
  return { stack = r.json }
end
