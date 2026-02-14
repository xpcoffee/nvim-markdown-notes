--- Graph module for nvim-markdown-notes
--- Provides Memgraph integration for note relationships
local M = {}

M.connection = require("nvim-markdown-notes.graph.connection")
M.extractor = require("nvim-markdown-notes.graph.extractor")

---@type MarkdownNotesFullOpts | nil
M.opts = nil

-- Lazy load submodules that depend on connection
local function get_sync()
  return require("nvim-markdown-notes.graph.sync")
end

local function get_query()
  return require("nvim-markdown-notes.graph.query")
end

local function get_commands()
  return require("nvim-markdown-notes.graph.commands")
end

--- Check if Memgraph is enabled
---@return boolean
function M.is_enabled()
  return M.opts ~= nil and M.opts.memgraph.enabled
end

--- Check if connected to Memgraph
---@return boolean
function M.is_connected()
  return M.is_enabled() and M.connection.is_connected()
end

--- Get the sync module
---@return table
function M.get_sync()
  return get_sync()
end

--- Get the query module
---@return table
function M.get_query()
  return get_query()
end

--- Get the commands module
---@return table
function M.get_commands()
  return get_commands()
end

-- ===========================================
-- PRIMARY NAVIGATION EXPORTS
-- These are the recommended entry points for
-- searching and navigating notes via the graph.
-- ===========================================

--- Browse all tags (PRIMARY - use before full-text search)
--- Opens a Telescope picker with all tags sorted by usage
function M.browse_tags()
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().browse_tags()
end

--- Browse all people (PRIMARY - use before full-text search)
--- Opens a Telescope picker with all people sorted by mention count
function M.browse_people()
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().browse_people()
end

--- Find notes by tag (PRIMARY)
---@param tag string Tag name (with or without #)
function M.find_by_tag(tag)
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().show_tagged(tag)
end

--- Find notes mentioning a person (PRIMARY)
---@param person string Person name (with or without @)
function M.find_by_mention(person)
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().show_mentions(person)
end

--- Show backlinks to current note
function M.show_backlinks()
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().show_backlinks()
end

--- Show notes related to current note
function M.show_related()
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().show_related()
end

--- Reindex all notes
function M.reindex()
  if not M.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return
  end
  get_commands().reindex()
end

--- Setup the graph module
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
  M.opts = opts

  -- Setup submodules
  M.connection.setup(opts)
  M.extractor.setup(opts)

  if opts.memgraph.enabled then
    -- Defer loading of other modules
    vim.schedule(function()
      get_sync().setup(opts)
      get_query().setup(opts)
      get_commands().setup(opts)
    end)

    -- Manual install command
    vim.api.nvim_create_user_command("MemgraphInstallCLI", function()
      local installer = require("nvim-markdown-notes.graph.installer")
      installer.reset_declined()
      installer.ensure_cli(opts.memgraph, function(success)
        if success then
          vim.notify("[Memgraph] CLI is available", vim.log.levels.INFO)
        end
      end)
    end, { desc = "Install the Memgraph CLI tool" })
  end
end

return M
