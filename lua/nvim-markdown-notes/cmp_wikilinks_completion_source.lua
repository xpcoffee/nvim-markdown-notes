local M = {}

local completion_source = {}
function completion_source:is_available()
	return true
end

function completion_source:get_trigger_characters()
	return { "[" }
end

M.register_cmp_source = function(cmp, name)
	function completion_source:get_debug_name()
		return name
	end

	function completion_source:complete(params, callback)
		local line = params.context.cursor_before_line

		-- Only trigger when we have [[
		if not line:match("%[%[$") then
			callback({ items = {}, isIncomplete = false })
			return
		end

		-- Your custom completion items
		local items = {
			{ label = "note1", kind = cmp.lsp.CompletionItemKind.Reference },
			{ label = "note2", kind = cmp.lsp.CompletionItemKind.Reference },
			-- Add your items here
		}

		callback({ items = items, isIncomplete = false })
	end

	cmp.register_source(name, completion_source)
end

return M
