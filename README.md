# nvim-markdown-notes

A Neovim plugin for managing a repo of Markdown notes, inspired by tools like Obsidian.

## Features

- **Tag Search:** List all tags in your notes and quickly jump to files by tag.
- **Files by Tag:** View all Markdown files containing a specific tag.
- **People/Mentions:** List all people (@mentions) and find notes mentioning them.
- **Daily Journal:** Create and open daily journal entries with one command.
- **Journal Picker:** Quickly open recent journal files (today, yesterday, last 5 days) via a Telescope menu.
- **Create Note:** Create new notes with date-prefixed filenames in YYYY-MM-dd format.
- **Smart Link Following:** Navigate to notes using `gf` or `Ctrl-]` on `[[note_name]]` links or words, with automatic note creation for missing files.
- **Virtual Titles:** Inline display of resolved note titles for `[[wikilinks]]` and `@mentions`. The link under the cursor expands to show raw text for editing.
- **Floating Preview:** Press `K` to preview the contents of the linked note in a floating window.
- **Graph Database (Optional):** Index your notes in Memgraph for fast relationship queries, backlinks, and AI-powered exploration.

## Prerequisites

This plugin extends the markdown grammar for tree-sitter. At the moment this needs to be compiled and linked during installation.

```
npm install -g tree-sitter-cli
```

TODO: build using CI and download the grammar .so file during installation.

### Optional: Memgraph graph database

For graph database features (backlinks, related notes, AI access via MCP), install the [`nvim-markdown-notes-memgraph`](https://github.com/xpcoffee/nvim-markdown-notes-memgraph) CLI. This requires Docker and Docker Compose.

```bash
pip install nvim-markdown-notes-memgraph
```

The CLI manages Memgraph and MCP server containers via Docker Compose. See the [CLI README](https://github.com/xpcoffee/nvim-markdown-notes-memgraph) for full documentation.

Alternatively, if you enable `memgraph` in the plugin config and the CLI is not installed, the plugin will prompt you to install it automatically.

## Installation

Install with your favorite Neovim plugin manager. Example using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "xpcoffee/nvim-markdown-notes",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("nvim-markdown-notes").setup {
      notes_root_path = "~/notes",          -- directory containing your markdown notes
    }
  end,
}
```

## Usage

All features are exposed as Lua functions. You can map them to commands or keybindings as follows:

```lua
local notes = require("nvim-markdown-notes")

-- Tags (uses graph if available, falls back to ripgrep)
vim.keymap.set("n", "<leader>nt", notes.list_all_tags)           -- Browse all tags
vim.keymap.set("n", "<leader>nf", function()                      -- Files with tag under cursor
  local tag = vim.fn.expand("<cword>")
  notes.view_files_with_tag(tag)
end)

-- People (uses graph if available, falls back to directory/ripgrep)
vim.keymap.set("n", "<leader>np", notes.list_all_people)          -- Browse all people
vim.keymap.set("n", "<leader>nm", function()                      -- Files mentioning person
  local person = vim.fn.expand("<cword>")
  notes.view_files_with_mention(person)
end)

-- Journal
vim.keymap.set("n", "<leader>nj", notes.open_daily_journal)       -- Today's journal
vim.keymap.set("n", "<leader>nJ", notes.open_journal)             -- Pick journal by date

-- Notes
vim.keymap.set("n", "<leader>nn", notes.create_note)              -- Create new note
```

## Example Workflow

1. **Browse all tags:**
   Press `<leader>nt` to see all tags. With graph enabled, you'll see usage counts.

2. **Jump to files tagged `#project`:**
   Place your cursor over `#project` and press `<leader>nf`.

3. **Browse all people:**
   Press `<leader>np` to see all people. With graph enabled, you'll see mention counts.

4. **Find notes mentioning someone:**
   Place cursor on `@john-doe` and press `<leader>nm`.

5. **Open today's journal:**
   Press `<leader>nj` to create or open today's entry.

6. **Follow note links:**
   Place cursor on `[[note_name]]` and press `Ctrl-]` to navigate. If the note doesn't exist, you'll be prompted to create it.

7. **With graph enabled - explore connections:**
   Use `:MarkdownNotesGraphBacklinks` to see what links to the current note, or `:MarkdownNotesGraphRelated` to find notes sharing tags/mentions.

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
  virtual_titles = true,          -- show resolved titles inline (default: true)
  preview_keymap = "K",           -- keymap for floating preview (default: "K")
}
```

## Memgraph Integration (Optional)

The plugin supports optional integration with [Memgraph](https://memgraph.com/) via the [`nvim-markdown-notes-memgraph`](https://github.com/xpcoffee/nvim-markdown-notes-memgraph) CLI. This enables:

- **Backlink queries** - Find all notes that link to the current note
- **Related notes** - Discover notes sharing tags or mentions
- **Graph exploration** - Query the knowledge graph with Cypher
- **AI access** - Expose your note graph to AI assistants via MCP

### Setup

1. Install the CLI (requires Docker and Docker Compose):

   ```bash
   pip install nvim-markdown-notes-memgraph
   ```

   Or enable `memgraph.enabled = true` in your plugin config and the plugin will offer to install it for you.

2. Enable in your Neovim config:

   ```lua
   require("nvim-markdown-notes").setup {
     notes_root_path = "~/notes",
     memgraph = {
       enabled = true,           -- Enable graph integration
       host = "localhost",       -- Memgraph host (default)
       port = 7687,              -- Memgraph Bolt port (default)
       auto_sync = true,         -- Sync notes on save (default)
       sync_debounce = 500,      -- Debounce rapid saves in ms (default)
     },
   }
   ```

The plugin automatically starts services and connects when Neovim opens. See the [CLI README](https://github.com/xpcoffee/nvim-markdown-notes-memgraph) for CLI commands (`start`, `stop`, `status`) and troubleshooting.

### Graph Commands

| Command | Description |
|---------|-------------|
| `:MarkdownNotesGraphTags` | Browse all tags with usage counts |
| `:MarkdownNotesGraphPeople` | Browse all people with mention counts |
| `:MarkdownNotesGraphBacklinks` | Notes linking to current note |
| `:MarkdownNotesGraphRelated` | Notes sharing tags/mentions with current note |
| `:MarkdownNotesGraphContext` | Show all relationships for current note |
| `:MarkdownNotesGraphTagged [tag]` | Notes with specific tag (or browse if no arg) |
| `:MarkdownNotesGraphMentions [person]` | Notes mentioning person (or browse if no arg) |
| `:MarkdownNotesGraphStatus` | Show connection status and statistics |
| `:MarkdownNotesGraphReindex` | Rebuild entire graph from all notes |
| `:MarkdownNotesGraphSync` | Sync current buffer to graph |
| `:MarkdownNotesGraphConnect` | Connect or reconnect to Memgraph |

### Graph Keymaps

```lua
local notes = require("nvim-markdown-notes")

