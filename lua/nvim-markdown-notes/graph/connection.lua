--- Graph connection module
--- Manages the Python bridge process lifecycle for Memgraph communication
local M = {}

local installer = require("nvim-markdown-notes.graph.installer")

---@type MarkdownNotesFullOpts | nil
M.opts = nil

---@type number | nil
local job_id = nil

---@type boolean
local is_connected = false

---@type table<number, function>
local pending_callbacks = {}

---@type number
local callback_counter = 0

---@type string
local response_buffer = ""

--- Parse a JSON response from the bridge
---@param line string
---@return table | nil
local function parse_response(line)
  local ok, result = pcall(vim.json.decode, line)
  if ok then
    return result
  end
  return nil
end

--- Send a request to the bridge
---@param action string
---@param params table | nil
---@param callback function | nil
local function send_request(action, params, callback)
  if not job_id then
    if callback then
      callback(false, nil, "Bridge not started")
    end
    return
  end

  local request = vim.json.encode({
    action = action,
    params = params or {}
  })

  if callback then
    callback_counter = callback_counter + 1
    pending_callbacks[callback_counter] = callback
  end

  vim.fn.chansend(job_id, request .. "\n")
end

--- Handle stdout from the bridge process
---@param data string[]
local function on_stdout(_, data, _)
  for _, line in ipairs(data) do
    if line and line ~= "" then
      -- Accumulate partial responses
      response_buffer = response_buffer .. line

      -- Try to parse complete JSON
      local response = parse_response(response_buffer)
      if response then
        response_buffer = ""

        -- Find and execute the oldest pending callback
        local oldest_key = nil
        for key, _ in pairs(pending_callbacks) do
          if oldest_key == nil or key < oldest_key then
            oldest_key = key
          end
        end

        if oldest_key and pending_callbacks[oldest_key] then
          local cb = pending_callbacks[oldest_key]
          pending_callbacks[oldest_key] = nil
          cb(response.success, response.data, response.error)
        end

        -- Update connection state based on certain responses
        -- Check type to handle vim.NIL (userdata) properly
        if type(response.data) == "table" then
          if response.data.status == "healthy" then
            is_connected = true
          elseif response.data.message and type(response.data.message) == "string" and response.data.message:match("^Connected") then
            is_connected = true
          end
        end
      end
    end
  end
end

--- Handle stderr from the bridge process
---@param data string[]
local function on_stderr(_, data, _)
  for _, line in ipairs(data) do
    if line and line ~= "" then
      if M.opts and M.opts.debug_logging then
        vim.notify("[Memgraph Bridge] " .. line, vim.log.levels.WARN)
      end
    end
  end
end

--- Handle bridge process exit
---@param exit_code number
local function on_exit(_, exit_code, _)
  job_id = nil
  is_connected = false

  -- Fail all pending callbacks
  for key, cb in pairs(pending_callbacks) do
    cb(false, nil, "Bridge process exited with code " .. exit_code)
    pending_callbacks[key] = nil
  end

  if M.opts and M.opts.debug_logging then
    vim.notify("[Memgraph] Bridge process exited with code " .. exit_code, vim.log.levels.INFO)
  end
end

--- Check if the standalone CLI is available
---@return boolean
local function has_cli()
  return vim.fn.executable("nvim-markdown-notes-memgraph") == 1
end

--- Ensure services are running before connecting
--- Starts the services via CLI if available, otherwise skips
---@param callback function | nil Called with (success, message, error)
function M.ensure_services(callback)
  -- Check if CLI is installed
  if not has_cli() then
    if M.opts and M.opts.debug_logging then
      vim.notify("[Memgraph] CLI not installed, skipping service startup", vim.log.levels.DEBUG)
    end
    -- Skip silently - user needs to install CLI or manage services manually
    if callback then
      callback(true, "CLI not available, skipping service check", nil)
    end
    return
  end

  if M.opts and M.opts.debug_logging then
    vim.notify("[Memgraph] Starting services via CLI...", vim.log.levels.INFO)
  end

  -- Start services using the CLI
  vim.fn.jobstart(
    { "nvim-markdown-notes-memgraph", "start" },
    {
      on_exit = function(_, exit_code, _)
        if exit_code == 0 then
          if M.opts and M.opts.debug_logging then
            vim.notify("[Memgraph] Services started successfully", vim.log.levels.INFO)
          end
          if callback then
            callback(true, "Services started", nil)
          end
        else
          local err_msg = "Failed to start services (exit code: " .. exit_code .. ")"
          if M.opts and M.opts.debug_logging then
            vim.notify("[Memgraph] " .. err_msg, vim.log.levels.WARN)
          end
          if callback then
            callback(false, nil, err_msg)
          end
        end
      end,
      stdout_buffered = true,
      stderr_buffered = true,
    }
  )
end

