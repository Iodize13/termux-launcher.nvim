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

local has_org, orgmode = pcall(require, "orgmode")
if not has_org and vim.pack then
  pcall(vim.pack.add, { "https://github.com/nvim-orgmode/orgmode" })
  has_org, orgmode = pcall(require, "orgmode")
end
if has_org then
  orgmode.setup({
    org_agenda_files = org_dir .. "/**/*",
    org_default_notes_file = org_dir .. "/inbox.org",
    -- The launcher shows the agenda inside its own main window.
    win_split_mode = "edit",
  })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "orgagenda",
    callback = function(ev)
      vim.keymap.set("n", "<2-LeftMouse>", "<CR>", { buffer = ev.buf, remap = true })
    end,
  })
end

require("launcher").setup({ notes_file = org_dir .. "/inbox.org" })

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      require("launcher").open()
    end
  end,
})
