local M = {}

local custom_parser = require("nvim-markdown-notes.treesitter_grammar")

---@param node_type string
---@return boolean
M.is_match = function(node_type)
	return node_type == "link"
		or node_type == "link_text"
		or node_type == "inline_link"
		or node_type == "link_destination"
		or node_type == "link_label"
		or node_type == "link_reference_definition"
		or node_type == "full_reference_link"
end

---@param n TSNode node
---@param t string type
local function find_child_of_type(n, t)
	for child, _ in n:iter_children() do
		if child:type() == t then
			return child
		end
	end
	return nil
end

---@param label string
---@return TSNode?
local function get_reference_definition_node(label)
	local reference_definition_nodes = custom_parser.get_nodes_by_type(0, "link_reference_definition")
	if not reference_definition_nodes then
		return nil
	end

	for _, node in ipairs(reference_definition_nodes) do
		local label_node = find_child_of_type(node, "link_label")
		if not label_node then
			goto continue
		end

		local label_text = vim.treesitter.get_node_text(label_node, 0)
		if label_text == label then
			return label_node
		end

		::continue::
	end

	return nil
end

---@param node TSNode?
---@return string | nil
local function get_text(node)
	if not node then
		return nil
	end

	local t = node:type()

	if t == "link_destination" then
		print("in a destination " .. t)
		return vim.treesitter.get_node_text(node, 0)
	elseif t == "link" or t == "inline_link" or t == "link_reference_definition" then
		print("in a parent " .. t)
		local destination_node = find_child_of_type(node, "link_destination")
		return get_text(destination_node)
	elseif t == "full_reference_link" then
		print("resolving reference ")
		local label_node = find_child_of_type(node, "link_label")
		if not label_node then
			return nil
		end

		local label_text = vim.treesitter.get_node_text(label_node, 0)
		if not label_text then
			return nil
		end

		local definition_node = get_reference_definition_node(label_text)
		return get_text(definition_node)
	elseif t == "link_text" or t == "link_label" or t == "link_reference_definition" then
		print("in a child " .. t)
		-- climb to enclosing link node
		---@type TSNode?
		local cur = node
		while
			cur
			and (
				cur:type() ~= "link"
				and cur:type() ~= "inline_link"
				and cur:type() ~= "link_reference_definition"
				and cur:type() ~= "full_reference_link"
			)
		do
			cur = cur:parent()
			print("jumping up to " .. ((cur and cur:type()) or "nil"))
		end

		return get_text(cur)
	end

	print("nada for " .. t)
	return nil
end

---@param node TSNode
M.jump = function(node)
	local text = get_text(node)
	if text ~= nil then
		print("opening " .. text)
		vim.ui.open(text)
	end
end

M.is_completion_match = function(line)
	return false
end

M.suggest = function(cmp)
	return {}
end

---@param opts MarkdownNotesFullOpts
M.setup = function(opts)
	M.opts = opts
end

return M
