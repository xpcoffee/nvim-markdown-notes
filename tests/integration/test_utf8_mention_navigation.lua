-- Test: UTF-8 mention navigation jumps to person file
require('nvim-markdown-notes').setup({
  notes_root_path = vim.fn.getcwd() .. '/tests/fixtures',
  people_dir_name = 'people',
})

vim.cmd('edit tests/fixtures/utf8_mentions.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)
vim.api.nvim_win_set_cursor(0, {1, 1})  -- @andré on line 1

require('nvim-markdown-notes').custom_jump_to_tag()

local file = vim.fn.expand('%:t')
if file == 'andré.md' then
  print('PASS')
else
  print('FAIL: expected andré.md, got ' .. file)
end
