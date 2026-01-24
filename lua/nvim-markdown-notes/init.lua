local M = {}

local custom_parser = require("nvim-markdown-notes.treesitter_grammar")
local nvim_cmp_source = require("nvim-markdown-notes.cmp_wikilinks_completion_source")
local tags = require("nvim-markdown-notes.tags")
local journal = require("nvim-markdown-notes.journal")
local notes = require("nvim-markdown-notes.notes")
local wikilink = require("nvim-markdown-notes.wikilink")
local mentions = require("nvim-markdown-notes.mentions")
local weblink = require("nvim-markdown-notes.weblink")
local graph = require("nvim-markdown-notes.graph")

-- export functions from modules
M.list_all_tags = tags.list_all_tags
M.view_files_with_tag = tags.find_tag
M.open_daily_journal = journal.open_daily_journal
M.open_journal = journal.open_journal
M.create_note = notes.create_top_level_note
M.register_wikilink_cmp_source = nvim_cmp_source.register_cmp_source

-- export graph module
M.graph = graph

-- ===========================================
-- GRAPH-POWERED NAVIGATION (when memgraph enabled)
-- These are the PRIMARY search/navigation methods.
-- Use these BEFORE resorting to full-text search.
-- ===========================================

--- Browse all tags via graph (PRIMARY NAVIGATION)
--- Use this for topic-based searching - more efficient than full-text
M.graph_browse_tags = function()
  graph.browse_tags()
end

--- Browse all people via graph (PRIMARY NAVIGATION)
--- Use this for person-related searching - more efficient than full-text
M.graph_browse_people = function()
  graph.browse_people()
end

--- Find notes by tag via graph (PRIMARY SEARCH)
---@param tag string Tag name (with or without #)
M.graph_find_by_tag = function(tag)
  graph.find_by_tag(tag)
end

--- Find notes mentioning a person via graph (PRIMARY SEARCH)
---@param person string Person name (with or without @)
M.graph_find_by_mention = function(person)
  graph.find_by_mention(person)
end

--- Show backlinks to current note
M.graph_backlinks = function()
  graph.show_backlinks()
end

--- Show notes related to current note (shared tags/mentions)
M.graph_related = function()
  graph.show_related()
end

--- Reindex all notes into the graph
M.graph_reindex = function()
  graph.reindex()
end

--- custom jump-to-definition for my notes
M.custom_jump_to_tag = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1

	local node = custom_parser.get_markdown_notes_node(bufnr, row, col, "markdown_notes")
	if not node then
		node = custom_parser.get_markdown_notes_node(bufnr, row, col, "markdown_inline")
	end

	if not node then
		return nil
	end

	local node_type = node:type()
	if tags.is_match(node_type) then
		tags.jump(node)
	elseif wikilink.is_match(node_type) then
		wikilink.jump(node)
	elseif mentions.is_match(node_type) then
		mentions.jump(node)
	elseif weblink.is_match(node_type) then
		weblink.jump(node)
	end
end

-- Setup the extension: use user configuration & set up commands
---@param opts MarkdownNotesOpts
M.setup = function(opts)
	local options = require("nvim-markdown-notes.options").configure_options(opts)
	notes.setup(options)
	tags.setup(options)
	journal.setup(options)
	wikilink.setup(options)
	mentions.setup(options)
	weblink.setup(options)
	custom_parser.setup(options)
	graph.setup(options)

	-- Set up highlight groups for markdown_notes treesitter captures
	for group, settings in pairs(options.highlights) do
		vim.api.nvim_set_hl(0, group, settings)
	end

	-- Set up autocommands for markdown files
	vim.api.nvim_create_augroup("MarkdownNotes", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = "MarkdownNotes",
		pattern = "markdown",
		callback = function()
			-- Map gf and Ctrl-] to follow_link function
			vim.keymap.set("n", "<C-]>", M.custom_jump_to_tag, { buffer = true, desc = "Follow note link" })
		end,
	})

	-- Auto-sync to graph on save if enabled
	if options.memgraph.enabled and options.memgraph.auto_sync then
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = "MarkdownNotes",
			pattern = "*.md",
			callback = function(args)
				-- Only sync files within notes_root_path
				local filepath = args.file
				if filepath and filepath:find(options.notes_root_path, 1, true) then
					graph.get_sync().update_note(filepath)
				end
			end,
		})
	end
end

return M
