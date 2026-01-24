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
  end
end

return M
