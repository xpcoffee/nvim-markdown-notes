local M = {}

local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local conf = require('telescope.config').values

-- View all files in the project that contain a specific tag and show them in telescope
M.view_files_with_tag = function(tag)
  assert(M.notes_root_path, "notes_root_path must be configured")
  local next_match = string.match(tag, '#[a-zA-Z0-9-]+')

  if not next_match then
    print("No tag found under cursor")
    return
  end

  pickers.new({}, {
    prompt_title = "Files with tag: " .. next_match,
    finder = finders.new_oneshot_job(
      { 'rg', '--vimgrep', next_match },
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

-- List all tags in the project and show them intelescope
M.list_all_tags = function()
  assert(M.notes_root_path, "notes_root_path must be configured")

  local function get_all_tags()
    local command = string.format(
      "rg -o '(^|\\s)#[a-zA-Z0-9-]+' %s --no-filename --type markdown | sed 's/^\\s*//' | sort | uniq", M
      .notes_root_path)
    local tags = {}

    local handle = io.popen(command)
    if handle == nil then
      return tags;
    end

    local result = handle:read("*a")
    handle:close()
    for tag in result:gmatch("[^\r\n]+") do
      table.insert(tags, tag)
    end
    return tags
  end

  local tags = get_all_tags()

  pickers.new({}, {
    prompt_title = "All Tags",
    finder = finders.new_table {
      results = tags,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry,
          ordinal = entry,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.view_files_with_tag(selection.value)
      end)
      return true
    end,
  }):find()
end

-- Show a telescope menu with options for what journal to open
M.open_journal = function()
  assert(M.notes_root_path, "notes_root_path must be configured")
  assert(M.journal_dir_name, "journal_dir_name must be configured")

  local function get_date_options()
    local options = {}
    for i = 0, 5 do
      local date = os.date("%Y-%m-%d", os.time() - i * 86400)
      local label = date
      if i == 0 then
        label = label .. " (today)"
      elseif i == 1 then
        label = label .. " (yesterday)"
      end
      table.insert(options, { date = date, label = label })
    end
    return options
  end

  local date_options = get_date_options()

  pickers.new({}, {
    prompt_title = "Open Journal",
    finder = finders.new_table {
      results = date_options,
      entry_maker = function(entry)
        return {
          value = entry.date,
          display = entry.label,
          ordinal = entry.label,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local journal_file_name = selection.value .. ".md"
        local journal_file_path = vim.fn.expand(vim.fn.resolve(M.notes_root_path ..
          "/" .. M.journal_dir_name .. "/" .. journal_file_name))

        if type(journal_file_path) == "string" then
          if vim.fn.filereadable(journal_file_path) == 1 then
            vim.cmd('edit ' .. journal_file_path)
          else
            os.execute('echo "# ' .. selection.value .. '" > ' .. journal_file_path)
            vim.cmd('edit ' .. journal_file_path)
          end
        end
      end)
      return true
    end,
  }):find()
end

-- Find backlinks tto this file and list them in telescope
M.list_backlinks = function()
  assert(M.notes_root_path, "notes_root_path must be configured")

  local current_file = vim.fn.expand('%:t:r')
  local backlink_pattern = '%[%[' .. current_file .. '%]%]'
  local files_with_backlinks = {}

  local function search_backlinks(file)
    local f = io.open(file, "r")
    if f then
      local content = f:read("*all")
      f:close()
      for line in content:gmatch("[^\r\n]+") do
        if line:match(backlink_pattern) then
          table.insert(files_with_backlinks, { filename = file, line = line })
          break
        end
      end
    end
  end

  for file in vim.fn.glob(M.notes_root_path .. '/**/*.md'):gmatch("[^\r\n]+") do
    search_backlinks(file)
  end

  pickers.new({}, {
    prompt_title = "Backlinks to " .. current_file,
    finder = finders.new_table {
      results = files_with_backlinks,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.filename .. ": " .. entry.line,
          ordinal = entry.filename,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local file_path = selection.value.filename
        print('opening file: ' .. file_path)
        vim.cmd('edit ' .. file_path)
        local file = io.open(file_path, "r")
        if file then
          local content = file:read("*all")
          file:close()
          local line_num = 1
          for line in content:gmatch("[^\r\n]+") do
            if line == selection.value.line then
              vim.api.nvim_win_set_cursor(0, { line_num, 0 })
              break
            end
            line_num = line_num + 1
          end
        end
      end)
      return true
    end,
  }):find()
end


-- Open today's journal entry - populate it if it doesn't exist.
M.open_daily_journal = function()
  assert(M.notes_root_path, "notes_root_path must be configured")
  assert(M.journal_dir_name, "journal_dir_name must be configured")

  local today = vim.fn.strftime("%Y-%m-%d")
  local daily_note_file_name = today .. ".md"
  local daily_note_file_path = vim.fn.expand(vim.fn.resolve(M.notes_root_path ..
    "/" .. M.journal_dir_name .. "/" .. daily_note_file_name))


  if (type(daily_note_file_path) == "string") then
    if vim.fn.filereadable(daily_note_file_path) == 1 then
      vim.cmd('e ' .. daily_note_file_path)
    else
      os.execute('echo "# ' .. today .. '" > ' .. daily_note_file_path)
      vim.cmd('e ' .. daily_note_file_path)
    end
  end
end

-- Setup the extension: use user configuration & set up commands
M.setup = function(opts)
  M.notes_root_path = opts.notes_root_path:gsub("/$", "")
  M.journal_dir_name = opts.journal_dir_name
end

return M
