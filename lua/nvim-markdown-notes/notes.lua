local M = {}

-- Create a new note with title input, formatted as "YYYY-MM-dd title.md"
M.create_note = function(notes_root_path)
	assert(notes_root_path, "notes_root_path must be configured")

	local title = vim.fn.input("Note title: ")
	if title == "" then
		print("Note creation cancelled")
		return
	end

	local today = vim.fn.strftime("%Y-%m-%d")
	local note_filename = today .. " " .. title .. ".md"
	local note_filepath = vim.fn.expand(vim.fn.resolve(notes_root_path .. "/" .. note_filename))

	if type(note_filepath) == "string" then
		if vim.fn.filereadable(note_filepath) == 1 then
			print("Note already exists: " .. note_filename)
			vim.cmd("e " .. vim.fn.fnameescape(note_filepath))
		else
			local header = "# " .. title
			os.execute('echo "' .. header .. '" > "' .. note_filepath .. '"')
			vim.cmd("e " .. vim.fn.fnameescape(note_filepath))
			print("Created note: " .. note_filename)
		end
	end
end

return M
