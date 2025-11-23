local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local notes = require("nvim-markdown-notes.notes")

local M = {}
M.opts = {}

-- Show a telescope menu with options for what journal to open
M.open_journal = function()
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

  pickers
      .new({}, {
        prompt_title = "Open Journal",
        finder = finders.new_table({
          results = date_options,
          entry_maker = function(entry)
            return {
              value = entry.date,
              display = entry.label,
              ordinal = entry.label,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            local journal_file_path = notes.get_file_path(M.opts.journal_dir_path, selection.value)

            if type(journal_file_path) == "string" then
              if vim.fn.filereadable(journal_file_path) == 1 then
                vim.cmd("edit " .. journal_file_path)
              else
                os.execute('echo "# ' .. selection.value .. '" > ' .. journal_file_path)
                vim.cmd("edit " .. journal_file_path)
              end
            end
          end)
          return true
        end,
      })
      :find()
end

-- Open today's journal entry - populate it if it doesn't exist.
M.open_daily_journal = function()
  local today = vim.fn.strftime("%Y-%m-%d")
  local daily_note_file_path = notes.get_file_path(M.opts.journal_dir_path, today)
  print(daily_note_file_path)

  if type(daily_note_file_path) == "string" and vim.fn.filereadable(daily_note_file_path) == 1 then
    vim.cmd("e " .. daily_note_file_path)
  else
    local title = today
    local file_path = notes.create_note(title, M.opts.journal_dir_path, today)
    if file_path then
      vim.cmd("e " .. vim.fn.fnameescape(file_path))
    end
  end
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
