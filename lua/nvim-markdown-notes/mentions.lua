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
  return {
    { label = "mention1", kind = cmp.lsp.CompletionItemKind.Reference },
    { label = "mention2", kind = cmp.lsp.CompletionItemKind.Reference },
  }
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
