# nvim-markdown-notes

A Neovim plugin for managing Markdown notes and journals, inspired by tools like Obsidian. Features seamless tag searching, backlink navigation, and daily journal creation—all powered by Telescope.

## Features

- **Tag Search:** List all tags in your notes and quickly jump to files by tag.
- **Files by Tag:** View all Markdown files containing a specific tag.
- **Backlinks:** Find and open files that link to the current note.
- **Daily Journal:** Create and open daily journal entries with one command.
- **Journal Picker:** Quickly open recent journal files (today, yesterday, last 5 days) via a Telescope menu.
- **Create Note:** Create new notes with date-prefixed filenames in YYYY-MM-dd format.
- **Smart Link Following:** Navigate to notes using `gf` or `Ctrl-]` on `[[note_name]]` links or words, with automatic note creation for missing files.

## Prerequisites

This plugin extends the markdown grammar for tree-sitter. At the moment this needs to be compiled and linked during installation.

```
npm install -g tree-sitter-cli
```

TODO: build using CI and download the grammar .so file during installation.

## Installation

Install with your favorite Neovim plugin manager. Example using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "xpcoffee/nvim-markdown-notes",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("nvim-markdown-notes").setup {
      notes_root_path = "~/notes",          -- directory containing your markdown notes
      journal_dir_name = "journal",         -- subdirectory for daily journals
    }
  end,
}
```

## Usage

All features are exposed as Lua functions. You can map them to commands or keybindings as follows:

```lua
local notes = require("nvim-markdown-notes")

-- Find all tags in your notes
vim.keymap.set("n", "<leader>nt", notes.list_all_tags)

-- Show files with the tag under cursor
vim.keymap.set("n", "<leader>nf", function()
  local tag = vim.fn.expand("<cword>")
  notes.view_files_with_tag(tag)
end)

-- List backlinks to the current file
vim.keymap.set("n", "<leader>nb", notes.list_backlinks)

-- Open today's journal entry
vim.keymap.set("n", "<leader>nj", notes.open_daily_journal)

-- Pick a journal by date
vim.keymap.set("n", "<leader>np", notes.open_journal)

-- Create a new note with date prefix
vim.keymap.set("n", "<leader>nn", notes.create_note)
```

## Example Workflow

1. **Jump to all files tagged `#project`:**  
   Place your cursor over `#project` and press `<leader>nf`.

2. **Open today’s journal:**  
   Press `<leader>nj` to create or open today's entry in your journal directory.

3. **List backlinks (notes referencing the current note):**  
   Press `<leader>nb`.

4. **Follow note links:**  
   Place cursor on `[[note_name]]` or any word and press `gf` or `Ctrl-]` to navigate to the note. If the note doesn't exist, you'll be prompted to create it.

## Requirements

- Neovim 0.9+
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [ripgrep](https://github.com/BurntSushi/ripgrep) (for fast searching)

## Configuration

Set up the plugin with your notes directory and journal subfolder:

```lua
require("nvim-markdown-notes").setup {
  notes_root_path = "~/notes",
  journal_dir_name = "journal",
}
```

## Development - custom treesitter grammar

Build using the Makefile.

```
make
```

