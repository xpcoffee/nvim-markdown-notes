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

--- Check if graph is available and connected
---@return boolean
local function graph_available()
  if not M.opts or not M.opts.memgraph or not M.opts.memgraph.enabled then
    return false
  end
  local ok, graph = pcall(require, "nvim-markdown-notes.graph")
  return ok and graph.is_connected()
end

-- View all files in the project that contain a specific tag
-- Uses graph database if available, falls back to ripgrep
---@param tag_text string
M.find_tag = function(tag_text)
  -- Remove # prefix if present
  tag_text = tag_text:gsub("^#", "")

  -- Use graph if available (faster and more accurate)
  if graph_available() then
    local graph = require("nvim-markdown-notes.graph")
    graph.find_by_tag(tag_text)
    return
  end

  -- Fallback to ripgrep
  -- Match tag followed by non-tag character or end of line
  -- Tag characters are: [a-zA-Z0-9_-]
  local pattern = '#' .. tag_text .. '([^a-zA-Z0-9_-]|$)'

  pickers.new({}, {
    prompt_title = "Files with tag: " .. tag_text,
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

-- List all tags in the project and show them in telescope
-- Uses graph database if available (includes usage counts), falls back to ripgrep
M.list_all_tags = function()
  -- Use graph if available (faster and shows usage counts)
  if graph_available() then
    local graph = require("nvim-markdown-notes.graph")
    graph.browse_tags()
    return
  end

  -- Fallback to ripgrep
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

M.is_completion_match = function(line)
  return line:match("%#$")
end

M.suggest = function(cmp)
  return {
    { label = "tag1", kind = cmp.lsp.CompletionItemKind.Reference },
    { label = "tag2", kind = cmp.lsp.CompletionItemKind.Reference },
  }
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
  M.opts = opts
end

return M
