local M = {}

local notes = require("nvim-markdown-notes.notes")

---@param node_type string
---@return boolean
M.is_match = function(node_type)
  return node_type == "wikilink"
end

---@param node TSNode
---@return string | nil
local get_text = function(node)
  -- Navigate to find link_text node
  for child, _ in node:iter_children() do
    if child:type() == "link_text" then
      local text = vim.treesitter.get_node_text(child, 0)
      return text
    end
  end

  return nil
end

---@param node TSNode
M.jump = function(node)
  local text = get_text(node)

  local note_filepath = notes.get_file_path(M.opts.notes_root_path, text)
  if note_filepath == nil then
    vim.ui.select({ 'Yes', 'No' }, { prompt = 'Note does not exist. Create it?' }, function(result)
      if result == 'Yes' then
        notes.create_note("New note", M.opts.notes_root_path, text)
      end

      --todo replace the text in the node with the relative filepath
    end)
  else
    vim.cmd('e ' .. vim.fn.fnameescape(note_filepath))
  end
end

M.is_completion_match = function(line)
  return line:match("%[%[$")
end

M.suggest = function(cmp)
  return {
    { label = "wiki1", kind = cmp.lsp.CompletionItemKind.Reference },
    { label = "wiki2", kind = cmp.lsp.CompletionItemKind.Reference },
  }
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
