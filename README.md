# nvim-markdown-notes

A Neovim plugin for managing a repo of Markdown notes, inspired by tools like Obsidian.

## Features

- **Tag Search:** List all tags in your notes and quickly jump to files by tag.
- **Files by Tag:** View all Markdown files containing a specific tag.
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

## Memgraph Integration (Optional)

The plugin supports optional integration with [Memgraph](https://memgraph.com/), an in-memory graph database, to create and query relationships between notes. This enables:

- **Backlink queries** - Find all notes that link to the current note
- **Related notes** - Discover notes sharing tags or mentions
- **Graph exploration** - Query the knowledge graph with Cypher
- **AI access** - Expose your note graph to AI assistants via MCP

### Prerequisites

1. **Memgraph** - Run via Docker:
   ```bash
   docker run -p 7687:7687 memgraph/memgraph
   ```

2. **Python dependencies** - Install the Memgraph client:
   ```bash
   pip install pymgclient
   ```

### Configuration

Enable Memgraph in your setup:

```lua
require("nvim-markdown-notes").setup {
  notes_root_path = "~/notes",
  memgraph = {
    enabled = true,           -- Enable graph integration
    host = "localhost",       -- Memgraph host
    port = 7687,              -- Memgraph Bolt port
    auto_sync = true,         -- Sync notes on save
    sync_debounce = 500,      -- Debounce rapid saves (ms)
  },
}
```

### Graph Commands

| Command | Description |
|---------|-------------|
| `:MarkdownNotesGraphStatus` | Show connection status and graph statistics |
| `:MarkdownNotesGraphReindex` | Rebuild entire graph from all notes |
| `:MarkdownNotesGraphSync` | Sync current buffer to graph |
| `:MarkdownNotesGraphBacklinks` | Telescope picker: notes linking to current note |
| `:MarkdownNotesGraphRelated` | Telescope picker: notes sharing tags/mentions |
| `:MarkdownNotesGraphTagged <tag>` | Telescope picker: notes with specific tag |
| `:MarkdownNotesGraphMentions <person>` | Telescope picker: notes mentioning person |
| `:MarkdownNotesGraphContext` | Show all relationships for current note |
| `:MarkdownNotesGraphConnect` | Connect or reconnect to Memgraph |

### Graph Keymaps

```lua
local notes = require("nvim-markdown-notes")

-- Show backlinks to current note
vim.keymap.set("n", "<leader>gb", function()
  vim.cmd("MarkdownNotesGraphBacklinks")
end)

-- Show related notes
vim.keymap.set("n", "<leader>gr", function()
  vim.cmd("MarkdownNotesGraphRelated")
end)

-- Show note context (all relationships)
vim.keymap.set("n", "<leader>gc", function()
  vim.cmd("MarkdownNotesGraphContext")
end)
```

### Lua API

```lua
local graph = require("nvim-markdown-notes").graph

-- Query backlinks
graph.get_query().find_backlinks(filepath, function(success, results, err)
  if success then
    for _, note in ipairs(results) do
      print(note.title, note.path)
    end
  end
end)

-- Find related notes
graph.get_query().find_related(filepath, callback)

-- Find notes by tag
graph.get_query().find_by_tag("project", callback)

-- Find notes mentioning a person
graph.get_query().find_by_mention("john", callback)

-- Run raw Cypher query
graph.get_query().run_cypher("MATCH (n:Note) RETURN n.title LIMIT 10", {}, callback)

-- Manual sync
graph.get_sync().update_note(filepath)
graph.get_sync().reindex_all()

-- Connection status
graph.is_connected()
```

### Graph Schema

The graph uses the following schema:

```cypher
// Nodes
(:Note {path, title, filename, last_modified, content_hash})
(:Person {name, display_name})
(:Tag {name})

// Relationships
(:Note)-[:LINKS_TO {line_number}]->(:Note)      // wikilinks
(:Note)-[:MENTIONS {line_number}]->(:Person)    // @mentions
(:Note)-[:HAS_TAG {line_number}]->(:Tag)        // #hashtags
(:Person)-[:HAS_NOTE]->(:Note)                  // people directory files
```

### MCP Server for AI Access

An MCP (Model Context Protocol) server is included for AI assistant integration:

```bash
# Install dependencies
pip install -r mcp/requirements.txt

# Run the server
NOTES_ROOT=~/notes python mcp/memgraph_notes_server.py
```

Configure in your MCP client (e.g., Claude Code):

```json
{
  "mcpServers": {
    "memgraph-notes": {
      "command": "python",
      "args": ["/path/to/nvim-markdown-notes/mcp/memgraph_notes_server.py"],
      "env": {
        "NOTES_ROOT": "/path/to/notes",
        "MEMGRAPH_HOST": "localhost",
        "MEMGRAPH_PORT": "7687"
      }
    }
  }
}
```

Available MCP tools:
- `search_notes` - Search notes by title
- `get_backlinks` - Find notes linking to a note
- `get_related` - Find related notes
- `get_note_context` - Get all relationships for a note
- `find_by_tag` - Find notes with a tag
- `find_by_mention` - Find notes mentioning a person
- `query_graph` - Run raw Cypher queries
- `get_graph_stats` - Get graph statistics

## Development - custom treesitter grammar

Build using the Makefile.

```
make
```
