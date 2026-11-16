local org_dir = vim.fn.expand(vim.env.ORG_DIR or "~/org")

vim.o.mouse = "a"
vim.o.termguicolors = true
vim.o.swapfile = false

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
