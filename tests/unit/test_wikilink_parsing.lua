-- Test: wikilink node type detection
vim.cmd('edit tests/fixtures/source.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)

local parser = require('nvim-markdown-notes.treesitter_grammar')
local node = parser.get_markdown_notes_node(0, 1, 10)

if node and node:type() == 'wikilink' then
  print('PASS')
else
  print('FAIL: got ' .. (node and node:type() or 'nil'))
end
