local M = {}

-- Create a new note with title input, formatted as "YYYY-MM-dd title.md"
M.create_note = function()
  assert(M.notes_root_path, "notes_root_path must be configured")

  local title = vim.fn.input("Note title: ")
  if title == "" then
    print("Note creation cancelled")
    return
  end

  local today = vim.fn.strftime("%Y-%m-%d")
  local note_filename = today .. " " .. title .. ".md"
  local note_filepath = vim.fn.expand(vim.fn.resolve(M.notes_root_path .. "/" .. note_filename))

  if type(note_filepath) == "string" then
    if vim.fn.filereadable(note_filepath) == 1 then
      print("Note already exists: " .. note_filename)
      vim.cmd('e ' .. vim.fn.fnameescape(note_filepath))
    else
      local header = "# " .. title
      os.execute('echo "' .. header .. '" > "' .. note_filepath .. '"')
      vim.cmd('e ' .. vim.fn.fnameescape(note_filepath))
      print("Created note: " .. note_filename)
    end
  end
end

local get_wiki_link_text = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1 -- Convert to 0-indexed

  -- Check if we're on a wikilink capture
  local captures = vim.treesitter.get_captures_at_pos(bufnr, row, col)
  local captures_names = vim.tbl_map(function(c) return c.capture end, captures)
  local is_wikilink = vim.tbl_contains(captures_names, "markup.wikilink.text")

  if not is_wikilink then
    return nil
  end

  -- Get the node at cursor
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

  if not node then
    return nil
  end

  -- Navigate to find link_text node
  -- The node might BE the link_text, or we need to walk up/down
  local current = node

  -- First, try to find link_text in current node or parents
  while current do
    print(vim.inspect(current) .. " type " .. current:type())
    if current:type() == "link_text" then
      local text = vim.treesitter.get_node_text(current, bufnr)
      return text:gsub("^%[%[", ""):gsub("%]%]$", "")
    end
    current = current:parent()
  end

  return nil
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
