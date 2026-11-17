local org_dir = vim.fn.expand(vim.env.ORG_DIR or "~/org")

vim.o.mouse = "a"
vim.o.termguicolors = true
vim.o.swapfile = false
vim.opt.fillchars:append({ stl = " ", stlnc = " " })

-- Drop every background so the Termux wallpaper shows through. Only the active
-- button and the selected result keep a solid colour.
local function transparent()
  local fg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg
  for _, name in ipairs({
    "Normal",
    "NormalNC",
    "EndOfBuffer",
    "SignColumn",
    "LineNr",
    "StatusLine",
    "StatusLineNC",
    "MsgArea",
    "LauncherButton",
  }) do
    vim.api.nvim_set_hl(0, name, { fg = fg })
  end
end
transparent()
vim.api.nvim_create_autocmd("ColorScheme", { callback = transparent })

-- The launcher is the one long-running process on the phone, so it owns the sync daemon.
if vim.fn.executable("teamtype") == 1 and vim.uv.fs_stat(org_dir .. "/.teamtype/config") then
  local socket = org_dir .. "/.teamtype/socket"
  local probe = vim.uv.new_pipe()
  probe:connect(socket, function(err)
    probe:close()
    if not err then
      return -- a daemon already serves this directory
    end
    vim.schedule(function()
      -- A killed daemon leaves its socket behind, and teamtype refuses to start over it.
      os.remove(socket)
      vim.fn.jobstart({ "teamtype", "join", "--directory", org_dir })
    end)
  end)
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- The launcher still works without orgmode, so a failed clone must not stop startup.
local has_lazy, lazy = pcall(require, "lazy")
if has_lazy then
  lazy.setup({
    spec = {
      {
        "nvim-orgmode/orgmode",
        -- The home screen is the agenda, so there is nothing to defer.
        lazy = false,
        opts = {
          org_agenda_files = org_dir .. "/**/*",
          org_default_notes_file = org_dir .. "/note.org",
          -- The launcher shows the agenda inside its own main window.
          win_split_mode = "edit",
        },
      },
      -- Syncs the org directory with the other devices when a teamtype daemon runs there.
      { "teamtype/teamtype-nvim", lazy = false },
    },
    -- Termux has no luarocks, and orgmode does not need it.
    rocks = { enabled = false },
    -- The default would switch to habamax while installing and change the launcher colours.
    install = { colorscheme = {} },
    change_detection = { enabled = false },
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "orgagenda",
  callback = function(ev)
    vim.keymap.set("n", "<2-LeftMouse>", "<CR>", { buffer = ev.buf, remap = true })
  end,
})

require("launcher").setup({
  notes = {
    { file = org_dir .. "/note.org", icon = "✎" },
    { file = org_dir .. "/inbox.org", icon = "✦" },
  },
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      require("launcher").open()
    end
  end,
})
