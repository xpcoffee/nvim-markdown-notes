-- Test: API functions exist and are callable
local plugin = require('nvim-markdown-notes')

local functions = {
  'custom_jump_to_tag',
  'list_all_tags',
  'open_daily_journal',
  'create_note',
}

local failed = {}
for _, name in ipairs(functions) do
  if type(plugin[name]) ~= 'function' then
    table.insert(failed, name)
  end
end

if #failed == 0 then
  print('PASS')
else
  print('FAIL: missing functions: ' .. table.concat(failed, ', '))
end
