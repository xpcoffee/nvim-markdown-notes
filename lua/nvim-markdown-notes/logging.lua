local M = {}

---@param opts MarkdownNotesFullOpts
---@param message unknown
M.log = function(opts, message)
  if opts.debug_logging then
    print("nvim-markdown-notes:: " .. vim.inspect(message))
  end
end

return M
