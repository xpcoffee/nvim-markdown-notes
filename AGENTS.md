# AGENTS.md

Neovim plugin for markdown notes with wikilinks, tags, mentions, and journaling. Uses a custom treesitter grammar for syntax highlighting and navigation.

## Architecture

```
lua/nvim-markdown-notes/     # Plugin code (Lua)
├── init.lua                 # Entry point, setup(), public API
├── options.lua              # Configuration handling
├── notes.lua                # Note creation and file management
├── tags.lua                 # Tag search (uses Telescope + ripgrep)
├── wikilink.lua             # [[wikilink]] navigation
├── mentions.lua             # @mention handling
├── journal.lua              # Daily journal management
├── treesitter_grammar.lua   # Parser build and registration
├── cmp_wikilinks_completion_source.lua  # nvim-cmp integration
└── logging.lua              # Debug logging

treesitter/
├── grammar.js               # Treesitter grammar definition
└── src/                     # Generated parser source (gitignored)

parser/
└── markdown_notes.so        # Compiled parser binary

queries/
├── markdown/injections.scm  # Injects markdown_notes parser into markdown
└── markdown_notes/
    ├── highlights.scm       # Syntax highlighting rules
    └── markdown_notes.scm   # Query captures for node extraction
```

## Development Feedback Cycles

### Testing Lua Plugin Changes

1. Edit any file in `lua/nvim-markdown-notes/`
2. Reload in Neovim:
   ```vim
   :luafile %
   ```
   Or restart Neovim for a clean state.
3. Test manually using keybindings or direct function calls:
   ```vim
   :lua require('nvim-markdown-notes').list_all_tags()
   :lua require('nvim-markdown-notes').open_daily_journal()
   :lua require('nvim-markdown-notes').create_note()
   ```

For testing navigation features, create test markdown files in your configured `notes_root_path` containing `[[wikilinks]]`, `@mentions`, and `#tags`.

### Testing Treesitter Grammar Changes

1. Edit `treesitter/grammar.js`
2. Rebuild the parser:
   ```bash
   make
   ```
   Or from Neovim:
   ```vim
   :MarkdownNotesBuildParser
   ```
3. Restart Neovim to reload the parser
4. Open a markdown file and verify syntax highlighting/navigation

Quick grammar test without Neovim:
```bash
make test
# Pipes "[[test link]]" through tree-sitter parse
```

### Testing Query Changes (Highlights/Injections)

1. Edit files in `queries/markdown_notes/` or `queries/markdown/`
2. Restart Neovim to reload queries
3. Open a markdown file and verify highlighting

## Build Commands

```bash
make              # Build parser (generate + compile)
make generate     # Regenerate parser.c from grammar.js
make test         # Quick grammar test
make clean        # Remove generated files and compiled .so
make check        # Verify tree-sitter CLI is installed
```

Clean rebuild:
```bash
make clean && make
```

## Neovim Commands

```vim
:MarkdownNotesBuildParser   " Manually rebuild parser
:MarkdownNotesCleanParser   " Clean build artifacts
```

## Dependencies

- `tree-sitter-cli`: `npm install -g tree-sitter-cli`
- `ripgrep`: Required for tag/file searching
- `telescope.nvim`: Required for pickers
- C compiler (`cc`): For compiling the parser

## Debug Logging

Enable debug output in setup:
```lua
require("nvim-markdown-notes").setup {
  notes_root_path = "~/notes",
  debug_logging = true,
}
```

Logs are written via `logging.lua` and can help diagnose parser/navigation issues.

## Running Tests

```bash
make test             # Run CI-safe tests (grammar + unit)
make test-grammar     # Run tree-sitter corpus tests only
make test-unit        # Run unit tests (stubbed deps, CI-safe)
make test-integration # Run integration tests (requires real nvim config)
```

### Adding Grammar Tests

Add test cases to `treesitter/corpus/basics.txt` using tree-sitter's format:

```
=== test name ===
input text here
---
(expected_parse_tree)
```

### Adding Unit Tests

Create a file in `tests/unit/test_*.lua`. Tests run with stubbed telescope/cmp:

```lua
-- tests/unit/test_example.lua
vim.cmd('edit tests/fixtures/source.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)

-- Test logic here...

if success then
  print('PASS')
else
  print('FAIL: reason')
end
```

### Adding Integration Tests

Create a file in `tests/integration/test_*.lua`. Tests use your real nvim config:

```lua
-- tests/integration/test_example.lua
require('nvim-markdown-notes').setup({
  notes_root_path = vim.fn.getcwd() .. '/tests/fixtures',
})

-- Test logic here...

if success then
  print('PASS')
else
  print('FAIL: reason')
end
```
