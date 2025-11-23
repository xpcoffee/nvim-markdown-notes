local M = {}

local completion_source = {}
function completion_source:is_available()
  return true
end

function completion_source:get_trigger_characters()
  return { "[", "@", "#" }
end

M.register_cmp_source = function(cmp, name)
  local wikilinks = require("nvim-markdown-notes.wikilink")
  local mentions = require("nvim-markdown-notes.mentions")
  local tags = require("nvim-markdown-notes.tags")

  function completion_source:get_debug_name()
    return name
  end

  function completion_source:complete(params, callback)
    local line = params.context.cursor_before_line
    local items = {}

    if wikilinks.is_completion_match(line) then
      items = wikilinks.suggest(cmp)
    elseif mentions.is_completion_match(line) then
      items = mentions.suggest(cmp)
    elseif tags.is_completion_match(line) then
      items = tags.suggest(cmp)
    end

    callback({ items = items, isIncomplete = false })
  end

  cmp.register_source(name, completion_source)
end

return M
