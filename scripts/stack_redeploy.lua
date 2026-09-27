-- stack redeploy: git-backed stacks only — pull current source and redeploy.
-- Prune is FIXED false (deletion-class actions stay out of the lane; design
-- Q1). PullImage false. Non-git stacks fail with Portainer's own error.
function run(ctx)
  local pkg = ctx.package
  local res = stack_write_shared.resolve(ctx)
  if res.error ~= nil then return res end
  local st = res.stack
  if st.GitConfig == nil then
    return { success = false,
             error = "stack \"" .. st.Name .. "\" is not git-backed — redeploy applies to git stacks only (stack update for file-backed)" }
  end
  local body = {
    Env = {},
    Prune = false,          -- fenced: no deletion semantics, ever (design Q1)
    PullImage = false,
    RepositoryAuthentication = false
  }
  shared.audit_write(ctx, "PUT", "/stacks/" .. st.Id .. "/git/redeploy",
                     json.encode(body))
  local r = shared.put(ctx, pkg, "/stacks/" .. tostring(st.Id) .. "/git/redeploy",
                       {}, body, 60)
  if not r.ok then
    return { success = false, error = r.error, http_status = r.http_status }
  end
  return { success = true,
           data = { stack = st.Name, action = "redeploy (git, prune=false)",
                    status = (r.json ~= nil and r.json.Status) or nil } }
end
