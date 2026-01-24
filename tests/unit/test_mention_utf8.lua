-- Test: mention with UTF-8 characters (diacritics, cyrillic)
vim.cmd('edit tests/fixtures/utf8_mentions.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)

local parser = require('nvim-markdown-notes.treesitter_grammar')

-- Test @andré (Latin with diacritics)
local node1 = parser.get_markdown_notes_node(0, 0, 1, 'markdown_notes')
local pass1 = node1 and node1:type() == 'mention'

-- Test @sławomir (Polish characters)
local node2 = parser.get_markdown_notes_node(0, 1, 1, 'markdown_notes')
local pass2 = node2 and node2:type() == 'mention'

-- Test @борис (Cyrillic)
local node3 = parser.get_markdown_notes_node(0, 2, 1, 'markdown_notes')
local pass3 = node3 and node3:type() == 'mention'

if pass1 and pass2 and pass3 then
  print('PASS')
else
  local failures = {}
  if not pass1 then table.insert(failures, 'andré=' .. (node1 and node1:type() or 'nil')) end
  if not pass2 then table.insert(failures, 'sławomir=' .. (node2 and node2:type() or 'nil')) end
  if not pass3 then table.insert(failures, 'борис=' .. (node3 and node3:type() or 'nil')) end
  print('FAIL: ' .. table.concat(failures, ', '))
end
