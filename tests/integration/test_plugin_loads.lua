-- Test: plugin loads successfully
local ok, err = pcall(require, 'nvim-markdown-notes')

if ok then
  print('PASS')
else
  print('FAIL: ' .. tostring(err))
end
