-- Minimal config for unit testing (stubs dependencies)
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. '/parser')

-- Stub out telescope (not available in CI)
local telescope_stub = {
  new = function() return { find = function() end } end,
}
package.loaded['telescope.pickers'] = telescope_stub
package.loaded['telescope.finders'] = {
  new_oneshot_job = function() return {} end,
  new_table = function() return {} end,
}
package.loaded['telescope.actions'] = {
  select_default = { replace = function() end },
  close = function() end,
}
package.loaded['telescope.actions.state'] = {
  get_selected_entry = function() return {} end,
}
package.loaded['telescope.config'] = {
  values = {
    grep_previewer = function() return {} end,
    generic_sorter = function() return {} end,
  },
}

-- Setup plugin with test fixtures path
require('nvim-markdown-notes').setup({
  notes_root_path = vim.fn.getcwd() .. '/tests/fixtures',
  people_dir_name = 'people',
})
