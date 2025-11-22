---@class MarkdownNotesOpts
---@field notes_root_path string Path to the notes directory
---@field journal_dir_name string Name of journal subdirectory
---@field auto_build? boolean Whether to auto-build parser
---@field highlights? {string: vim.api.keyset.highlight} Custom highlights
---@field debug_logging? boolean

---@class MarkdownNotesFullOpts
---@field notes_root_path string Path to the notes directory
---@field journal_dir_name string Name of journal subdirectory
---@field auto_build boolean Whether to auto-build parser
---@field highlights {string: vim.api.keyset.highlight} Custom highlights
---@field debug_logging boolean

local M = {}

local defaults = {
  auto_build = true,
  highlights = {
    ["@markup.wikilink"] = { link = "Special" },
    ["@markup.wikilink.text"] = { link = "Underlined" },
    ["@markup.mention"] = { link = "Special" },
    ["@markup.mention.text"] = { link = "Identifier" },
    ["@markup.tag"] = { link = "Tag" },
    ["@markup.tag.text"] = { link = "Tag" },
  },
  debug_logging = false
}

---@param opts table
---@return MarkdownNotesFullOpts
M.configure_options = function(opts)
  local options = vim.tbl_extend("force", defaults, opts, {
    notes_root_path = vim.fn.expand(opts.notes_root_path):gsub("/$", "")
  })

  assert(options.notes_root_path, "notes_root_path must be configured")
  assert(options.journal_dir_name, "journal_dir_name must be configured")

  return options
end


return M
