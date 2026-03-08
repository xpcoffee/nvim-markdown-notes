--- Floating preview module
--- Shows a floating window with the contents of the file under a wikilink or mention
local M = {}

local notes = require("nvim-markdown-notes.notes")
local custom_parser = require("nvim-markdown-notes.treesitter_grammar")
local wikilink = require("nvim-markdown-notes.wikilink")
local mentions = require("nvim-markdown-notes.mentions")

---@type MarkdownNotesFullOpts | nil
local opts = nil

-- Track the current preview window
local preview_win = nil
local preview_buf = nil

--- Close the preview window if open
local function close_preview()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
    vim.api.nvim_buf_delete(preview_buf, { force = true })
  end
  preview_win = nil
  preview_buf = nil
end

--- Get the wikilink or mention node under the cursor
---@param bufnr number
---@return TSNode|nil, string|nil node and node_type
local function get_node_under_cursor(bufnr)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local node = custom_parser.get_markdown_notes_node(bufnr, row, col, "markdown_notes")
  if not node then
    node = custom_parser.get_markdown_notes_node(bufnr, row, col, "markdown_inline")
  end

  if not node then
    return nil, nil
  end

  local node_type = node:type()
  if wikilink.is_match(node_type) or mentions.is_match(node_type) then
    return node, node_type
  end

  return nil, nil
end

--- Get text from a node based on its type
---@param node TSNode
---@param node_type string
---@param bufnr number
---@return string|nil
local function get_node_text(node, node_type, bufnr)
  local child_type = node_type == "wikilink" and "link_text" or "mention_text"
  for child in node:iter_children() do
    if child:type() == child_type then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  return nil
end

--- Resolve node to filepath
---@param node_type string
---@param text string
---@return string|nil
local function resolve_filepath(node_type, text)
  if not opts then
    return nil
  end

  local root_path
  if node_type == "wikilink" then
    root_path = opts.notes_root_path
  elseif node_type == "mention" then
    root_path = opts.people_dir_path
  else
    return nil
  end

  return notes.get_file_path(root_path, text)
end

--- Toggle preview window for the link under cursor
function M.toggle_preview()
  -- If preview is open, close it
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    close_preview()
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local node, node_type = get_node_under_cursor(bufnr)
  if not node or not node_type then
    return
  end

  local text = get_node_text(node, node_type, bufnr)
  if not text then
    return
  end

  local filepath = resolve_filepath(node_type, text)
  if not filepath then
    vim.notify("File not found for: " .. text, vim.log.levels.WARN)
    return
  end

  local lines = vim.fn.readfile(filepath)
  if not lines or #lines == 0 then
    return
  end

  -- Create scratch buffer
  preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = preview_buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = preview_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf })

  -- Calculate window dimensions
  local max_width = math.floor(vim.o.columns * 0.6)
  local max_height = math.floor(vim.o.lines * 0.5)
  local width = math.min(max_width, 80)
  local height = math.min(max_height, #lines)

  preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
  })

  -- Auto-close on cursor move or buffer leave
  local close_group = vim.api.nvim_create_augroup("MarkdownNotesPreviewClose", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
    group = close_group,
    buffer = bufnr,
    once = true,
    callback = function()
      close_preview()
      pcall(vim.api.nvim_del_augroup_by_id, close_group)
    end,
  })
end

--- Attach preview keymap to buffer
---@param bufnr number
function M.attach(bufnr)
  if not opts then
    return
  end

  vim.keymap.set("n", opts.preview_keymap, M.toggle_preview, {
    buffer = bufnr,
    desc = "Preview linked note",
  })
end

---@param o MarkdownNotesFullOpts
function M.setup(o)
  opts = o
end

return M
