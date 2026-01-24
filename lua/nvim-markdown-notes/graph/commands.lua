--- Graph commands module
--- User commands and Telescope pickers for graph operations
local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

---@type MarkdownNotesFullOpts | nil
M.opts = nil

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

--- Get the sync module
local function get_sync()
  return require("nvim-markdown-notes.graph.sync")
end

--- Get the query module
local function get_query()
  return require("nvim-markdown-notes.graph.query")
end

--- Check connection and notify if not connected
---@return boolean
local function check_connection()
  local connection = get_connection()
  if not connection.is_connected() then
    vim.notify("[Memgraph] Not connected to graph database", vim.log.levels.WARN)
    return false
  end
  return true
end

--- Show graph connection status and statistics
function M.show_status()
  local connection = get_connection()

  if not connection.is_connected() then
    vim.notify("[Memgraph] Status: Not connected", vim.log.levels.INFO)
    return
  end

  connection.get_stats(function(success, data, err)
    if success and data then
      local lines = {
        "[Memgraph] Status: Connected",
        "",
        "Graph Statistics:",
        string.format("  Notes:    %d", data.notes or 0),
        string.format("  Persons:  %d", data.persons or 0),
        string.format("  Tags:     %d", data.tags or 0),
        "",
        "Relationships:",
        string.format("  Links:    %d", data.links or 0),
        string.format("  Mentions: %d", data.mentions or 0),
        string.format("  Tag uses: %d", data.tag_usages or 0),
      }
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    else
      vim.notify("[Memgraph] Status: Connected (failed to get stats: " .. error_to_string(err) .. ")", vim.log.levels.WARN)
    end
  end)
end

--- Sync current buffer to graph
function M.sync_current()
  if not check_connection() then
    return
  end

  local sync = get_sync()
  sync.update_current(function(success, data, err)
    if success then
      local msg = "[Memgraph] Synced current buffer"
      if data then
        msg = msg .. string.format(" (links: %d, mentions: %d, tags: %d)",
          data.wikilinks_count or 0,
          data.mentions_count or 0,
          data.hashtags_count or 0)
      end
      vim.notify(msg, vim.log.levels.INFO)
    else
      vim.notify("[Memgraph] Sync failed: " .. error_to_string(err), vim.log.levels.ERROR)
    end
  end)
end

--- Reindex all notes
function M.reindex()
  if not check_connection() then
    return
  end

  local sync = get_sync()
  sync.reindex_all()
end

--- Create entry maker for note results
---@param entry table Note entry with path, title, line_number
---@return table Telescope entry
local function make_note_entry(entry)
  local display = entry.title or vim.fn.fnamemodify(entry.path, ":t:r")
  if entry.line_number then
    display = display .. ":" .. entry.line_number
  end
  if entry.shared_count then
    display = display .. " (" .. entry.shared_count .. " shared)"
  end

  return {
    value = entry,
    display = display,
    ordinal = (entry.title or "") .. " " .. (entry.path or ""),
    filename = entry.path,
    lnum = entry.line_number,
  }
end

--- Open Telescope picker for backlinks to current note
function M.show_backlinks()
  if not check_connection() then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("[Memgraph] Current buffer has no file", vim.log.levels.WARN)
    return
  end

  local query = get_query()
  query.find_backlinks(filepath, function(success, results, err)
    if not success then
      vim.notify("[Memgraph] Query failed: " .. error_to_string(err), vim.log.levels.ERROR)
      return
    end

    if #results == 0 then
      vim.notify("[Memgraph] No backlinks found", vim.log.levels.INFO)
      return
    end

    vim.schedule(function()
      pickers.new({}, {
        prompt_title = "Backlinks",
        finder = finders.new_table({
          results = results,
          entry_maker = make_note_entry,
        }),
        previewer = conf.grep_previewer({}),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection.filename then
              local cmd = "edit " .. vim.fn.fnameescape(selection.filename)
              if selection.lnum then
                cmd = "edit +" .. selection.lnum .. " " .. vim.fn.fnameescape(selection.filename)
              end
              vim.cmd(cmd)
            end
          end)
          return true
        end,
      }):find()
    end)
  end)
end

--- Open Telescope picker for related notes
function M.show_related()
  if not check_connection() then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("[Memgraph] Current buffer has no file", vim.log.levels.WARN)
    return
  end

  local query = get_query()
  query.find_related(filepath, function(success, results, err)
    if not success then
      vim.notify("[Memgraph] Query failed: " .. error_to_string(err), vim.log.levels.ERROR)
      return
    end

    if #results == 0 then
      vim.notify("[Memgraph] No related notes found", vim.log.levels.INFO)
      return
    end

    vim.schedule(function()
      pickers.new({}, {
        prompt_title = "Related Notes",
        finder = finders.new_table({
          results = results,
          entry_maker = make_note_entry,
        }),
        previewer = conf.grep_previewer({}),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection.filename then
              vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
            end
          end)
          return true
        end,
      }):find()
    end)
  end)
end

--- Open Telescope picker for notes with a specific tag
---@param tag string Tag to search for (without #)
function M.show_tagged(tag)
  if not check_connection() then
    return
  end

  -- Remove # prefix if present
  tag = tag:gsub("^#", "")

  local query = get_query()
  query.find_by_tag(tag, function(success, results, err)
    if not success then
      vim.notify("[Memgraph] Query failed: " .. error_to_string(err), vim.log.levels.ERROR)
      return
    end

    if #results == 0 then
      vim.notify("[Memgraph] No notes found with tag: #" .. tag, vim.log.levels.INFO)
      return
    end

    vim.schedule(function()
      pickers.new({}, {
        prompt_title = "Notes with #" .. tag,
        finder = finders.new_table({
          results = results,
          entry_maker = make_note_entry,
        }),
        previewer = conf.grep_previewer({}),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection.filename then
              local cmd = "edit " .. vim.fn.fnameescape(selection.filename)
              if selection.lnum then
                cmd = "edit +" .. selection.lnum .. " " .. vim.fn.fnameescape(selection.filename)
              end
              vim.cmd(cmd)
            end
          end)
          return true
        end,
      }):find()
    end)
  end)
