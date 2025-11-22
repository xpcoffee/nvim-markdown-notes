local M = {}

local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local conf = require('telescope.config').values

---@param node_type string
---@return boolean
M.is_match = function(node_type)
  return node_type == "hashtag"
end

---@param node TSNode
---@return string | nil
local get_text = function(node)
  for child, _ in node:iter_children() do
    if child:type() == "hashtag_text" then
      local text = vim.treesitter.get_node_text(child, 0)
      return text
    end
  end

  return nil
end

-- View all files in the project that contain a specific tag
-- Allow navigation to one via telescope
---@param node TSNode
M.jump = function(node)
  local tag_text = get_text(node)
  if not tag_text then
    return
  end

  M.find_tag(tag_text)
end

-- View all files in the project that contain a specific tag
-- Allow navigation to one via telescope
---@param tag_text string
M.find_tag = function(tag_text)
  pickers.new({}, {
    prompt_title = "Files with tag: " .. tag_text,
    finder = finders.new_oneshot_job(
      { 'rg', '--vimgrep', tag_text, M.opts.notes_root_path },
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
  local function get_all_tags()
    local command = string.format(
      "rg -o '(^|\\s)#[a-zA-Z0-9-]+' %s --no-filename --type markdown | sed 's/^\\s*//' | sort | uniq",
      M.opts.notes_root_path)
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
        M.find_tag(selection.value)
      end)
      return true
    end,
  }):find()
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
