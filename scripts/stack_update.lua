-- stack update: replace a stack's stored compose definition. Highest-risk
-- command in the lane — the result carries a line diff of what changed
-- (fetched before writing; design Q3). PUT requires ?endpointId= (live).
function run(ctx)
  local pkg = ctx.package
  local res = stack_write_shared.resolve(ctx)
  if res.error ~= nil then return res end
  local st = res.stack
  local content = ctx.args.content
  if content == nil or content == "" then
    return { success = false,
             error = "content required (full new compose file as a string)" }
  end
  -- Current definition first — the diff IS the presentation.
  local cur = shared.get(ctx, pkg, "/stacks/" .. tostring(st.Id) .. "/file", {})
  if not cur.ok then
    return { success = false, error = cur.error, http_status = cur.http_status }
  end
  local cur_content = (type(cur.json) == "table") and
    (cur.json.stackFileContent or cur.json.StackFileContent) or nil
  local diff = shared.diff_summary(cur_content or "", tostring(content))
  if diff.added_lines == 0 and diff.removed_lines == 0 then
    return { success = true,
             data = { stack = st.Name, action = "update", changed = false,
                      note = "new content identical to current definition — no write issued" } }
  end
  local body = {
    stackFileContent = tostring(content),
    prune = false,        -- fenced: orphan services are never deleted here
    pullImage = false
  }
  shared.audit_write(ctx, "PUT",
                     "/stacks/" .. st.Id .. "?endpointId=" .. tostring(st.EndpointId),
                     body.stackFileContent)
  local r = shared.put(ctx, pkg, "/stacks/" .. tostring(st.Id),
                       { endpointId = st.EndpointId, __order = { "endpointId" } }, body, 60)
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status,
             diff = diff }
  end
  return { success = true,
           data = { stack = st.Name, action = "update", changed = true,
                    diff = diff,
                    status = (r.json ~= nil and r.json.Status) or nil,
                    note = "Status 3 = deploying (PUT response is async-start)" } }
end
