--- Virtual titles module
--- Displays resolved titles inline for wikilinks and mentions using extmarks
local M = {}

local notes = require("nvim-markdown-notes.notes")

---@type MarkdownNotesFullOpts | nil
local opts = nil

local ns = vim.api.nvim_create_namespace("markdown_notes_virtual_titles")

-- Cache: filepath -> { title = string, mtime = number }
local title_cache = {}

--- Get the injected markdown_notes language tree for a buffer
---@param bufnr number
---@return table|nil child language tree
local function get_injected_tree(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return nil
  end

  local child = (parser:children() or {})["markdown_notes"]
  if not child then
    return nil
  end

  local tree_ok = pcall(function() return child:trees() end)
  if not tree_ok then
    child = child[1]
  end

  return child
end

--- Get the text content of a child node by type
---@param node TSNode
---@param child_type string
---@param bufnr number
---@return string|nil
local function get_child_text(node, child_type, bufnr)
  for c in node:iter_children() do
    if c:type() == child_type then
      return vim.treesitter.get_node_text(c, bufnr)
    end
  end
  return nil
end

--- Collect all wikilink and mention nodes from buffer
---@param bufnr number
---@return table[] Array of { type: string, text: string, range: {sr, sc, er, ec} }
local function collect_nodes(bufnr)
  local child = get_injected_tree(bufnr)
  if not child then
    return {}
  end

  local trees = child:trees()
  if not trees then
    return {}
  end

  local result = {}

  for _, tree in ipairs(trees) do
    local root = tree:root()

    local function traverse(node)
      local node_type = node:type()

      if node_type == "wikilink" then
        local link_text = get_child_text(node, "link_text", bufnr)
        if link_text then
          local sr, sc, er, ec = node:range()
          table.insert(result, {
            type = "wikilink",
            text = link_text,
            range = { sr, sc, er, ec },
          })
        end
      elseif node_type == "mention" then
        local mention_text = get_child_text(node, "mention_text", bufnr)
        if mention_text then
          local sr, sc, er, ec = node:range()
          table.insert(result, {
            type = "mention",
            text = mention_text,
            range = { sr, sc, er, ec },
          })
        end
      end

      for c in node:iter_children() do
        traverse(c)
      end
    end

    traverse(root)
  end

  return result
end

--- Get title from the first heading of a file, with mtime-based caching
---@param filepath string
---@return string|nil
local function get_title(filepath)
  local stat = vim.uv.fs_stat(filepath)
  if not stat then
    return nil
  end

  local cached = title_cache[filepath]
  if cached and cached.mtime == stat.mtime.sec then
    return cached.title
  end

  local f = io.open(filepath, "r")
  if not f then
    return nil
  end

  local first_line = f:read("*l")
  f:close()

  if not first_line then
    return nil
  end

  local title = first_line:gsub("^#+ ", "")
  title_cache[filepath] = { title = title, mtime = stat.mtime.sec }
  return title
end

--- Resolve a node to its display title
---@param node_type string "wikilink" or "mention"
---@param text string The raw link/mention text
---@return string|nil
local function resolve_title(node_type, text)
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

  local filepath = notes.get_file_path(root_path, text)
  if not filepath then
    return nil
  end

  return get_title(filepath)
end

--- Check if cursor position is inside a node range
---@param cursor_row number 0-indexed
---@param cursor_col number 0-indexed
---@param sr number start row
---@param sc number start col
---@param er number end row
---@param ec number end col
---@return boolean
local function cursor_in_range(cursor_row, cursor_col, sr, sc, er, ec)
  if cursor_row < sr or cursor_row > er then
    return false
  end
  if cursor_row == sr and cursor_col < sc then
    return false
  end
  if cursor_row == er and cursor_col >= ec then
    return false
  end
  return true
end

--- Update extmarks for virtual titles, expanding the node under the cursor
---@param bufnr number
---@param cursor_row number|nil 0-indexed
---@param cursor_col number|nil 0-indexed
local function update_extmarks(bufnr, cursor_row, cursor_col)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local nodes = collect_nodes(bufnr)

  for _, node in ipairs(nodes) do
    local sr, sc, er, ec = node.range[1], node.range[2], node.range[3], node.range[4]

    -- Skip the node under the cursor so raw text is visible
    if cursor_row and cursor_col and cursor_in_range(cursor_row, cursor_col, sr, sc, er, ec) then
      goto continue
    end

    local title = resolve_title(node.type, node.text)
    if not title then
      goto continue
    end

    local hl_group, display_text
    if node.type == "wikilink" then
      hl_group = "@markup.wikilink"
      display_text = "[[" .. title .. "]]"
    else
      hl_group = "@markup.mention"
      display_text = "@" .. title
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns, sr, sc, {
      end_row = er,
      end_col = ec,
      conceal = "",
      virt_text = { { display_text, hl_group } },
      virt_text_pos = "inline",
    })

    ::continue::
  end
end

--- Attach virtual titles to a buffer
---@param bufnr number
function M.attach(bufnr)
  if not opts or not opts.virtual_titles then
    return
  end

  -- Set conceallevel so conceal extmarks work, and concealcursor
  -- so conceal stays active on the cursor line in all modes
  vim.api.nvim_set_option_value("conceallevel", 2, { win = 0 })
  vim.api.nvim_set_option_value("concealcursor", "nvic", { win = 0 })

  -- Helper to get cursor and update
  local function render(bufnr_inner)
    local cursor = vim.api.nvim_win_get_cursor(0)
    update_extmarks(bufnr_inner, cursor[1] - 1, cursor[2])
  end

  -- Initial render
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    render(bufnr)
  end)

  local group = vim.api.nvim_create_augroup("MarkdownNotesVirtualTitles_" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      render(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      render(bufnr)
    end,
  })

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    buffer = bufnr,
    callback = function() end,
  })
end

---@param o MarkdownNotesFullOpts
function M.setup(o)
  opts = o
end

return M
