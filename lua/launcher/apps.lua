local M = {}

---@class LauncherItem
---@field component string  "package/activity", passed to `am start -n`
---@field text string       what the user sees and what fuzzy search matches

---@param lines string[]  "label<TAB>package/activity"
---@return LauncherItem[]
function M.parse(lines)
  local items = {}
  for _, line in ipairs(lines) do
    local label, component = line:match("^([^\t]+)\t(%S+/%S+)$")
    if label then
      local pkg = component:match("^[^/]+")
      items[#items + 1] = {
        component = component,
        text = label == pkg and pkg or (label .. "  " .. pkg),
      }
    end
  end
  return items
end

---@return LauncherItem[]
function M.load(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  return M.parse(vim.fn.readfile(path))
end

---@param cmd string[]
---@param path string
---@param done fun(items: LauncherItem[]?, err: string?)
function M.refresh(cmd, path, done)
  local ok, err = pcall(
    vim.system,
    cmd,
    { text = true },
    vim.schedule_wrap(function(res)
      local lines = vim.split(vim.trim(res.stdout or ""), "\n")
      local items = res.code == 0 and M.parse(lines) or {}
      if #items == 0 then
        return done(nil, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or "no launchable apps found")
      end
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile(lines, path)
      done(items)
    end)
  )
  if not ok then
    done(nil, tostring(err))
  end
end

---@param item LauncherItem
---@param cmd string[]  argv prefix, the component is appended
function M.launch(item, cmd)
  local argv = vim.list_extend(vim.deepcopy(cmd), { item.component })
  local ok, err = pcall(vim.system, argv, {}, function(res)
    if res.code ~= 0 then
      vim.schedule(function()
        vim.notify(("launcher: %s exited %d: %s"):format(argv[1], res.code, vim.trim(res.stderr or "")), vim.log.levels.ERROR)
      end)
    end
  end)
  if not ok then
    vim.notify("launcher: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
