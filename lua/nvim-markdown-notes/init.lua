local M = {}

local tags = require("nvim-markdown-notes.tags")
M.list_all_tags = function()
	tags.list_all_tags(M.notes_root_path)
end
M.view_files_with_tag = function(tag)
	tags.find_tag(M.notes_root_path, tag)
end

local journal = require("nvim-markdown-notes.journal")
M.open_daily_journal = function()
	journal.open_daily_journal(M.notes_root_path, M.journal_dir_name)
end
M.open_journal = function()
	journal.open_journal(M.notes_root_path, M.journal_dir_name)
end

local notes = require("nvim-markdown-notes.notes")
M.create_note = function()
	notes.create_note(M.notes_root_path)
end

local wikilink = require("nvim-markdown-notes.wikilink")

M.custom_jump_to_tag = function()
	local word = vim.fn.expand("<cWORD>")
	local jumped = tags.find_tag(M.notes_root_path, word)
	if jumped then
		return
	end

	jumped = wikilink.wiki_link_jump(M.notes_root_path)
end

M.register_wikilink_cmp_source = require("nvim-markdown-notes.cmp_wikilinks_completion_source").register_cmp_source

-- Setup the extension: use user configuration & set up commands
M.setup = function(opts)
	M.notes_root_path = vim.fn.expand(opts.notes_root_path):gsub("/$", "")
	M.journal_dir_name = opts.journal_dir_name

	local custom_parser = require("nvim-markdown-notes.treesitter_grammar")
	custom_parser.setup(opts)

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
end

return M
