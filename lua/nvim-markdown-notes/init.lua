local M = {}

local custom_parser = require("nvim-markdown-notes.treesitter_grammar")
local nvim_cmp_source = require("nvim-markdown-notes.cmp_wikilinks_completion_source")
local tags = require("nvim-markdown-notes.tags")
local journal = require("nvim-markdown-notes.journal")
local notes = require("nvim-markdown-notes.notes")
local wikilink = require("nvim-markdown-notes.wikilink")
local mentions = require("nvim-markdown-notes.mentions")

-- export functions from modules
M.list_all_tags = tags.list_all_tags
M.view_files_with_tag = tags.find_tag
M.open_daily_journal = journal.open_daily_journal
M.open_journal = journal.open_journal
M.create_note = notes.create_top_level_note
M.register_wikilink_cmp_source = nvim_cmp_source.register_cmp_source

--- custom jump-to-definition for my notes
M.custom_jump_to_tag = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local node = custom_parser.get_markdown_notes_node(bufnr, row, col)
  if not node then
    return nil
  end

  local node_type = node:type()
  if tags.is_match(node_type) then
    tags.jump(node)
  elseif wikilink.is_match(node_type) then
    wikilink.jump(node)
  elseif mentions.is_match(node_type) then
    mentions.jump(node)
  end
end

-- Setup the extension: use user configuration & set up commands
---@param opts MarkdownNotesOpts
M.setup = function(opts)
  local options = require("nvim-markdown-notes.options").configure_options(opts)
  notes.setup(options)
  tags.setup(options)
  journal.setup(options)
  wikilink.setup(options)
  mentions.setup(options)
  custom_parser.setup(options)

  -- Set up highlight groups for markdown_notes treesitter captures
  for group, settings in pairs(options.highlights) do
    vim.api.nvim_set_hl(0, group, settings)
  end

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
