local M = {}

local notes = require("nvim-markdown-notes.notes")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

---@param node_type string
---@return boolean
M.is_match = function(node_type)
  return node_type == "mention"
end

--- Check if graph is available and connected
---@return boolean
local function graph_available()
  if not M.opts or not M.opts.memgraph or not M.opts.memgraph.enabled then
    return false
  end
  local ok, graph = pcall(require, "nvim-markdown-notes.graph")
  return ok and graph.is_connected()
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
        local default_title = text:gsub("-", " "):gsub("(%a)([%w]*)", function(first, rest)
          return first:upper() .. rest
        end)
        local title = vim.fn.input({ prompt = "Note title: ", default = default_title })
        if title ~= "" then
          local new_filename = title:gsub(" ", "-"):lower()
          notes.create_note(title, M.opts.people_dir_path, new_filename)
          if new_filename ~= text then
            for child, _ in node:iter_children() do
              if child:type() == "mention_text" then
                local sr, sc, er, ec = child:range()
                vim.api.nvim_buf_set_text(0, sr, sc, er, ec, { new_filename })
                break
              end
            end
          end
        end
      end
    end)
  else
    vim.cmd('e ' .. vim.fn.fnameescape(note_filepath))
  end
end

-- View all files in the project that mention a specific person
-- Uses graph database if available, falls back to ripgrep
---@param person_name string Person name (without @)
M.find_person = function(person_name)
  -- Remove @ prefix if present
  person_name = person_name:gsub("^@", "")

  -- Use graph if available (faster and more accurate)
  if graph_available() then
    local graph = require("nvim-markdown-notes.graph")
    graph.find_by_mention(person_name)
    return
  end

  -- Fallback to ripgrep
  local pattern = '@' .. person_name .. '([^a-zA-Z0-9_-]|$)'

  pickers.new({}, {
    prompt_title = "Files mentioning: @" .. person_name,
    finder = finders.new_oneshot_job(
      { 'rg', '--vimgrep', '-e', pattern, M.opts.notes_root_path },
      {
        entry_maker = function(entry)
          local filename, lnum, col, text = entry:match("(.+):(%d+):(%d+):(.*)")
          return {
            value = entry,
            display = string.format("%s:%s\t%s", filename, lnum, text:gsub("^%s*", "")),
            ordinal = filename .. " " .. text,
            filename = filename,
            lnum = tonumber(lnum),
            col = tonumber(col),
          }
        end
      }
    ),
    previewer = conf.grep_previewer({}),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.cmd(string.format('edit +%d %s', selection.lnum, selection.filename))
      end)
      return true
    end,
  }):find()
end

-- List all people (from graph or people directory) and show them in telescope
-- Uses graph database if available (includes mention counts), falls back to directory listing
M.list_all_people = function()
  -- Use graph if available (faster and shows mention counts)
  if graph_available() then
    local graph = require("nvim-markdown-notes.graph")
    graph.browse_people()
    return
  end

  -- Fallback to directory listing
  if not M.opts or not M.opts.people_dir_path then
    vim.notify("People directory not configured", vim.log.levels.WARN)
    return
  end

  local files = vim.fn.glob(M.opts.people_dir_path .. "/*.md", false, true)
  local people = {}

  for _, file_path in ipairs(files) do
    local filename = vim.fn.fnamemodify(file_path, ":t:r")
    table.insert(people, {
      name = filename,
      path = file_path,
    })
  end

  if #people == 0 then
    vim.notify("No people found in " .. M.opts.people_dir_path, vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "All People",
    finder = finders.new_table {
      results = people,
      entry_maker = function(entry)
        return {
          value = entry,
          display = "@" .. entry.name,
          ordinal = entry.name,
          filename = entry.path,
        }
      end,
    },
    previewer = conf.grep_previewer({}),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- Default action: find notes mentioning this person
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.find_person(selection.value.name)
      end)
      -- Ctrl-o: open person's note directly
      map("i", "<C-o>", function()
        local selection = action_state.get_selected_entry()
        if selection and selection.filename then
          actions.close(prompt_bufnr)
          vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
        end
      end)
      map("n", "<C-o>", function()
        local selection = action_state.get_selected_entry()
        if selection and selection.filename then
          actions.close(prompt_bufnr)
          vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
        end
      end)
      return true
    end,
  }):find()
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
