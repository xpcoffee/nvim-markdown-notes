local M = {}

local ROOT_NODE_NAME = "source_file"

-- Helper to get plugin root directory
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source:sub(2)
	local plugin_root = vim.fn.fnamemodify(source, ":h:h:h")
	return plugin_root
end

-- Check if parser exists
local function parser_exists()
	local parser_files = vim.api.nvim_get_runtime_file("parser/markdown_notes.so", false)
	if #parser_files > 0 then
		return true, parser_files[1]
	end

	parser_files = vim.api.nvim_get_runtime_file("parser/markdown_notes.dll", false)
	if #parser_files > 0 then
		return true, parser_files[1]
	end

	return false, nil
end

-- Build parser using make
local function build_parser(callback)
	local plugin_root = get_plugin_root()

	vim.notify("Building markdown_notes parser...", vim.log.levels.INFO)

	-- Run make in the plugin directory
	local cmd = string.format("cd %s && make", vim.fn.shellescape(plugin_root))

	vim.fn.jobstart(cmd, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.notify("Parser built successfully!", vim.log.levels.INFO)
				if callback then
					callback(true)
				end
			else
				vim.notify("Failed to build parser. Exit code: " .. exit_code, vim.log.levels.ERROR)
				if callback then
					callback(false)
				end
			end
		end,
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						print(line)
					end
				end
			end
		end,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						vim.notify(line, vim.log.levels.WARN)
					end
				end
			end
		end,
		stdout_buffered = true,
		stderr_buffered = true,
	})
end

-- Check dependencies
local function check_dependencies()
	-- Check if tree-sitter CLI is available
	vim.fn.system("which tree-sitter")
	if vim.v.shell_error ~= 0 then
		return false, "tree-sitter CLI not found. Install with: npm install -g tree-sitter-cli"
	end

	-- Check if make is available
	vim.fn.system("which make")
	if vim.v.shell_error ~= 0 then
		return false, "make not found. Please install build tools."
	end

	-- Check if compiler is available
	vim.fn.system("which cc")
	if vim.v.shell_error ~= 0 then
		return false, "C compiler (cc) not found. Please install a C compiler."
	end

	return true, nil
end

local register_parser = function(parser_path)
	pcall(vim.treesitter.language.add, "markdown_notes", { path = parser_path })

	vim.notify("MarkdownNotesBuildParser ready", vim.log.levels.INFO)
end

---Build (if necessary) and register the custom grammar with treesitter
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
	opts = opts or {}

	-- Default: auto-build if parser doesn't exist
	local auto_build = opts.auto_build
	if auto_build == nil then
		auto_build = true
	end

	-- Check if parser exists
	local exists, path = parser_exists()

	if not exists then
		if auto_build then
			-- Check dependencies first
			local deps_ok, deps_err = check_dependencies()

			if not deps_ok then
				vim.notify("Cannot auto-build parser: " .. deps_err, vim.log.levels.WARN)
				vim.notify("Run :WikilinkBuildParser after installing dependencies", vim.log.levels.INFO)
				return
			end

			-- Build automatically
			vim.notify("Parser not found. Building automatically...", vim.log.levels.INFO)
			build_parser(function(success)
				if success then
					register_parser(path)
				end
			end)
		else
			vim.notify(
				"markdown_notes parser not found. Run :MarkdownNotesBuildParser to build it.",
				vim.log.levels.WARN
			)
		end
	else
		register_parser(path)
	end

	-- Create user command to manually build parser
	vim.api.nvim_create_user_command("MarkdownNotesBuildParser", function()
		local deps_ok, deps_err = check_dependencies()
		if not deps_ok and deps_err then
			vim.notify(deps_err, vim.log.levels.ERROR)
			return
		end
		build_parser()
	end, {})

	-- Create user command to clean build artifacts
	vim.api.nvim_create_user_command("MarkdownNotesCleanParser", function()
		local plugin_root = get_plugin_root()
		local cmd = string.format("cd %s && make clean", vim.fn.shellescape(plugin_root))
		vim.fn.system(cmd)
		vim.notify("Parser cleaned", vim.log.levels.INFO)
	end, {})

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "markdown",
		callback = function(args)
			vim.schedule(function()
				local ok, parser = pcall(vim.treesitter.get_parser, args.buf, "markdown")
				if ok and parser then
					parser:parse(true) -- Force parse to trigger injection creation
				end
			end)
		end,
		desc = "Force treesitter parse to create language injections",
	})
end

---Return the custom node under the cursor
---@return TSNode | nil
M.get_markdown_notes_node = function(bufnr, row, col, custom_lang)
	-- Get the markdown parser
	local parser = vim.treesitter.get_parser(bufnr, "markdown")
	if not parser then
		return nil
	end

	if custom_lang then
		local child = (parser:children() or {})[custom_lang]
		if not child then
			return nil
		end
		-- children()[lang] may be a single LanguageTree or a list; normalize to a LanguageTree
		local ok = pcall(function()
			return child:trees()
		end)
		if not ok then
			child = child[1]
		end
		if not child then
			return nil
		end
		parser = child
	end

	-- Iterate through all trees to find the one containing the cursor
	local trees = parser:trees()
	if not trees or #trees == 0 then
		return nil
	end

	local node = nil
	for _, tree in ipairs(trees) do
		local root = tree:root()
		local tree_start_row, _, tree_end_row, _ = root:range()

		-- Check if this tree contains the cursor position (row only)
		if tree_start_row <= row and tree_end_row >= row then
			node = root:named_descendant_for_range(row, col, row, col)
			if node then
				break
			end
		end
	end

	if not node then
		return nil
	end

	-- For custom markdown_notes, normalize to top-level node; for inline, climb to nearest link node
	if not custom_lang or custom_lang == "markdown_notes" then
		while node and node:type() ~= ROOT_NODE_NAME do
			node = node:parent()
		end

		if node and node:type() == ROOT_NODE_NAME then
			for child in node:iter_children() do
				local child_start_row, child_start_col, child_end_row, child_end_col = child:range()
				if
					(child_start_row <= row and child_end_row >= row)
					and (child_start_col <= col and child_end_col >= col)
				then
					node = child
					break
				end
			end
		end
	else
		local n = node
		while n and (n:type() ~= "link_text" and n:type() ~= "link_destination" and n:type() ~= "link") do
			n = n:parent()
		end
		if n then
			node = n
		end
	end

	return node
end

M.get_nodes_by_type = function(bufnr, node_type)
	local parser = vim.treesitter.get_parser(bufnr, "markdown")
	if not parser then
		return nil
	end
	local tree = parser:parse()[1]
	local root = tree:root()

	local query = vim.treesitter.query.parse(parser:lang(), string.format("(%s) @node", node_type))

	local nodes = {}
	for _, node in query:iter_captures(root, bufnr) do
		table.insert(nodes, node)
	end
	return nodes
end

return M
