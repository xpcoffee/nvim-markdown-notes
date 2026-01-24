--- Graph query module
--- Cypher query builders for Memgraph
local M = {}

---@type MarkdownNotesFullOpts | nil
M.opts = nil

--- Get the connection module
local function get_connection()
  return require("nvim-markdown-notes.graph.connection")
end

--- Find notes that link to a given note (backlinks)
---@param note_path string Path to the note
---@param callback function Called with (success, results, error)
function M.find_backlinks(note_path, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    callback(false, nil, "Not connected to Memgraph")
    return
  end

  local cypher = [[
    MATCH (source:Note)-[r:LINKS_TO]->(target:Note {path: $path})
    RETURN source.path AS path, source.title AS title, r.line_number AS line_number
    ORDER BY source.title
  ]]

  connection.request("query", {
    cypher = cypher,
    params = { path = note_path },
  }, function(success, data, err)
    if success and data and data.results then
      -- Transform results into a more usable format
      local results = {}
      for _, row in ipairs(data.results) do
        table.insert(results, {
          path = row[1],
          title = row[2],
          line_number = row[3],
        })
      end
      callback(true, results, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Find notes related to a given note (sharing tags or mentions)
---@param note_path string Path to the note
---@param callback function Called with (success, results, error)
function M.find_related(note_path, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    callback(false, nil, "Not connected to Memgraph")
    return
  end

  -- Find notes that share tags or mentions with this note
  local cypher = [[
    MATCH (source:Note {path: $path})-[:HAS_TAG|MENTIONS]->(shared)<-[:HAS_TAG|MENTIONS]-(related:Note)
    WHERE related.path <> $path
    WITH related, count(shared) AS shared_count, collect(DISTINCT labels(shared)[0] + ': ' + COALESCE(shared.name, '')) AS connections
    RETURN related.path AS path, related.title AS title, shared_count, connections
    ORDER BY shared_count DESC, related.title
    LIMIT 20
  ]]

  connection.request("query", {
    cypher = cypher,
    params = { path = note_path },
  }, function(success, data, err)
    if success and data and data.results then
      local results = {}
      for _, row in ipairs(data.results) do
        table.insert(results, {
          path = row[1],
          title = row[2],
          shared_count = row[3],
          connections = row[4],
        })
      end
      callback(true, results, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Find notes with a specific tag
---@param tag string Tag name (without #)
---@param callback function Called with (success, results, error)
function M.find_by_tag(tag, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    callback(false, nil, "Not connected to Memgraph")
    return
  end

  local cypher = [[
    MATCH (note:Note)-[r:HAS_TAG]->(t:Tag {name: $tag})
    RETURN note.path AS path, note.title AS title, r.line_number AS line_number
    ORDER BY note.title
  ]]

  connection.request("query", {
    cypher = cypher,
    params = { tag = tag },
  }, function(success, data, err)
    if success and data and data.results then
      local results = {}
      for _, row in ipairs(data.results) do
        table.insert(results, {
          path = row[1],
          title = row[2],
          line_number = row[3],
        })
      end
      callback(true, results, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Find notes mentioning a specific person
---@param person string Person name (without @)
---@param callback function Called with (success, results, error)
function M.find_by_mention(person, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    callback(false, nil, "Not connected to Memgraph")
    return
  end

  local cypher = [[
    MATCH (note:Note)-[r:MENTIONS]->(p:Person {name: $person})
    RETURN note.path AS path, note.title AS title, r.line_number AS line_number
    ORDER BY note.title
  ]]

  connection.request("query", {
    cypher = cypher,
    params = { person = person },
  }, function(success, data, err)
    if success and data and data.results then
      local results = {}
      for _, row in ipairs(data.results) do
        table.insert(results, {
          path = row[1],
          title = row[2],
          line_number = row[3],
        })
      end
      callback(true, results, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Get all relationships for a note (full context)
---@param note_path string Path to the note
---@param callback function Called with (success, context, error)
function M.get_note_context(note_path, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    callback(false, nil, "Not connected to Memgraph")
    return
  end

  -- Get outgoing links, tags, mentions, and backlinks
  local cypher = [[
    MATCH (note:Note {path: $path})
    OPTIONAL MATCH (note)-[links_to:LINKS_TO]->(linked:Note)
    OPTIONAL MATCH (note)-[has_tag:HAS_TAG]->(tag:Tag)
    OPTIONAL MATCH (note)-[mentions:MENTIONS]->(person:Person)
    OPTIONAL MATCH (backlink:Note)-[bl:LINKS_TO]->(note)
    RETURN
      note.title AS title,
      collect(DISTINCT {path: linked.path, title: linked.title}) AS outgoing_links,
      collect(DISTINCT tag.name) AS tags,
      collect(DISTINCT person.name) AS mentions,
      collect(DISTINCT {path: backlink.path, title: backlink.title}) AS backlinks
  ]]

  connection.request("query", {
    cypher = cypher,
    params = { path = note_path },
  }, function(success, data, err)
    if success and data and data.results and #data.results > 0 then
      local row = data.results[1]
      local context = {
        title = row[1],
        outgoing_links = row[2] or {},
        tags = row[3] or {},
        mentions = row[4] or {},
        backlinks = row[5] or {},
      }
      -- Filter out null entries
      context.outgoing_links = vim.tbl_filter(function(l) return l.path ~= nil end, context.outgoing_links)
      context.backlinks = vim.tbl_filter(function(l) return l.path ~= nil end, context.backlinks)
      callback(true, context, nil)
    else
      local error_msg = (type(err) == "string" and err) or "Note not found in graph"
      callback(false, nil, error_msg)
    end
  end)
end

--- Execute a raw Cypher query
---@param cypher string Cypher query
---@param params table | nil Query parameters
---@param callback function Called with (success, results, error)
function M.run_cypher(cypher, params, callback)
  local connection = get_connection()

  if not connection.is_connected() then
    callback(false, nil, "Not connected to Memgraph")
    return
  end

  connection.request("query", {
    cypher = cypher,
    params = params or {},
  }, function(success, data, err)
    if success and data then
      callback(true, data.results or {}, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Get all tags in the graph
---@param callback function Called with (success, tags, error)
function M.get_all_tags(callback)
  local cypher = [[
    MATCH (t:Tag)<-[r:HAS_TAG]-()
    RETURN t.name AS name, count(r) AS usage_count
    ORDER BY usage_count DESC, t.name
  ]]

  M.run_cypher(cypher, {}, function(success, results, err)
    if success then
      local tags = {}
      for _, row in ipairs(results) do
        table.insert(tags, {
          name = row[1],
          count = row[2],
        })
      end
      callback(true, tags, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Get all persons in the graph
---@param callback function Called with (success, persons, error)
function M.get_all_persons(callback)
  local cypher = [[
    MATCH (p:Person)
    OPTIONAL MATCH (p)<-[r:MENTIONS]-()
    OPTIONAL MATCH (p)-[:HAS_NOTE]->(note:Note)
    RETURN p.name AS name, p.display_name AS display_name, count(r) AS mention_count, note.path AS note_path
    ORDER BY mention_count DESC, p.name
  ]]

  M.run_cypher(cypher, {}, function(success, results, err)
    if success then
      local persons = {}
      for _, row in ipairs(results) do
        table.insert(persons, {
          name = row[1],
          display_name = row[2],
          mention_count = row[3],
          note_path = row[4],
        })
      end
      callback(true, persons, nil)
    else
      callback(false, nil, err)
    end
  end)
end

--- Setup the query module
---@param opts MarkdownNotesFullOpts
function M.setup(opts)
  M.opts = opts
end

return M