--- Start the Python bridge process
---@param callback function | nil Called with (success, message)
function M.start(callback)
  if job_id then
    if callback then
      callback(true, "Bridge already running")
    end
    return
  end

  if not M.opts then
    if callback then
      callback(false, "Graph module not configured")
    end
    return
  end

  local cmd

  -- Check if standalone CLI is available
  if not has_cli() then
    if callback then
      callback(false, "nvim-markdown-notes-memgraph CLI not found. Install with: pip install nvim-markdown-notes-memgraph")
    end
    return
  end

  cmd = { "nvim-markdown-notes-memgraph", "bridge" }

  if M.opts and M.opts.debug_logging then
    vim.notify("[Memgraph] Using nvim-markdown-notes-memgraph CLI", vim.log.levels.INFO)
  end

  job_id = vim.fn.jobstart(cmd, {
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
    stdout_buffered = false,
    stderr_buffered = false,
  })

  if job_id <= 0 then
    job_id = nil
    if callback then
      callback(false, "Failed to start bridge process")
    end
    return
  end

  -- Connect to Memgraph
  vim.defer_fn(function()
    M.connect(callback)
  end, 100)
end

--- Stop the Python bridge process
function M.stop()
  if job_id then
    send_request("quit", {}, nil)
    vim.fn.jobstop(job_id)
    job_id = nil
    is_connected = false
  end
end

--- Connect to Memgraph database
---@param callback function | nil Called with (success, data, error)
function M.connect(callback)
  if not M.opts then
    if callback then
      callback(false, nil, "Graph module not configured")
    end
    return
  end

  send_request("connect", {
    host = M.opts.memgraph.host,
    port = M.opts.memgraph.port
  }, function(success, data, err)
    is_connected = success
    if callback then
      callback(success, data, err)
    end
  end)
end

--- Check if connected to Memgraph
---@return boolean
function M.is_connected()
  return is_connected and job_id ~= nil
end

--- Perform a health check
---@param callback function Called with (success, data, error)
function M.health_check(callback)
  send_request("health_check", {}, function(success, data, err)
    is_connected = success
    if callback then
      callback(success, data, err)
    end
  end)
end

--- Get graph statistics
---@param callback function Called with (success, data, error)
function M.get_stats(callback)
  send_request("stats", {}, callback)
end

--- Execute a raw request
---@param action string
---@param params table
---@param callback function Called with (success, data, error)
function M.request(action, params, callback)
  send_request(action, params, callback)
end

--- Ensure connection is alive, reconnect if needed
---@param callback function Called with (success, message)
function M.ensure_connected(callback)
  if M.is_connected() then
    M.health_check(function(success, _, err)
      if success then
        if callback then
          callback(true, nil, nil)
        end
      else
        -- Try to reconnect
        M.connect(function(s, _, e)
          if callback then
            local error_msg = (type(e) == "string") and e or nil
            callback(s, nil, error_msg)
          end
        end)
      end
    end)
  else
    M.start(callback)
  end
end

--- Setup the connection module
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
  M.opts = opts

  -- Auto-start if enabled
  if opts.memgraph.enabled then
    -- Defer to allow other modules to load
    vim.defer_fn(function()
      -- First try to install CLI if missing
      installer.ensure_cli(opts.memgraph, function(_)
        -- Then ensure services are running (if CLI is available)
        M.ensure_services(function(service_success, service_msg, service_err)
        if not service_success and service_err then
          -- Service startup failed - log warning but continue with connection attempt
          if opts.debug_logging then
            vim.notify("[Memgraph] " .. (service_err or "Service startup error"), vim.log.levels.WARN)
          end
        end

        -- Now start the bridge and connect
        M.start(function(success, data, err)
          if success then
            if opts.debug_logging then
              local msg = "Connected"
              if type(data) == "table" and type(data.message) == "string" then
                msg = data.message
              end
              vim.notify("[Memgraph] " .. msg, vim.log.levels.INFO)
            end
          else
            local error_msg = "unknown error"
            if type(err) == "string" then
              error_msg = err
            elseif type(data) == "string" then
              error_msg = data
            end

            -- Check for common errors and provide helpful messages
            if error_msg:match("mgclient not installed") then
              vim.notify(
                "[Memgraph] Python client not installed.\n" ..
                "Install with: pip install pymgclient\n" ..
                "Graph features will be disabled until installed.",
                vim.log.levels.WARN
              )
            elseif error_msg:match("Failed to connect") or error_msg:match("Connection refused") then
              vim.notify(
                "[Memgraph] Could not connect to database.\n" ..
                "Start Memgraph with: docker run -p 7687:7687 memgraph/memgraph\n" ..
                "Or install CLI with: pip install nvim-markdown-notes-memgraph\n" ..
                "Graph features will be disabled until connected.",
                vim.log.levels.WARN
              )
            else
              vim.notify("[Memgraph] Connection failed: " .. error_msg, vim.log.levels.WARN)
            end
          end
        end)
      end)
      end)
    end, 500)
  end
end

return M
