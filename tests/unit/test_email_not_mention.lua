-- Test: email addresses are not parsed as mentions
vim.cmd('edit tests/fixtures/email_test.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)

local parser = require('nvim-markdown-notes.treesitter_grammar')

-- Line 0: "@bob is a mention" - @bob should be mention
local node1 = parser.get_markdown_notes_node(0, 0, 1, 'markdown_notes')
local pass1 = node1 and node1:type() == 'mention'

-- Line 1: "hello@gmail.com is email" - position inside email should be text
local node2 = parser.get_markdown_notes_node(0, 1, 6, 'markdown_notes')
local pass2 = node2 and node2:type() == 'text'

-- Line 2: "contact hello@example.org for info" - email in middle of text
local node3 = parser.get_markdown_notes_node(0, 2, 15, 'markdown_notes')
local pass3 = node3 and node3:type() == 'text'

if pass1 and pass2 and pass3 then
  print('PASS')
else
  local failures = {}
  if not pass1 then table.insert(failures, '@bob=' .. (node1 and node1:type() or 'nil')) end
  if not pass2 then table.insert(failures, 'hello@gmail=' .. (node2 and node2:type() or 'nil')) end
  if not pass3 then table.insert(failures, 'hello@example=' .. (node3 and node3:type() or 'nil')) end
  print('FAIL: ' .. table.concat(failures, ', '))
end
