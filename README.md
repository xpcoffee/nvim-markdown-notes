# nvim-markdown-notes

A Neovim plugin for managing Markdown notes and journals, inspired by tools like Obsidian. Features seamless tag searching, backlink navigation, and daily journal creation—all powered by Telescope.

## Features

- **Tag Search:** List all tags in your notes and quickly jump to files by tag.
- **Files by Tag:** View all Markdown files containing a specific tag.
- **Backlinks:** Find and open files that link to the current note.
- **Daily Journal:** Create and open daily journal entries with one command.
- **Journal Picker:** Quickly open recent journal files (today, yesterday, last 5 days) via a Telescope menu.

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
```

## Example Workflow

1. **Jump to all files tagged `#project`:**  
   Place your cursor over `#project` and press `<leader>nf`.

2. **Open today’s journal:**  
   Press `<leader>nj` to create or open today's entry in your journal directory.

3. **List backlinks (notes referencing the current note):**  
   Press `<leader>nb`.

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