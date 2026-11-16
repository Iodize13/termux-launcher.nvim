local api, fn = vim.api, vim.fn
local apps = require("launcher.apps")

local M = {}
local ns = api.nvim_create_namespace("launcher")
local ns_sel = api.nvim_create_namespace("launcher_sel")
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

local S = {
  mode = "search", ---@type "search"|"note"
  view = nil, ---@type "home"|"results"|"notes"|nil  what the main window shows
  items = {}, ---@type LauncherItem[]
  matches = {}, ---@type LauncherItem[]
  sel = 1,
  prompt_buf = nil,
  list_buf = nil,
  prompt_win = nil,
  main_win = nil,
}

local function message(lines)
  vim.bo[S.list_buf].modifiable = true
  api.nvim_buf_clear_namespace(S.list_buf, -1, 0, -1)
  local padded = {}
  for _ = #lines + 1, api.nvim_win_get_height(S.main_win) do
    padded[#padded + 1] = ""
  end
  api.nvim_buf_set_lines(S.list_buf, 0, -1, false, vim.list_extend(padded, lines))
  vim.bo[S.list_buf].modifiable = false
  if api.nvim_win_get_buf(S.main_win) ~= S.list_buf then
    api.nvim_win_set_buf(S.main_win, S.list_buf)
  end
  -- Row arithmetic for taps assumes one screen row per line.
  vim.wo[S.main_win][0].wrap = false
end

local config = {
  cache = fn.stdpath("cache") .. "/launcher-apps.tsv",
  refresh_cmd = { root .. "/bin/launcher-apps" },
  launch_cmd = nil, ---@type string[]?  defaults to termux-am, then am
  notes_file = "~/org/inbox.org",
  note = function(text)
    return { "* " .. text, "  [" .. os.date("%Y-%m-%d %a %H:%M") .. "]" }
  end,
  spacing = 1,
  -- Height of the home and note buttons in rows. Each button is half the screen wide.
  button_rows = 3,
  icons = { search = ">", note = "✎", home = "⌂" },
  -- Runs with the main window current and must leave the home buffer in it.
  home = function()
    local ok, org = pcall(require, "orgmode")
    if not (ok and pcall(function()
      org.agenda:agenda():wait(3000)
    end)) then
      message({ "  org agenda unavailable (nvim-orgmode did not load)" })
    end
  end,
}

local function step()
  return 1 + config.spacing
end

local function query()
  return api.nvim_buf_get_lines(S.prompt_buf, 0, 1, false)[1] or ""
end

-- Results grow upward from the prompt, so the best match is the bottom row.
local function row_of(i)
  return api.nvim_win_get_height(S.main_win) - 1 - (i - 1) * step()
end

local function paint_selection()
  api.nvim_buf_clear_namespace(S.list_buf, ns_sel, 0, -1)
  if S.matches[S.sel] then
    api.nvim_buf_set_extmark(S.list_buf, ns_sel, row_of(S.sel), 0, { line_hl_group = "LauncherSel" })
  end
end

local views = {}

function views.home()
  if S.view ~= "home" then
    api.nvim_win_call(S.main_win, config.home)
  end
end

function views.notes()
  if S.view ~= "notes" then
    api.nvim_win_call(S.main_win, function()
      vim.cmd.edit(fn.fnameescape(fn.expand(config.notes_file)))
      vim.cmd("normal! G")
    end)
  end
end

function views.results(q)
  local rows = math.max(1, math.floor(api.nvim_win_get_height(S.main_win) / step()))
  local found, positions = unpack(fn.matchfuzzypos(S.items, q, { key = "text", limit = rows }))
  local seen = {}
  for _, item in ipairs(found) do
    seen[item.component] = true
  end
  for _, item in ipairs(#found < rows and fn.matchfuzzy(S.items, q, { key = "pkg" }) or {}) do
    if #found < rows and not seen[item.component] then
      found[#found + 1] = item
    end
  end
  S.matches, S.sel = found, 1
  if #found == 0 then
    return message({ #S.items == 0 and "  no app list yet, run :LauncherRefresh" or "  no match" })
  end
  local lines = {}
  for i = #found, 1, -1 do
    lines[#lines + 1] = "  " .. found[i].text
    for _ = 1, i > 1 and config.spacing or 0 do
      lines[#lines + 1] = ""
    end
  end
  message(lines)
  for i, item in ipairs(found) do
    if item.text ~= item.pkg then
      api.nvim_buf_set_extmark(S.list_buf, ns, row_of(i), 0, {
        virt_text = { { "  " .. item.pkg, "Comment" } },
      })
    end
    for _, char in ipairs(positions[i] or {}) do
      api.nvim_buf_set_extmark(S.list_buf, ns, row_of(i), 2 + fn.byteidx(item.text, char), {
        end_col = 2 + fn.byteidx(item.text, char + 1),
        hl_group = "LauncherMatch",
      })
    end
  end
  paint_selection()
end

local function show(view, arg)
  views[view](arg)
  S.view = view
end

local function set_query(text)
  api.nvim_buf_set_lines(S.prompt_buf, 0, -1, false, { text })
end

local function save_note(text)
  local path = fn.expand(config.notes_file)
  fn.mkdir(vim.fs.dirname(path), "p")
  local buf = fn.bufadd(path)
  fn.bufload(buf)
  local empty = api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
  api.nvim_buf_set_lines(buf, empty and 0 or -1, -1, false, config.note(text))
  api.nvim_buf_call(buf, function()
    vim.cmd("silent write")
  end)
  if api.nvim_win_get_buf(S.main_win) == buf then
    api.nvim_win_set_cursor(S.main_win, { api.nvim_buf_line_count(buf), 0 })
  end
end

---@type table<string, { render: fun(q: string), submit: fun(q: string) }>
local modes = {
  search = {
    render = function(q)
      show(q == "" and "home" or "results", q)
    end,
    submit = function()
      local item = S.view == "results" and S.matches[S.sel]
      if item then
        apps.launch(item, config.launch_cmd)
        set_query("")
      end
    end,
  },
  note = {
    render = function()
      show("notes")
    end,
    submit = function(q)
      if q:match("%S") then
        save_note(vim.trim(q))
        set_query("")
      end
    end,
  },
}

local function render()
  modes[S.mode].render(query())
end

local function focus_prompt()
  api.nvim_set_current_win(S.prompt_win)
  vim.cmd("startinsert!")
end

local paint_bar

local function chrome()
  vim.wo[S.prompt_win].statuscolumn = "%#LauncherIcon# " .. config.icons[S.mode] .. " "
  paint_bar()
  vim.cmd.redrawstatus()
end

function M.submit()
  modes[S.mode].submit(query())
  render()
end

function M.move(delta)
  S.sel = math.max(1, math.min(#S.matches, S.sel + delta))
  paint_selection()
end

--- Swap search and note. The typed text stays, so a half-typed search can become a note.
function M.toggle()
  S.mode = S.mode == "search" and "note" or "search"
  chrome()
  render()
  focus_prompt()
end

function M.tap()
  local pos = fn.getmousepos()
  local i = math.floor((api.nvim_win_get_height(S.main_win) - pos.winrow) / step()) + 1
  if pos.winid == S.main_win and S.view == "results" and S.matches[i] then
    S.sel = i
    M.submit()
    focus_prompt()
  end
end

function M.refresh()
  apps.refresh(config.refresh_cmd, config.cache, function(items, err)
    if not items then
      return vim.notify("launcher: app list refresh failed: " .. err, vim.log.levels.WARN)
    end
    S.items = items
    vim.notify(("launcher: %d apps"):format(#items))
  end)
end

local function map(buf, modes_, lhs, rhs)
  vim.keymap.set(modes_, lhs, rhs, { buffer = buf, nowait = true })
end

local function scratch()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  return buf
end

local function ensure_buffers()
  if S.prompt_buf and api.nvim_buf_is_valid(S.prompt_buf) and api.nvim_buf_is_valid(S.list_buf) then
    return
  end
  S.prompt_buf, S.list_buf, S.bar_buf = scratch(), scratch(), scratch()
  map(S.bar_buf, { "i", "n" }, "<LeftRelease>", function()
    M.bar_tap()
  end)
  vim.bo[S.list_buf].modifiable = false

  api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, { buffer = S.prompt_buf, callback = render })
  map(S.prompt_buf, { "i", "n" }, "<CR>", M.submit)
  map(S.prompt_buf, { "i", "n" }, "<Tab>", M.toggle)
  map(S.prompt_buf, { "i", "n" }, "<Esc>", M.open)
  for lhs, delta in pairs({ ["<Up>"] = 1, ["<C-p>"] = 1, ["<Down>"] = -1, ["<C-n>"] = -1 }) do
    map(S.prompt_buf, { "i", "n" }, lhs, function()
      M.move(delta)
    end)
  end
  map(S.list_buf, { "i", "n" }, "<LeftRelease>", M.tap)
end

local function ensure_layout()
  ensure_buffers()
  local bar_rows = config.button_rows - 1
  local valid = S.prompt_win and api.nvim_win_is_valid(S.prompt_win) and api.nvim_win_is_valid(S.main_win)
  if valid and (bar_rows == 0 or api.nvim_win_is_valid(S.bar_win)) then
    return
  end
  vim.cmd("silent! only")
  S.main_win = api.nvim_get_current_win()
  -- The prompt's statusline is the top row of the buttons. Extra rows are a window below it.
  S.bar_win = bar_rows > 0
      and api.nvim_open_win(S.bar_buf, false, { split = "below", win = S.main_win, height = bar_rows })
    or nil
  S.prompt_win = api.nvim_open_win(S.prompt_buf, true, { split = "below", win = S.main_win, height = 1 })
  for _, win in ipairs({ S.prompt_win, S.bar_win }) do
    for name, value in pairs({ winfixheight = true, number = false, relativenumber = false, signcolumn = "no", wrap = false }) do
      vim.wo[win][name] = value
    end
  end
  vim.wo[S.prompt_win].statusline = "%!v:lua.require'launcher'.buttons()"
end

local buttons = {
  { icon = "home", tap = function() M.open() end, active = function() return false end },
  { icon = "note", tap = function() M.toggle() end, active = function() return S.mode == "note" end },
}

local function button_hl(id)
  return buttons[id].active() and "LauncherButtonOn" or "LauncherButton"
end

-- One row of the two buttons as padded text. The statusline row and the bar window
-- rows both use it so the seam between the buttons lines up.
local function button_cells(width, with_icon)
  local widths = { math.floor(width / 2), width - math.floor(width / 2) }
  local cells = {}
  for id, button in ipairs(buttons) do
    local icon = with_icon and config.icons[button.icon] or ""
    local pad = widths[id] - fn.strdisplaywidth(icon)
    cells[id] = (" "):rep(math.floor(pad / 2)) .. icon .. (" "):rep(pad - math.floor(pad / 2))
  end
  return cells
end

function M.buttons()
  local cells = button_cells(api.nvim_win_get_width(S.prompt_win), config.button_rows == 1)
  for id, cell in ipairs(cells) do
    cells[id] = ("%%#%s#%%%d@v:lua.LauncherTap@%s%%X"):format(button_hl(id), id, cell)
  end
  return table.concat(cells)
end

function paint_bar()
  if not S.bar_win then
    return
  end
  local lines, split = {}, {}
  for row = 1, api.nvim_win_get_height(S.bar_win) do
    local cells = button_cells(api.nvim_win_get_width(S.bar_win), row == 1)
    lines[row], split[row] = table.concat(cells), #cells[1]
  end
  api.nvim_buf_set_lines(S.bar_buf, 0, -1, false, lines)
  for row, col in ipairs(split) do
    api.nvim_buf_set_extmark(S.bar_buf, ns, row - 1, 0, { end_col = col, hl_group = button_hl(1) })
    api.nvim_buf_set_extmark(S.bar_buf, ns, row - 1, col, { end_col = #lines[row], hl_group = button_hl(2) })
  end
end

function M.bar_tap()
  local pos = fn.getmousepos()
  if pos.winid == S.bar_win then
    buttons[pos.wincol <= math.floor(api.nvim_win_get_width(S.bar_win) / 2) and 1 or 2].tap()
  end
end

--- Show the launcher at its home screen. Safe to call again from any state.
function M.open()
  -- Set before the windows exist. Changing cmdheight later hands its row to the bottom window.
  vim.o.showtabline, vim.o.cmdheight, vim.o.showmode = 0, 0, false
  -- With a bar window the buttons end in that window, so the last window needs no statusline.
  vim.o.laststatus = config.button_rows > 1 and 0 or 2
  ensure_layout()
  if #S.items == 0 then
    S.items = apps.load(config.cache)
    if #S.items == 0 then
      M.refresh()
    end
  end
  vim.go.statusline = "%#WinSeparator#%{repeat('─', winwidth(0))}"
  S.mode, S.view = "search", nil
  set_query("")
  chrome()
  render()
  focus_prompt()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  config.launch_cmd = config.launch_cmd
    or { fn.executable("termux-am") == 1 and "termux-am" or "am", "start", "-n" }

  _G.LauncherTap = function(id)
    vim.schedule(buttons[id].tap)
  end
  for name, link in pairs({ LauncherSel = "PmenuSel", LauncherMatch = "Special", LauncherIcon = "Title" }) do
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
  -- A statusline blends a linked or partial group with StatusLine, so a button would change
  -- colour between its statusline row and its window rows. Resolve to explicit colours.
  local function solid_buttons()
    local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
    for name, source in pairs({ LauncherButton = "Pmenu", LauncherButtonOn = "PmenuSel" }) do
      local hl = api.nvim_get_hl(0, { name = source, link = false })
      local fg, bg = hl.fg or normal.fg or 0xe0e2ea, hl.bg or normal.bg or 0x14161b
      if hl.reverse then
        fg, bg = bg, fg
      end
      api.nvim_set_hl(0, name, { fg = fg, bg = bg, default = true })
    end
  end
  solid_buttons()
  api.nvim_create_autocmd("ColorScheme", { callback = solid_buttons })
  api.nvim_create_user_command("Launcher", M.open, {})
  api.nvim_create_user_command("LauncherRefresh", M.refresh, {})
  api.nvim_create_autocmd("VimResized", {
    callback = function()
      if S.bar_win and api.nvim_win_is_valid(S.bar_win) then
        paint_bar()
      end
    end,
  })
  api.nvim_create_autocmd("WinEnter", {
    callback = function()
      if api.nvim_get_current_win() == S.prompt_win then
        vim.cmd("startinsert!")
      else
        vim.cmd("stopinsert")
      end
    end,
  })
end

return M
