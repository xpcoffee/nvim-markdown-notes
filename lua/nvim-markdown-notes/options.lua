---@class MemgraphOpts
---@field enabled? boolean Enable Memgraph integration (opt-in, default false)
---@field host? string Memgraph host (default "localhost")
---@field port? number Memgraph Bolt port (default 7687)
---@field auto_sync? boolean Sync on BufWritePost (default true)
---@field python_path? string Path to Python interpreter (default "python3")
---@field connection_timeout? number Connection timeout in ms (default 5000)
---@field sync_debounce? number Debounce delay for rapid saves in ms (default 500)
---@field install_prompt? boolean Prompt to install CLI if missing (default true)
---@field install_source? string pip/uv package specifier for CLI installation

---@class MarkdownNotesOpts
---@field notes_root_path string Path to the notes directory
---@field journal_dir_name? string Name of journal subdirectory
---@field people_dir_name? string Name of journal subdirectory
---@field auto_build? boolean Whether to auto-build parser
---@field highlights? {string: vim.api.keyset.highlight} Custom highlights
---@field debug_logging? boolean
---@field add_date_prefix? boolean
---@field memgraph? MemgraphOpts Memgraph graph database configuration

---@class MemgraphFullOpts
---@field enabled boolean Enable Memgraph integration
---@field host string Memgraph host
---@field port number Memgraph Bolt port
---@field auto_sync boolean Sync on BufWritePost
---@field python_path string Path to Python interpreter
---@field connection_timeout number Connection timeout in ms
---@field sync_debounce number Debounce delay for rapid saves in ms
---@field install_prompt boolean Prompt to install CLI if missing
---@field install_source string pip/uv package specifier for CLI installation

---@class MarkdownNotesFullOpts
---@field notes_root_path string Path to the notes directory
---@field journal_dir_path string Name of journal subdirectory
---@field people_dir_path string Name of journal subdirectory
---@field auto_build boolean Whether to auto-build parser
---@field highlights {string: vim.api.keyset.highlight} Custom highlights
---@field debug_logging boolean
---@field add_date_prefix boolean
---@field memgraph MemgraphFullOpts Memgraph graph database configuration

local M = {}

local memgraph_defaults = {
  enabled = false,
  host = "localhost",
  port = 7687,
  auto_sync = true,
  python_path = "python3",
  connection_timeout = 5000,
  sync_debounce = 500,
  install_prompt = true,
  install_source = "git+https://github.com/xpcoffee/nvim-markdown-notes-memgraph.git",
}

local defaults = {
  auto_build = true,
  journal_dir_name = "journal",
  people_dir_name = "people",
  highlights = {
    ["@markup.wikilink"] = { link = "Tag" },
    ["@markup.mention"] = { link = "Tag" },
    ["@markup.tag"] = { link = "Tag" },
  },
  debug_logging = false,
  add_date_prefix = true,
  memgraph = memgraph_defaults,
}

---@param opts table
---@return MarkdownNotesFullOpts
M.configure_options = function(opts)
  local notes_root_path = vim.fn.expand(opts.notes_root_path):gsub("/$", "")

  -- Merge memgraph options separately to handle nested table
  local memgraph_opts = vim.tbl_extend("force", memgraph_defaults, opts.memgraph or {})

  local options = vim.tbl_extend("force", defaults, opts)
  options = vim.tbl_extend("force", options, {
    notes_root_path = notes_root_path,
    journal_dir_path = vim.fs.joinpath(notes_root_path, options.journal_dir_name),
    people_dir_path = vim.fs.joinpath(notes_root_path, options.people_dir_name),
    memgraph = memgraph_opts,
  })

  assert(options.notes_root_path, "notes_root_path must be configured")

  return options
end


return M
