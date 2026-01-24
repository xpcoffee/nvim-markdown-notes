-- Test: mention navigation jumps to person file
require('nvim-markdown-notes').setup({
  notes_root_path = vim.fn.getcwd() .. '/tests/fixtures',
  people_dir_name = 'people',
})

vim.cmd('edit tests/fixtures/source.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)
vim.api.nvim_win_set_cursor(0, {2, 32})

require('nvim-markdown-notes').custom_jump_to_tag()

local file = vim.fn.expand('%:t')
if file == 'alice.md' then
  print('PASS')
else
  print('FAIL: expected alice.md, got ' .. file)
end
