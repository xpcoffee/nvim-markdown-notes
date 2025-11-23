local M = {}

local notes = require("nvim-markdown-notes.notes")

---@param node_type string
---@return boolean
M.is_match = function(node_type)
  return node_type == "mention"
end

---@param node TSNode
---@return string | nil
local get_text = function(node)
  -- Navigate to find link_text node
  for child, _ in node:iter_children() do
    if child:type() == "mention_text" then
      local text = vim.treesitter.get_node_text(child, 0)
      return text
    end
  end

  return nil
end


---@param node TSNode
M.jump = function(node)
  local text = get_text(node)

  local note_filepath = notes.get_file_path(M.opts.people_dir_path, text)
  if note_filepath == nil then
    vim.ui.select({ 'Yes', 'No' }, { prompt = 'Person not found. Create a new note for them?' }, function(result)
      if result == 'Yes' then
        notes.create_note("New person", M.opts.people_dir_path, text)
      end

      -- update the node text
    end)
  else
    vim.cmd('e ' .. vim.fn.fnameescape(note_filepath))
  end
end

M.is_completion_match = function(line)
  return line:match("%@$")
end

M.suggest = function(cmp)
  if not M.opts or not M.opts.people_dir_path then
    return {}
  end

  -- Get all markdown files from people directory
  local files = vim.fn.glob(M.opts.people_dir_path .. "/*.md", false, true)
  local items = {}

  for _, file_path in ipairs(files) do
    -- Get just the filename without path and .md extension
    local filename = vim.fn.fnamemodify(file_path, ":t:r")
    table.insert(items, {
      label = filename,
      kind = cmp.lsp.CompletionItemKind.Reference,
    })
  end

  return items
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
