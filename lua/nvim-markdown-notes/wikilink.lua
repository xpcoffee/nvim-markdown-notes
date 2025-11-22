local M = {}

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

local ignore_case = function(name)
  return name:lower();
end

local function get_file_path(notes_root, name)
  local name_lower = ignore_case(name .. ".md")

  -- Get all files in directory
  local files = vim.fs.find(function(filename)
    return ignore_case(filename) == name_lower
  end, {
    path = notes_root,
    type = "file",
    limit = 1
  })

  return files[1]
end


---@param node TSNode
M.jump = function(node)
  local text = get_text(node)
  local is_wikilink = text ~= nil;

  if not is_wikilink then
    return is_wikilink
  end

  local note_filepath = get_file_path(M.opts.notes_root_path, text)
  if note_filepath == nil then
    vim.ui.select({ 'Yes', 'No' }, { prompt = 'Note does not exist. Create it?' }, function(result)
      if result == 'Yes' then
        local new_filepath = vim.fn.expand(vim.fs.joinpath(M.opts.notes_root_path, text .. ".md"))
        vim.cmd('e ' .. vim.fn.fnameescape(new_filepath))
      end
    end)
  else
    vim.cmd('e ' .. vim.fn.fnameescape(note_filepath))
  end

  return is_wikilink
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
