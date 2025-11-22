local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

local M = {}
M.opts = {}

-- Show a telescope menu with options for what journal to open
M.open_journal = function()
  assert(M.opts.notes_root_path, "notes_root_path must be configured")
  assert(M.opts.journal_dir_name, "journal_dir_name must be configured")

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
            local journal_file_name = selection.value .. ".md"
            local journal_file_path = vim.fn.expand(
              vim.fn.resolve(M.opts.notes_root_path .. "/" .. M.opts.journal_dir_name .. "/" .. journal_file_name)
            )

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
  local daily_note_file_name = today .. ".md"
  local daily_note_file_path =
      vim.fn.expand(vim.fn.resolve(M.opts.notes_root_path ..
        "/" .. M.opts.journal_dir_name .. "/" .. daily_note_file_name))

  if type(daily_note_file_path) == "string" then
    if vim.fn.filereadable(daily_note_file_path) == 1 then
      vim.cmd("e " .. daily_note_file_path)
    else
      os.execute('echo "# ' .. today .. '" > ' .. daily_note_file_path)
      vim.cmd("e " .. daily_note_file_path)
    end
  end
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