end

--- Open Telescope picker for notes mentioning a person
---@param person string Person to search for (without @)
function M.show_mentions(person)
  if not check_connection() then
    return
  end

  -- Remove @ prefix if present
  person = person:gsub("^@", "")

  local query = get_query()
  query.find_by_mention(person, function(success, results, err)
    if not success then
      vim.notify("[Memgraph] Query failed: " .. error_to_string(err), vim.log.levels.ERROR)
      return
    end

    if #results == 0 then
      vim.notify("[Memgraph] No notes found mentioning: @" .. person, vim.log.levels.INFO)
      return
    end

    vim.schedule(function()
      pickers.new({}, {
        prompt_title = "Notes mentioning @" .. person,
        finder = finders.new_table({
          results = results,
          entry_maker = make_note_entry,
        }),
        previewer = conf.grep_previewer({}),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection.filename then
              local cmd = "edit " .. vim.fn.fnameescape(selection.filename)
              if selection.lnum then
                cmd = "edit +" .. selection.lnum .. " " .. vim.fn.fnameescape(selection.filename)
              end
              vim.cmd(cmd)
            end
          end)
          return true
        end,
      }):find()
    end)
  end)
end

--- Show note context (all relationships)
function M.show_context()
  if not check_connection() then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("[Memgraph] Current buffer has no file", vim.log.levels.WARN)
    return
  end

  local query = get_query()
  query.get_note_context(filepath, function(success, context, err)
    if not success then
      vim.notify("[Memgraph] Query failed: " .. error_to_string(err), vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      local lines = {
        "Note: " .. (context.title or vim.fn.fnamemodify(filepath, ":t:r")),
        "",
      }

      if #context.tags > 0 then
        table.insert(lines, "Tags:")
        for _, tag in ipairs(context.tags) do
          table.insert(lines, "  #" .. tag)
        end
        table.insert(lines, "")
      end

      if #context.mentions > 0 then
        table.insert(lines, "Mentions:")
        for _, person in ipairs(context.mentions) do
          table.insert(lines, "  @" .. person)
        end
        table.insert(lines, "")
      end

      if #context.outgoing_links > 0 then
        table.insert(lines, "Links to:")
        for _, link in ipairs(context.outgoing_links) do
          table.insert(lines, "  -> " .. (link.title or link.path))
        end
        table.insert(lines, "")
      end

      if #context.backlinks > 0 then
        table.insert(lines, "Linked from:")
        for _, link in ipairs(context.backlinks) do
          table.insert(lines, "  <- " .. (link.title or link.path))
        end
      end

      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end)
  end)
end

--- Register user commands
function M.register_commands()
  vim.api.nvim_create_user_command("MarkdownNotesGraphStatus", function()
    M.show_status()
  end, { desc = "Show Memgraph connection status and stats" })

  vim.api.nvim_create_user_command("MarkdownNotesGraphSync", function()
    M.sync_current()
  end, { desc = "Sync current buffer to graph" })

  vim.api.nvim_create_user_command("MarkdownNotesGraphReindex", function()
    M.reindex()
  end, { desc = "Rebuild entire graph from all notes" })

  vim.api.nvim_create_user_command("MarkdownNotesGraphBacklinks", function()
    M.show_backlinks()
  end, { desc = "Show notes linking to current note" })

  vim.api.nvim_create_user_command("MarkdownNotesGraphRelated", function()
    M.show_related()
  end, { desc = "Show notes related to current note" })

  vim.api.nvim_create_user_command("MarkdownNotesGraphTagged", function(opts)
    if opts.args and opts.args ~= "" then
      M.show_tagged(opts.args)
    else
      vim.notify("Usage: :MarkdownNotesGraphTagged <tag>", vim.log.levels.WARN)
    end
  end, {
    nargs = "?",
    desc = "Show notes with a specific tag",
    complete = function()
      -- Could add tag completion here
      return {}
    end,
  })

  vim.api.nvim_create_user_command("MarkdownNotesGraphMentions", function(opts)
    if opts.args and opts.args ~= "" then
      M.show_mentions(opts.args)
    else
      vim.notify("Usage: :MarkdownNotesGraphMentions <person>", vim.log.levels.WARN)
    end
  end, {
    nargs = "?",
    desc = "Show notes mentioning a person",
  })

  vim.api.nvim_create_user_command("MarkdownNotesGraphContext", function()
    M.show_context()
  end, { desc = "Show all relationships for current note" })

  vim.api.nvim_create_user_command("MarkdownNotesGraphConnect", function()
    local connection = get_connection()
    connection.ensure_connected(function(success, data, err)
      if success then
        local msg = (data and type(data) == "table" and data.message) or "Connected"
        vim.notify("[Memgraph] " .. msg, vim.log.levels.INFO)
      else
        local error_msg = (type(err) == "string" and err) or "unknown error"
        vim.notify("[Memgraph] Connection failed: " .. error_msg, vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Connect/reconnect to Memgraph" })
end

--- Setup the commands module
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
  M.opts = opts
  M.register_commands()
end

return M
