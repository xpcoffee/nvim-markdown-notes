--- CLI installer module
--- Detects missing CLI and prompts the user to install it automatically
local M = {}

---@type boolean
local user_declined = false

--- Find the best available install command
---@return string[]|nil command args, or nil if no installer found
local function find_install_command(install_source)
  if vim.fn.executable("uv") == 1 then
    return { "uv", "tool", "install", install_source }
  elseif vim.fn.executable("pip3") == 1 then
    return { "pip3", "install", install_source }
  elseif vim.fn.executable("pip") == 1 then
    return { "pip", "install", install_source }
  end
  return nil
end

--- Format install command for display
---@param cmd string[]
---@return string
local function format_cmd(cmd)
  return table.concat(cmd, " ")
end

--- Run the install command asynchronously
---@param cmd string[]
---@param callback function Called with (success: boolean)
local function run_install(cmd, callback)
  vim.notify("[Memgraph] Installing CLI via: " .. format_cmd(cmd), vim.log.levels.INFO)

  local stderr_lines = {}
  local stdout_lines = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data, _)
      if data then
        vim.list_extend(stdout_lines, data)
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        vim.list_extend(stderr_lines, data)
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code == 0 then
          vim.notify("[Memgraph] CLI installed successfully", vim.log.levels.INFO)
          callback(true)
        else
          local output = table.concat(stderr_lines, "\n")
          if output == "" then
            output = table.concat(stdout_lines, "\n")
          end
          local msg = "[Memgraph] CLI installation failed (exit code: " .. exit_code .. ")"
          if output ~= "" then
            msg = msg .. "\n" .. output
          end
          vim.notify(msg, vim.log.levels.ERROR)
          callback(false)
        end
      end)
    end,
  })
end

--- Ensure the CLI is available, prompting to install if missing
---@param opts MemgraphFullOpts
---@param callback function Called with (success: boolean)
function M.ensure_cli(opts, callback)
  -- Already on PATH
  if vim.fn.executable("nvim-markdown-notes-memgraph") == 1 then
    callback(true)
    return
  end

  -- User declined this session or prompting disabled
  if user_declined or not opts.install_prompt then
    callback(false)
    return
  end

  -- Need python3 for the CLI to work
  if vim.fn.executable("python3") ~= 1 then
    callback(false)
    return
  end

  -- Find an installer
  local cmd = find_install_command(opts.install_source)
  if not cmd then
    callback(false)
    return
  end

  -- Prompt user
  local prompt_msg = "Memgraph CLI not found. Install via `" .. format_cmd(cmd) .. "`?"
  vim.ui.select({ "Yes", "No" }, { prompt = prompt_msg }, function(choice)
    if choice == "Yes" then
      run_install(cmd, callback)
    else
      user_declined = true
      callback(false)
    end
  end)
end

--- Reset the session-declined flag (used by :MemgraphInstallCLI)
function M.reset_declined()
  user_declined = false
end

return M
