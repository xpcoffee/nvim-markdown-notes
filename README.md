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
- **Graph Database (Optional):** Index your notes in Memgraph for fast relationship queries, backlinks, and AI-powered exploration.

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

**Primary Navigation (use these for searching):**

| Command | Description |
|---------|-------------|
| `:MarkdownNotesGraphTags` | Browse all tags with usage counts |
| `:MarkdownNotesGraphPeople` | Browse all people with mention counts |

**Contextual Navigation (for current note):**

| Command | Description |
|---------|-------------|
| `:MarkdownNotesGraphBacklinks` | Notes linking to current note |
| `:MarkdownNotesGraphRelated` | Notes sharing tags/mentions with current note |
| `:MarkdownNotesGraphContext` | Show all relationships for current note |

**Direct Search:**

| Command | Description |
|---------|-------------|
| `:MarkdownNotesGraphTagged [tag]` | Notes with specific tag (or browse if no arg) |
| `:MarkdownNotesGraphMentions [person]` | Notes mentioning person (or browse if no arg) |

**Management:**

| Command | Description |
|---------|-------------|
| `:MarkdownNotesGraphStatus` | Show connection status and statistics |
| `:MarkdownNotesGraphReindex` | Rebuild entire graph from all notes |
| `:MarkdownNotesGraphSync` | Sync current buffer to graph |
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

-- Primary navigation (Telescope pickers)
graph.browse_tags()                      -- All tags with counts
graph.browse_people()                    -- All people with counts
graph.find_by_tag("project")             -- Notes with tag
graph.find_by_mention("john")            -- Notes mentioning person
graph.show_backlinks()                   -- Backlinks to current note
graph.show_related()                     -- Related notes

-- Low-level query API (async callbacks)
graph.get_query().find_backlinks(filepath, function(success, results, err)
  if success then
    for _, note in ipairs(results) do
      print(note.title, note.path)
    end
  end
end)

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

### MCP Search Strategy

The MCP server provides a `get_search_instructions` tool that guides AI assistants on the optimal search order:

1. **Tags** (`find_by_tag`) - Most efficient for topic-based searches
2. **Date ranges** (`find_journals_by_date`) - For temporal queries on journals and date-prefixed notes
3. **Mentions** (`find_by_mention`) - For person-related queries
4. **Filename** (`find_by_filename`) - When you know part of the note's name
5. **Graph exploration** (`get_backlinks`, `get_related`) - For connection-based discovery
6. **Full-text search** (`search_content`) - Last resort, slower

### Available MCP Tools

| Tool | Priority | Description |
|------|----------|-------------|
| `get_search_instructions` | - | Returns the search strategy guide |
| `find_by_tag` | 1 | Find notes with a hashtag |
| `find_journals_by_date` | 2 | Find journals/notes by date range |
| `find_by_mention` | 3 | Find notes mentioning a person |
| `find_by_filename` | 4 | Search by filename/title pattern |
| `get_backlinks` | 5 | Notes linking to a specific note |
| `get_related` | 5 | Notes sharing tags/mentions |
| `get_note_context` | 5 | All relationships for a note |
| `search_content` | 6 | Full-text content search (last resort) |
| `list_all_tags` | - | List all tags with counts |
| `list_all_persons` | - | List all people with counts |
| `query_graph` | - | Run raw Cypher queries |
| `get_graph_stats` | - | Get graph statistics |
| `reindex_notes` | - | Rebuild the graph from all notes |

## Development - custom treesitter grammar

Build using the Makefile.

```
make
```