vim.keymap.set("n", "<leader>gb", function() vim.cmd("MarkdownNotesGraphBacklinks") end)
vim.keymap.set("n", "<leader>gr", function() vim.cmd("MarkdownNotesGraphRelated") end)
vim.keymap.set("n", "<leader>gc", function() vim.cmd("MarkdownNotesGraphContext") end)
```

### Lua API

The main API functions automatically use the graph database when connected, falling back to ripgrep/filesystem when not:

```lua
local notes = require("nvim-markdown-notes")

-- These auto-detect graph availability
notes.list_all_tags()                    -- Browse tags (graph: with counts)
notes.view_files_with_tag("project")     -- Find notes with #project
notes.list_all_people()                  -- Browse people (graph: with mention counts)
notes.view_files_with_mention("john")    -- Find notes mentioning @john
```

For direct graph access:

```lua
local graph = require("nvim-markdown-notes").graph

-- Telescope pickers
graph.browse_tags()                      -- All tags with counts
graph.browse_people()                    -- All people with counts
graph.find_by_tag("project")             -- Notes with tag
graph.find_by_mention("john")            -- Notes mentioning person
graph.show_backlinks()                   -- Backlinks to current note
graph.show_related()                     -- Related notes

-- Low-level query API (async callbacks)
graph.get_query().find_backlinks(filepath, callback)
graph.get_query().find_by_tag("project", callback)
graph.get_query().find_by_mention("john", callback)
graph.get_query().get_all_tags(callback)
graph.get_query().get_all_persons(callback)
graph.get_query().run_cypher("MATCH (n:Note) RETURN n.title LIMIT 10", {}, callback)

-- Sync
graph.get_sync().update_note(filepath)
graph.get_sync().reindex_all()

-- Connection status
graph.is_connected()
```

### MCP Server for AI Access

The CLI includes an MCP server for AI assistant integration. Generate the config:

```bash
nvim-markdown-notes-memgraph config --notes-root ~/notes
```

Add the output to your MCP client config (e.g., Claude Desktop). See the [CLI README](https://github.com/xpcoffee/nvim-markdown-notes-memgraph#mcp-integration) for available MCP tools and search strategy.

## Development - custom treesitter grammar

Build using the Makefile.

```
make
```
