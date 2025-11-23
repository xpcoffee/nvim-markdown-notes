local M = {}

M.create_top_level_note = function()
  local title = vim.fn.input("Note title: ")
  if title == "" then
    return
  end

  local note_filepath = M.create_note(title, M.opts.notes_root_path, title, M.opts.add_date_prefix)
  if note_filepath then
    vim.cmd("e " .. vim.fn.fnameescape(note_filepath))
  end
end

---Create a new note with title input, formatted as "YYYY-MM-dd title.md"
---@param title any
---@param root_path any
---@param filename any
---@param add_date_prefix any
---@return string?
M.create_note = function(title, root_path, filename, add_date_prefix)
  local note_filename = filename:gsub(" ", "-"):lower() .. ".md"
  local note_filepath = vim.fn.resolve(vim.fn.expand(vim.fs.joinpath(root_path, note_filename)))

  if add_date_prefix then
    local today = vim.fn.strftime("%Y-%m-%d")
    note_filename = today .. "-" .. note_filename
  end

  if type(note_filepath) == "string" then
    if vim.fn.filereadable(note_filepath) == 1 then
      vim.notify("Note already exists")
      return note_filepath;
    else
      local header = "# " .. title
      os.execute('echo "' .. header .. '" > "' .. note_filepath .. '"')
      vim.notify("Note created")
      return note_filepath;
    end
  end
end

--silly to make it a function, but makes this behaviour more explicit when reading other functions
local ignore_case = function(name)
  return name:lower();
end

M.get_file_path = function(root_path, relative_filename)
  local name_lower = ignore_case(relative_filename .. ".md")
  local expected_path = vim.fn.resolve(vim.fn.expand(vim.fs.joinpath(root_path, name_lower)))
  local dir = vim.fs.dirname(expected_path)
  local name = vim.fs.basename(expected_path)
  print("DEBUG: searching in " .. dir .. " for " .. name)

  -- Get all files in directory
  local files = vim.fs.find(function(filename)
    return ignore_case(filename) == name
  end, {
    path = dir,
    type = "file",
    limit = 1
  })

  return files[1]
end


---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
