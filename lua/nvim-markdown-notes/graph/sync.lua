--- Graph sync module
--- Handles syncing notes to Memgraph database
local M = {}

---@type MarkdownNotesFullOpts | nil
M.opts = nil

---@type table<string, number> Debounce timers by filepath
local debounce_timers = {}

--- Safely convert error to string
---@param err any
---@return string
local function error_to_string(err)
  if err == nil or err == vim.NIL then
    return "unknown"
  end
  if type(err) == "string" then
    return err
  end
  return tostring(err)
end

--- Get the connection module
local function get_connection()
  return require("nvim-markdown-notes.graph.connection")
end

--- Get the extractor module
local function get_extractor()
  return require("nvim-markdown-notes.graph.extractor")
end

--- Update a single note in the graph
---@param filepath string Absolute path to the note file
---@param callback function | nil Called with (success, data, error)
function M.update_note(filepath, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    if callback then
      callback(false, nil, "Not connected to Memgraph")
    end
    return
  end

  -- Cancel any pending debounce for this file
  if debounce_timers[filepath] then
    vim.fn.timer_stop(debounce_timers[filepath])
    debounce_timers[filepath] = nil
  end

  -- Debounce the sync
  local debounce_ms = M.opts and M.opts.memgraph.sync_debounce or 500

  debounce_timers[filepath] = vim.fn.timer_start(debounce_ms, function()
    debounce_timers[filepath] = nil

    vim.schedule(function()
      -- Extract entities from the file
      local extractor = get_extractor()
      local entities = extractor.extract_from_file(filepath)

      -- Send update request to bridge
      connection.request("update_note", {
        path = filepath,
        title = entities.title,
        content = entities.content,
        wikilinks = entities.wikilinks,
        mentions = entities.mentions,
        hashtags = entities.hashtags,
      }, function(success, data, err)
        if callback then
          callback(success, data, err)
        elseif M.opts and M.opts.debug_logging then
          if success then
            vim.notify("[Memgraph] Synced: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.DEBUG)
          else
            vim.notify("[Memgraph] Sync failed: " .. error_to_string(err), vim.log.levels.WARN)
          end
        end
      end)
    end)
  end)
end

--- Update the current buffer immediately (no debounce)
---@param callback function | nil Called with (success, data, error)
function M.update_current(callback)
  local connection = get_connection()

  if not connection.is_connected() then
    if callback then
      callback(false, nil, "Not connected to Memgraph")
    end
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  if filepath == "" then
    if callback then
      callback(false, nil, "Buffer has no file")
    end
    return
  end

  -- Extract entities from current buffer
  local extractor = get_extractor()
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
  local title = (lines[1] or vim.fn.fnamemodify(filepath, ":t:r")):gsub("^#+ ", "")

  local entities = extractor.extract_all(bufnr)

  -- Send update request to bridge
  connection.request("update_note", {
    path = filepath,
    title = title,
    content = content,
    wikilinks = entities.wikilinks,
    mentions = entities.mentions,
    hashtags = entities.hashtags,
  }, callback)
end

--- Delete a note from the graph
---@param filepath string Absolute path to the note file
---@param callback function | nil Called with (success, data, error)
function M.delete_note(filepath, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    if callback then
      callback(false, nil, "Not connected to Memgraph")
    end
    return
  end

  -- Cancel any pending debounce for this file
  if debounce_timers[filepath] then
    vim.fn.timer_stop(debounce_timers[filepath])
    debounce_timers[filepath] = nil
  end

  connection.request("delete_note", {
    path = filepath,
  }, callback)
end

--- Reindex all notes in the notes directory
---@param callback function | nil Called with (success, data, error)
function M.reindex_all(callback)
  local connection = get_connection()

  if not connection.is_connected() then
    if callback then
      callback(false, nil, "Not connected to Memgraph")
    end
    return
  end

  if not M.opts then
    if callback then
      callback(false, nil, "Graph module not configured")
    end
    return
  end

  vim.notify("[Memgraph] Starting full reindex...", vim.log.levels.INFO)

  -- Find all markdown files
  local files = vim.fn.glob(M.opts.notes_root_path .. "/**/*.md", false, true)
  local extractor = get_extractor()
  local notes = {}

  -- Extract entities from each file
  for _, filepath in ipairs(files) do
    local entities = extractor.extract_from_file(filepath)
    table.insert(notes, {
      path = filepath,
      title = entities.title,
      content = entities.content,
      wikilinks = entities.wikilinks,
      mentions = entities.mentions,
      hashtags = entities.hashtags,
    })
  end

  vim.notify("[Memgraph] Extracted " .. #notes .. " notes, sending to graph...", vim.log.levels.INFO)

  -- Send reindex request
  connection.request("reindex", {
    notes = notes,
  }, function(success, data, err)
    if success then
      local indexed = data and data.indexed or 0
      vim.notify("[Memgraph] Reindex complete: " .. indexed .. " notes indexed", vim.log.levels.INFO)
    else
      vim.notify("[Memgraph] Reindex failed: " .. error_to_string(err), vim.log.levels.ERROR)
    end

    if callback then
      callback(success, data, err)
    end
  end)
end

--- Setup the sync module
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
  M.opts = opts
end

return M
