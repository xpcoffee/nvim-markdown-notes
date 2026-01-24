-- Test: wikilink navigation jumps to target file
require('nvim-markdown-notes').setup({
  notes_root_path = vim.fn.getcwd() .. '/tests/fixtures',
  people_dir_name = 'people',
})

vim.cmd('edit tests/fixtures/source.md')
vim.treesitter.get_parser(0, 'markdown'):parse(true)
vim.api.nvim_win_set_cursor(0, {2, 10})

require('nvim-markdown-notes').custom_jump_to_tag()

local file = vim.fn.expand('%:t')
if file == 'target.md' then
  print('PASS')
else
  print('FAIL: expected target.md, got ' .. file)
end
