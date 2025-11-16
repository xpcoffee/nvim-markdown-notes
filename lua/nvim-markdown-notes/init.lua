local M = {}

local tags = require("nvim-markdown-notes.tags")
M.list_all_tags = tags.list_all_tags
M.view_files_with_tag = tags.view_files_with_tag

local journal = require("nvim-markdown-notes.journal")
M.open_daily_journal = journal.open_daily_journal
M.open_journal = journal.open_journal

local notes = require("nvim-markdown-notes.notes")
M.create_note = notes.create_note

M.custom_jump_to_tag = function()
  local word = vim.fn.expand('<cWORD>')
  tags.find_tag(M.notes_root_path, word)
end

-- Setup the extension: use user configuration & set up commands
M.setup = function(opts)
  M.notes_root_path = vim.fn.expand(opts.notes_root_path):gsub("/$", "")
  M.journal_dir_name = opts.journal_dir_name

  -- Set up autocommands for markdown files
  vim.api.nvim_create_augroup("MarkdownNotes", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = "MarkdownNotes",
    pattern = "markdown",
    callback = function()
      -- Map gf and Ctrl-] to follow_link function
      vim.keymap.set("n", "<C-]>", M.custom_jump_to_tag, { buffer = true, desc = "Follow note link" })
    end,
  })
end

return M
