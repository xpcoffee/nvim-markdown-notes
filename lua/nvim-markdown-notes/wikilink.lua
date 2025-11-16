local M = {}

local custom_parser = require("nvim-markdown-notes.treesitter_grammar")

local get_wiki_link_text = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  -- Check if we're on a wikilink capture
  local captures = vim.treesitter.get_captures_at_pos(bufnr, row, col)
  local captures_names = vim.tbl_map(function(c) return c.capture end, captures)
  local is_wikilink = vim.tbl_contains(captures_names, "markup.wikilink.text")

  if not is_wikilink then
    return nil
  end


  local node = custom_parser.get_markdown_notes_node(bufnr, row, col)
  if not node then
    return nil
  end

  -- Navigate to find link_text node
  local current = node
  while current do
    if current:type() == "link_text" then
      local text = vim.treesitter.get_node_text(current, bufnr)
      return text
    end
    current = current:parent()
  end

  return node
end

M.wiki_link_jump = function()
  local text = get_wiki_link_text()
  print(vim.inspect(text))

  if text == nil then
    return false
  end

  return true
end

return M
