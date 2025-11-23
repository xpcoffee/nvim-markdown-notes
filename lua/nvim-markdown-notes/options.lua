---@class MarkdownNotesOpts
---@field notes_root_path string Path to the notes directory
---@field journal_dir_name? string Name of journal subdirectory
---@field people_dir_name? string Name of journal subdirectory
---@field auto_build? boolean Whether to auto-build parser
---@field highlights? {string: vim.api.keyset.highlight} Custom highlights
---@field debug_logging? boolean
---@field add_date_prefix? boolean

---@class MarkdownNotesFullOpts
---@field notes_root_path string Path to the notes directory
---@field journal_dir_path string Name of journal subdirectory
---@field people_dir_path string Name of journal subdirectory
---@field auto_build boolean Whether to auto-build parser
---@field highlights {string: vim.api.keyset.highlight} Custom highlights
---@field debug_logging boolean
---@field add_date_prefix boolean

local M = {}

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
  add_date_prefix = true
}

---@param opts table
---@return MarkdownNotesFullOpts
M.configure_options = function(opts)
  local notes_root_path = vim.fn.expand(opts.notes_root_path):gsub("/$", "")

  local options = vim.tbl_extend("force", defaults, opts)
  options = vim.tbl_extend("force", options, {
    notes_root_path = notes_root_path,
    journal_dir_path = vim.fs.joinpath(notes_root_path, options.journal_dir_name),
    people_dir_path = vim.fs.joinpath(notes_root_path, options.people_dir_name)
  })

  assert(options.notes_root_path, "notes_root_path must be configured")

  return options
end


return M
