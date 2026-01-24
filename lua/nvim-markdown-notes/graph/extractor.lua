--- Graph entity extractor module
--- Extracts wikilinks, mentions, and hashtags from buffers using treesitter
local M = {}

---@type MarkdownNotesFullOpts | nil
M.opts = nil

--- Get the text content of a child node by type
---@param node TSNode
---@param child_type string
---@param bufnr number
---@return string | nil
local function get_child_text(node, child_type, bufnr)
  for child in node:iter_children() do
    if child:type() == child_type then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  return nil
end

--- Extract wikilinks from a buffer
---@param bufnr number
---@return table[] Array of {target: string, target_path: string, line_number: number}
function M.extract_wikilinks(bufnr)
  local wikilinks = {}

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  if not parser then
    return wikilinks
  end

  local child = (parser:children() or {})["markdown_notes"]
  if not child then
    return wikilinks
  end

  -- Handle if child is a list
  local ok = pcall(function() return child:trees() end)
  if not ok then
    child = child[1]
  end
  if not child then
    return wikilinks
  end

  local trees = child:trees()
  if not trees then
    return wikilinks
  end

  for _, tree in ipairs(trees) do
    local root = tree:root()

    -- Traverse tree looking for wikilink nodes
    local function traverse(node)
      if node:type() == "wikilink" then
        local link_text = get_child_text(node, "link_text", bufnr)
        if link_text then
          local start_row = node:range()
          -- Resolve the target path
          local target_path = nil
          if M.opts then
            local notes = require("nvim-markdown-notes.notes")
            target_path = notes.get_file_path(M.opts.notes_root_path, link_text)
            -- If file doesn't exist yet, create expected path
            if not target_path then
              target_path = vim.fs.joinpath(M.opts.notes_root_path, link_text .. ".md")
            end
          end

          table.insert(wikilinks, {
            target = link_text,
            target_path = target_path,
            line_number = start_row + 1, -- 1-indexed
          })
        end
      end

      for child_node in node:iter_children() do
        traverse(child_node)
      end
    end

    traverse(root)
  end

  return wikilinks
end

--- Extract mentions from a buffer
---@param bufnr number
---@return table[] Array of {name: string, line_number: number}
function M.extract_mentions(bufnr)
  local mentions = {}

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  if not parser then
    return mentions
  end

  local child = (parser:children() or {})["markdown_notes"]
  if not child then
    return mentions
  end

  local ok = pcall(function() return child:trees() end)
  if not ok then
    child = child[1]
  end
  if not child then
    return mentions
  end

  local trees = child:trees()
  if not trees then
    return mentions
  end

  for _, tree in ipairs(trees) do
    local root = tree:root()

    local function traverse(node)
      if node:type() == "mention" then
        local mention_text = get_child_text(node, "mention_text", bufnr)
        if mention_text then
          local start_row = node:range()
          table.insert(mentions, {
            name = mention_text,
            line_number = start_row + 1,
          })
        end
      end

      for child_node in node:iter_children() do
        traverse(child_node)
      end
    end

    traverse(root)
  end

  return mentions
end

--- Extract hashtags from a buffer
---@param bufnr number
---@return table[] Array of {name: string, line_number: number}
function M.extract_hashtags(bufnr)
  local hashtags = {}

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  if not parser then
    return hashtags
  end

  local child = (parser:children() or {})["markdown_notes"]
  if not child then
    return hashtags
  end

  local ok = pcall(function() return child:trees() end)
  if not ok then
    child = child[1]
  end
  if not child then
    return hashtags
  end

  local trees = child:trees()
  if not trees then
    return hashtags
  end

  for _, tree in ipairs(trees) do
    local root = tree:root()

    local function traverse(node)
      if node:type() == "hashtag" then
        local tag_text = get_child_text(node, "hashtag_text", bufnr)
        if tag_text then
          local start_row = node:range()
          table.insert(hashtags, {
            name = tag_text,
            line_number = start_row + 1,
          })
        end
      end

      for child_node in node:iter_children() do
        traverse(child_node)
      end
    end

    traverse(root)
  end

  return hashtags
end

--- Extract all entities from a buffer
---@param bufnr number
---@return table {wikilinks: table[], mentions: table[], hashtags: table[]}
function M.extract_all(bufnr)
  return {
    wikilinks = M.extract_wikilinks(bufnr),
    mentions = M.extract_mentions(bufnr),
    hashtags = M.extract_hashtags(bufnr),
  }
end

--- Extract all entities from a file (loads file into temp buffer)
---@param filepath string
---@return table {wikilinks: table[], mentions: table[], hashtags: table[], title: string, content: string}
function M.extract_from_file(filepath)
  -- Check if file is already in a buffer
  local existing_buf = vim.fn.bufnr(filepath)
  if existing_buf ~= -1 and vim.api.nvim_buf_is_loaded(existing_buf) then
    local content = table.concat(vim.api.nvim_buf_get_lines(existing_buf, 0, -1, false), "\n")
    local lines = vim.api.nvim_buf_get_lines(existing_buf, 0, 1, false)
    local title = lines[1] or vim.fn.fnamemodify(filepath, ":t:r")
    -- Clean title (remove markdown heading prefix)
    title = title:gsub("^#+ ", "")

    local entities = M.extract_all(existing_buf)
    entities.title = title
    entities.content = content
    return entities
  end

  -- Load file into a scratch buffer
  local lines = vim.fn.readfile(filepath)
  if not lines or #lines == 0 then
    return {
      wikilinks = {},
      mentions = {},
      hashtags = {},
      title = vim.fn.fnamemodify(filepath, ":t:r"),
      content = "",
    }
  end

  local content = table.concat(lines, "\n")
  local title = lines[1] or vim.fn.fnamemodify(filepath, ":t:r")
  title = title:gsub("^#+ ", "")

  -- Create a temporary buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Force treesitter parse and wait for injections
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if ok and parser then
    -- Parse multiple times to ensure injections are created
    -- First parse creates the tree, subsequent parses activate injections
    for _ = 1, 3 do
      parser:parse(true)
    end

    -- Check if markdown_notes injection is available
    local children = parser:children() or {}
    if not children["markdown_notes"] then
      -- Try to manually register the injection region if needed
      -- This handles cases where the injection wasn't automatically detected
      parser:parse(true)
    end
  end

  local entities = M.extract_all(buf)
  entities.title = title
  entities.content = content

  -- Clean up temp buffer
  vim.api.nvim_buf_delete(buf, { force = true })

  return entities
end

--- Setup the extractor module
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
  M.opts = opts
end

return M
