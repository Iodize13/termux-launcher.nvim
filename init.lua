local org_dir = vim.fn.expand(vim.env.ORG_DIR or "~/org")

-- Space sits under the thumb on a phone keyboard. Backslash hides on a symbols page.
-- Plugins read the leader when they map keys, so set it before lazy.nvim loads them.
vim.g.mapleader = " "

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
          -- Keep in sync with ~/dotfiles, since both edit the same synced ~/org.
          org_todo_keywords = { "TODO", "|", "DONE", "KILL" },
          -- The launcher shows the agenda inside its own main window.
          win_split_mode = "edit",
          -- Tags are right-aligned virtual text, so on a phone-width screen they cover the title.
          org_agenda_remove_tags = true,
          org_agenda_skip_deadline_if_done = true,
          org_agenda_skip_scheduled_if_done = true,
        },
        config = function(_, opts)
          require("orgmode").setup(opts)
          -- Every line starts with its file's name padded to 11 columns, which is a quarter
          -- of a phone screen and says nothing here. orgmode has no option for it, so blank
          -- that first token and re-add the tokens to recompute their highlight ranges.
          local function drop_category(class, method)
            local build = class[method]
            class[method] = function(...)
              local line = build(...)
              local tokens = line.tokens
              tokens[1].content = " "
              line.tokens, line.col_counter = {}, 1
              for _, token in ipairs(tokens) do
                line:add_token(token)
              end
              return line
            end
          end
          local agenda = require("orgmode.agenda.types.agenda")
          drop_category(agenda, "_build_line")
          drop_category(agenda, "_build_time_grid_line")
          drop_category(require("orgmode.agenda.types.todo"), "_build_line")
        end,
      },
      -- Syncs the org directory with the other devices when a teamtype daemon runs there.
      { "teamtype/teamtype-nvim", lazy = false },
      -- Lists what each prefix leads to, so orgmode's <leader>o keys need no memorising.
      {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {
          -- One mapping per row at the screen bottom reads better on a narrow screen than columns.
          preset = "helix",
          -- A phone keyboard is slow, so show the popup almost at once.
          delay = 200,
          -- orgmode names its keys but not its prefixes, which would read "+7 keymaps".
          spec = {
            { "<leader>o", group = "org" },
            { "<leader>ob", group = "babel" },
            { "<leader>od", group = "date" },
            { "<leader>oi", group = "insert" },
            { "<leader>ol", group = "link" },
          },
        },
      },
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
    -- orgmode sets nowrap right after this event, so wrap long titles on the next tick instead.
    vim.schedule(function()
      for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
        vim.wo[win][0].wrap = true
        vim.wo[win][0].linebreak = true
        vim.wo[win][0].breakindent = true
        vim.wo[win][0].breakindentopt = "shift:2"
      end
    end)
  end,
})

require("launcher").setup({
  notes = {
    { file = org_dir .. "/inbox.org", icon = "✦" },
    { file = org_dir .. "/note.org", icon = "✎" },
  },
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      require("launcher").open()
    end
  end,
})
