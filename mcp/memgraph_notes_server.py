#!/usr/bin/env python3
"""
MCP Server for Memgraph Notes

This MCP server exposes the Memgraph graph database to AI assistants,
allowing them to explore note relationships, find backlinks, and query
the knowledge graph.

Usage:
    python3 memgraph_notes_server.py [--host HOST] [--port PORT] [--notes-root PATH]

Environment variables:
    MEMGRAPH_HOST: Memgraph host (default: localhost)
    MEMGRAPH_PORT: Memgraph port (default: 7687)
    NOTES_ROOT: Root directory for notes
"""

import asyncio
import json
import os
import re
import sys
import glob
from typing import Any, Optional
from pathlib import Path

# MCP SDK imports
try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import (
        Tool,
        TextContent,
        Resource,
        ResourceTemplate,
    )
    HAS_MCP = True
except ImportError:
    HAS_MCP = False
    print("MCP SDK not installed. Install with: pip install mcp", file=sys.stderr)

# Memgraph client
try:
    import mgclient
    HAS_MGCLIENT = True
except ImportError:
    HAS_MGCLIENT = False


class MemgraphNotesServer:
    def __init__(self, host: str = "localhost", port: int = 7687, notes_root: str = None):
        self.host = host
        self.port = port
        self.notes_root = notes_root or os.getcwd()
        self.connection: Optional[Any] = None

    def connect(self) -> bool:
        """Connect to Memgraph database."""
        if not HAS_MGCLIENT:
            return False

        try:
            self.connection = mgclient.connect(host=self.host, port=self.port)
            self.connection.autocommit = True
            return True
        except Exception as e:
            print(f"Failed to connect to Memgraph: {e}", file=sys.stderr)
            return False

    def is_connected(self) -> bool:
        """Check if connected to Memgraph."""
        if not self.connection:
            return False
        try:
            cursor = self.connection.cursor()
            cursor.execute("RETURN 1")
            cursor.fetchall()
            return True
        except Exception:
            self.connection = None
            return False

    def ensure_connected(self) -> bool:
        """Ensure connection is alive, reconnect if needed."""
        if not self.is_connected():
            return self.connect()
        return True

    def query(self, cypher: str, params: dict = None) -> list:
        """Execute a Cypher query and return results."""
        if not self.ensure_connected():
            raise Exception("Not connected to Memgraph")

        cursor = self.connection.cursor()
        cursor.execute(cypher, params or {})
        rows = cursor.fetchall()

        # Convert to serializable format
        results = []
        for row in rows:
            row_data = []
            for item in row:
                if hasattr(item, 'properties'):
                    row_data.append(dict(item.properties))
                else:
                    row_data.append(item)
            results.append(row_data)
        return results

    def get_backlinks(self, note_path: str) -> list[dict]:
        """Find notes that link to a given note."""
        cypher = """
            MATCH (source:Note)-[r:LINKS_TO]->(target:Note {path: $path})
            RETURN source.path AS path, source.title AS title, r.line_number AS line
            ORDER BY source.title
        """
        results = self.query(cypher, {"path": note_path})
        return [{"path": r[0], "title": r[1], "line": r[2]} for r in results]

    def get_related(self, note_path: str) -> list[dict]:
        """Find notes related to a given note (sharing tags/mentions)."""
        cypher = """
            MATCH (source:Note {path: $path})-[:HAS_TAG|MENTIONS]->(shared)<-[:HAS_TAG|MENTIONS]-(related:Note)
            WHERE related.path <> $path
            WITH related, count(shared) AS shared_count,
                 collect(DISTINCT labels(shared)[0] + ': ' + COALESCE(shared.name, '')) AS connections
            RETURN related.path AS path, related.title AS title, shared_count, connections
            ORDER BY shared_count DESC
            LIMIT 20
        """
        results = self.query(cypher, {"path": note_path})
        return [{"path": r[0], "title": r[1], "shared_count": r[2], "connections": r[3]} for r in results]

    def get_note_context(self, note_path: str) -> dict:
        """Get full context for a note including all relationships."""
        cypher = """
            MATCH (note:Note {path: $path})
            OPTIONAL MATCH (note)-[:LINKS_TO]->(linked:Note)
            OPTIONAL MATCH (note)-[:HAS_TAG]->(tag:Tag)
            OPTIONAL MATCH (note)-[:MENTIONS]->(person:Person)
            OPTIONAL MATCH (backlink:Note)-[:LINKS_TO]->(note)
            RETURN
                note.title AS title,
                note.path AS path,
                collect(DISTINCT {path: linked.path, title: linked.title}) AS outgoing_links,
                collect(DISTINCT tag.name) AS tags,
                collect(DISTINCT person.name) AS mentions,
                collect(DISTINCT {path: backlink.path, title: backlink.title}) AS backlinks
        """
        results = self.query(cypher, {"path": note_path})
        if not results:
            return {"error": "Note not found"}

        row = results[0]
        return {
            "title": row[0],
            "path": row[1],
            "outgoing_links": [l for l in row[2] if l.get("path")],
            "tags": [t for t in row[3] if t],
            "mentions": [m for m in row[4] if m],
            "backlinks": [b for b in row[5] if b.get("path")],
        }

    def search_notes(self, query: str) -> list[dict]:
        """Search for notes by title or content patterns."""
        # Use Memgraph's text matching
        cypher = """
            MATCH (n:Note)
            WHERE n.title CONTAINS $query OR n.filename CONTAINS $query
            RETURN n.path AS path, n.title AS title
            ORDER BY n.title
            LIMIT 20
        """
        results = self.query(cypher, {"query": query})
        return [{"path": r[0], "title": r[1]} for r in results]

    def find_by_tag(self, tag: str) -> list[dict]:
        """Find notes with a specific tag."""
        tag = tag.lstrip("#")
        cypher = """
            MATCH (note:Note)-[r:HAS_TAG]->(t:Tag {name: $tag})
            RETURN note.path AS path, note.title AS title, r.line_number AS line
            ORDER BY note.title
        """
        results = self.query(cypher, {"tag": tag})
        return [{"path": r[0], "title": r[1], "line": r[2]} for r in results]

    def find_by_mention(self, person: str) -> list[dict]:
        """Find notes mentioning a specific person."""
        person = person.lstrip("@")
        cypher = """
            MATCH (note:Note)-[r:MENTIONS]->(p:Person {name: $person})
            RETURN note.path AS path, note.title AS title, r.line_number AS line
            ORDER BY note.title
        """
        results = self.query(cypher, {"person": person})
        return [{"path": r[0], "title": r[1], "line": r[2]} for r in results]

    def get_all_tags(self) -> list[dict]:
        """Get all tags with usage counts."""
        cypher = """
            MATCH (t:Tag)<-[r:HAS_TAG]-()
            RETURN t.name AS name, count(r) AS count
            ORDER BY count DESC
        """
        results = self.query(cypher, {})
        return [{"name": r[0], "count": r[1]} for r in results]

    def get_all_persons(self) -> list[dict]:
        """Get all mentioned persons."""
        cypher = """
            MATCH (p:Person)
            OPTIONAL MATCH (p)<-[r:MENTIONS]-()
            RETURN p.name AS name, count(r) AS mention_count
            ORDER BY mention_count DESC
        """
        results = self.query(cypher, {})
        return [{"name": r[0], "mention_count": r[1]} for r in results]

    def get_graph_stats(self) -> dict:
        """Get statistics about the graph."""
        stats = {}

        queries = [
            ("notes", "MATCH (n:Note) RETURN count(n)"),
            ("tags", "MATCH (t:Tag) RETURN count(t)"),
            ("persons", "MATCH (p:Person) RETURN count(p)"),
            ("links", "MATCH ()-[r:LINKS_TO]->() RETURN count(r)"),
            ("mentions", "MATCH ()-[r:MENTIONS]->() RETURN count(r)"),
            ("tag_usages", "MATCH ()-[r:HAS_TAG]->() RETURN count(r)"),
        ]

        for name, cypher in queries:
            try:
                result = self.query(cypher)
                stats[name] = result[0][0] if result else 0
            except Exception:
                stats[name] = 0

        return stats

    def read_note_content(self, note_path: str) -> str:
        """Read the content of a note file."""
        try:
            path = Path(note_path)
            if not path.is_absolute():
                path = Path(self.notes_root) / note_path

            if path.exists():
                return path.read_text()
            return f"Note not found: {note_path}"
        except Exception as e:
            return f"Error reading note: {e}"

    def extract_from_file(self, filepath: str) -> dict:
        """Extract wikilinks, mentions, and hashtags from a markdown file."""
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            return {
                'path': filepath,
                'title': Path(filepath).stem,
                'content': '',
                'wikilinks': [],
                'mentions': [],
                'hashtags': []
            }

        lines = content.split('\n')
        title = lines[0] if lines else Path(filepath).stem
        title = re.sub(r'^#+ ', '', title)  # Remove heading prefix

        wikilinks = []
        mentions = []
        hashtags = []

        for line_num, line in enumerate(lines, 1):
            # Wikilinks: [[target]] or [[target|alias]]
            for match in re.finditer(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]', line):
                link_text = match.group(1)
                target_path = os.path.join(self.notes_root, link_text + '.md')
                wikilinks.append({
                    'target': link_text,
                    'target_path': target_path,
                    'line_number': line_num
                })

            # Mentions: @person-name (allow hyphens and underscores)
            for match in re.finditer(r'@([a-zA-Z][a-zA-Z0-9_-]*)', line):
                name = match.group(1)
                end_pos = match.end()
                rest_of_line = line[end_pos:]
                # Skip if this is part of an email
                if rest_of_line.startswith(('@', '.com', '.co', '.org', '.io', '.nl', '.uk')):
                    continue
                mentions.append({
                    'name': name,
                    'line_number': line_num
                })

            # Hashtags: #tag
            for match in re.finditer(r'(?<![/=])#([a-zA-Z][a-zA-Z0-9_-]*)', line):
                tag = match.group(1)
                if tag not in ['gid', 'browse', 'edit', 'resource']:
                    hashtags.append({
                        'name': tag,
                        'line_number': line_num
                    })

        return {
            'path': filepath,
            'title': title,
            'content': content,
            'wikilinks': wikilinks,
            'mentions': mentions,
            'hashtags': hashtags
        }

    def reindex_all_notes(self) -> dict:
        """Reindex all notes in the notes_root directory."""
        # Find all markdown files
        md_files = glob.glob(os.path.join(self.notes_root, '**/*.md'), recursive=True)

        # Clear the graph
        self.query("MATCH (n) DETACH DELETE n")

        # Create indexes
        index_queries = [
            "CREATE INDEX ON :Note(path)",
            "CREATE INDEX ON :Note(filename)",
            "CREATE INDEX ON :Person(name)",
            "CREATE INDEX ON :Tag(name)",
        ]
        for q in index_queries:
            try:
                self.query(q)
            except Exception:
                pass  # Index might already exist

        # Extract and index each file
        indexed = 0
        errors = []

        for filepath in md_files:
            try:
                note = self.extract_from_file(filepath)
                self._index_note(note)
                indexed += 1
            except Exception as e:
                errors.append({"path": filepath, "error": str(e)})

        return {
            "indexed": indexed,
            "total": len(md_files),
            "errors": errors
        }

    def _index_note(self, note: dict):
        """Index a single note into the graph."""
        import hashlib
        from datetime import datetime

        path = note['path']
        title = note['title']
        content = note['content']
        wikilinks = note.get('wikilinks', [])
        mentions = note.get('mentions', [])
        hashtags = note.get('hashtags', [])

        filename = os.path.basename(path)
        content_hash = hashlib.md5(content.encode()).hexdigest()
        last_modified = datetime.now().isoformat()

        # Create/update note node
        self.query("""
            MERGE (n:Note {path: $path})
            SET n.title = $title,
                n.filename = $filename,
                n.content_hash = $content_hash,
                n.last_modified = $last_modified
        """, {
            "path": path,
            "title": title,
            "filename": filename,
            "content_hash": content_hash,
            "last_modified": last_modified
        })

        # Create wikilink relationships
        for link in wikilinks:
            target_path = link.get('target_path')
            line_number = link.get('line_number', 0)
            if target_path:
                self.query("""
                    MATCH (source:Note {path: $source_path})
                    MERGE (target:Note {path: $target_path})
                    MERGE (source)-[r:LINKS_TO {line_number: $line_number}]->(target)
                """, {
                    "source_path": path,
                    "target_path": target_path,
                    "line_number": line_number
                })

        # Create mention relationships
        for mention in mentions:
            person_name = mention.get('name')
            line_number = mention.get('line_number', 0)
            if person_name:
                self.query("""
                    MATCH (source:Note {path: $source_path})
                    MERGE (person:Person {name: $person_name})
                    MERGE (source)-[r:MENTIONS {line_number: $line_number}]->(person)
                """, {
                    "source_path": path,
                    "person_name": person_name,
                    "line_number": line_number
                })

        # Create hashtag relationships
        for tag in hashtags:
            tag_name = tag.get('name')
            line_number = tag.get('line_number', 0)
            if tag_name:
                self.query("""
                    MATCH (source:Note {path: $source_path})
                    MERGE (tag:Tag {name: $tag_name})
                    MERGE (source)-[r:HAS_TAG {line_number: $line_number}]->(tag)
                """, {
                    "source_path": path,
                    "tag_name": tag_name,
                    "line_number": line_number
                })

        # Check if this is a person note (in people directory)
        if "/people/" in path:
            person_name = os.path.splitext(filename)[0]
            self.query("""
                MERGE (person:Person {name: $person_name})
                SET person.display_name = $person_name
                WITH person
                MATCH (note:Note {path: $path})
                MERGE (person)-[:HAS_NOTE]->(note)
            """, {
                "person_name": person_name,
                "path": path
            })


    def find_journals_by_date_range(self, start_date: str, end_date: str = None) -> list[dict]:
        """Find journal notes within a date range.

        Journal files are in /journal/ directory with YYYY-MM-DD format.
        Date-prefixed notes have formats like: YYYY-MM-DD, YYYY-MM, YYYY-HH (half-year)
        """
        if end_date is None:
            end_date = start_date

        # Search for journal entries and date-prefixed notes
        cypher = """
            MATCH (n:Note)
            WHERE (n.path CONTAINS '/journal/' OR n.filename STARTS WITH '20')
            AND (
                n.filename >= $start_date
                AND n.filename <= $end_date + 'z'
            )
            RETURN n.path AS path, n.title AS title, n.filename AS filename
            ORDER BY n.filename DESC
        """
        results = self.query(cypher, {"start_date": start_date, "end_date": end_date})
        return [{"path": r[0], "title": r[1], "filename": r[2]} for r in results]

    def find_notes_by_filename_pattern(self, pattern: str) -> list[dict]:
        """Find notes where filename contains the pattern."""
        cypher = """
            MATCH (n:Note)
            WHERE toLower(n.filename) CONTAINS toLower($pattern)
               OR toLower(n.title) CONTAINS toLower($pattern)
            RETURN n.path AS path, n.title AS title, n.filename AS filename
            ORDER BY n.filename DESC
            LIMIT 50
        """
        results = self.query(cypher, {"pattern": pattern})
        return [{"path": r[0], "title": r[1], "filename": r[2]} for r in results]

    def search_note_content(self, query: str) -> list[dict]:
        """Full-text search in note content. Use this as a LAST RESORT."""
        # Read files and search content since Memgraph doesn't store full content
        results = []
        md_files = glob.glob(os.path.join(self.notes_root, '**/*.md'), recursive=True)

        query_lower = query.lower()
        for filepath in md_files:
            try:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                if query_lower in content.lower():
                    lines = content.split('\n')
                    title = lines[0] if lines else Path(filepath).stem
                    title = re.sub(r'^#+ ', '', title)

                    # Find matching lines
                    matching_lines = []
                    for i, line in enumerate(lines, 1):
                        if query_lower in line.lower():
                            matching_lines.append({"line": i, "text": line.strip()[:100]})
                            if len(matching_lines) >= 3:
                                break

                    results.append({
                        "path": filepath,
                        "title": title,
                        "matches": matching_lines
                    })
                    if len(results) >= 20:
                        break
            except Exception:
                pass

        return results


# Search strategy instructions for AI assistants
SEARCH_INSTRUCTIONS = """
## Notes Search Strategy

When searching through notes, use this priority order (most efficient first):

### 1. TAGS (Highest Priority)
Use `find_by_tag` for topic-based searches. Tags are explicit categorizations.
- Examples: #project, #ops, #tech, #oncall, #meeting
- Use `list_all_tags` to see available tags

### 2. DATE RANGES (For temporal queries)
Use `find_journals_by_date` for time-based searches.
- Journal files: Located in /journal/ with YYYY-MM-DD.md format
- Date-prefixed notes: Many notes start with dates like "2024-05-02 Project name.md"
- Date formats: YYYY-MM-DD (specific day), YYYY-MM (month), YYYY-HH (half-year)
- Example: To find notes from January 2025, use start_date="2025-01", end_date="2025-01"

### 3. MENTIONS (For people-related queries)
Use `find_by_mention` to find notes mentioning specific people.
- Format: @person-name (e.g., @john-doe)
- Use `list_all_persons` to see known people

### 4. FILENAME/TITLE SEARCH
Use `find_by_filename` when you know part of the note's name.
- Searches both filename and title
- Good for finding specific topics or projects

### 5. GRAPH EXPLORATION
Use `get_backlinks`, `get_related`, `get_note_context` to explore connections.
- Find what links TO a note (backlinks)
- Find notes sharing tags/mentions (related)

### 6. FULL-TEXT SEARCH (Last Resort)
Use `search_content` only when other methods fail.
- Searches inside note content
- Slower and less precise
- Returns matching line numbers

### Tips:
- Combine methods: Find by tag first, then filter by date
- Use `get_graph_stats` to understand the knowledge base size
- Use `query_graph` for complex Cypher queries when needed
"""


def create_server(mg_server: MemgraphNotesServer) -> Server:
    """Create the MCP server with tools and resources."""
    server = Server("memgraph-notes")

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="get_search_instructions",
                description="CALL THIS FIRST before searching. Returns the recommended search strategy for finding notes efficiently. Explains which tools to use in what order.",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
            Tool(
                name="find_by_tag",
                description="[PRIORITY 1] Find notes by hashtag. Most efficient for topic searches. Use list_all_tags first to see available tags.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "tag": {
                            "type": "string",
                            "description": "Tag name (with or without # prefix). Examples: project, ops, tech, oncall"
                        }
                    },
                    "required": ["tag"]
                }
            ),
            Tool(
                name="find_journals_by_date",
                description="[PRIORITY 2] Find journal entries and date-prefixed notes within a date range. Journals are in /journal/YYYY-MM-DD.md format. Many notes have date prefixes like '2024-05-02 Topic.md'.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "start_date": {
                            "type": "string",
                            "description": "Start date in YYYY-MM-DD, YYYY-MM, or YYYY format"
                        },
                        "end_date": {
                            "type": "string",
                            "description": "End date (optional, defaults to start_date for single day/month)"
                        }
                    },
                    "required": ["start_date"]
                }
            ),
            Tool(
                name="find_by_mention",
                description="[PRIORITY 3] Find notes mentioning a specific person (@mentions). Use list_all_persons to see known people.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "person": {
                            "type": "string",
                            "description": "Person name (with or without @ prefix). Example: john-doe"
                        }
                    },
                    "required": ["person"]
                }
            ),
            Tool(
                name="find_by_filename",
                description="[PRIORITY 4] Search notes by filename or title pattern. Good when you know part of the note's name.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "pattern": {
                            "type": "string",
                            "description": "Pattern to match in filename or title (case-insensitive)"
                        }
                    },
                    "required": ["pattern"]
                }
            ),
            Tool(
                name="search_content",
                description="[PRIORITY 6 - LAST RESORT] Full-text search in note content. Only use when tags, dates, mentions, and filename searches fail. Slower and less precise.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Text to search for in note content"
                        }
                    },
                    "required": ["query"]
                }
            ),
            Tool(
                name="get_backlinks",
                description="[PRIORITY 5 - Graph exploration] Find all notes that link TO a specific note via [[wikilinks]].",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "note_path": {
                            "type": "string",
                            "description": "Full path to the note file"
                        }
                    },
                    "required": ["note_path"]
                }
            ),
            Tool(
                name="get_related",
                description="[PRIORITY 5 - Graph exploration] Find notes related to a specific note by shared tags or mentions.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "note_path": {
                            "type": "string",
                            "description": "Full path to the note file"
                        }
                    },
                    "required": ["note_path"]
                }
            ),
            Tool(
                name="get_note_context",
                description="[PRIORITY 5 - Graph exploration] Get full context for a note: outgoing links, backlinks, tags, and mentions.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "note_path": {
                            "type": "string",
                            "description": "Full path to the note file"
                        }
                    },
                    "required": ["note_path"]
                }
            ),
            Tool(
                name="list_all_tags",
                description="List all hashtags used in notes with usage counts. Use this to discover available tags before using find_by_tag.",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
            Tool(
                name="list_all_persons",
                description="List all persons mentioned in notes. Use this to discover people before using find_by_mention.",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
            Tool(
                name="query_graph",
                description="Execute a raw Cypher query on the graph database (for advanced exploration)",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "cypher": {
                            "type": "string",
                            "description": "Cypher query to execute"
                        },
                        "params": {
                            "type": "object",
                            "description": "Query parameters (optional)"
                        }
                    },
                    "required": ["cypher"]
                }
            ),
            Tool(
                name="get_graph_stats",
                description="Get statistics about the knowledge graph (counts of notes, tags, links, etc.)",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
            Tool(
                name="reindex_notes",
                description="Reindex all notes from the notes directory into the graph database. This clears the existing graph and rebuilds it from scratch.",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        try:
            if name == "get_search_instructions":
                return [TextContent(type="text", text=SEARCH_INSTRUCTIONS)]

            elif name == "find_journals_by_date":
                results = mg_server.find_journals_by_date_range(
                    arguments["start_date"],
                    arguments.get("end_date")
                )
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "find_by_filename":
                results = mg_server.find_notes_by_filename_pattern(arguments["pattern"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "search_content":
                results = mg_server.search_note_content(arguments["query"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "search_notes":
                # Keep for backwards compatibility, redirects to filename search
                results = mg_server.find_notes_by_filename_pattern(arguments["query"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "get_backlinks":
                results = mg_server.get_backlinks(arguments["note_path"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "get_related":
                results = mg_server.get_related(arguments["note_path"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "get_note_context":
                results = mg_server.get_note_context(arguments["note_path"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "find_by_tag":
                results = mg_server.find_by_tag(arguments["tag"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "find_by_mention":
                results = mg_server.find_by_mention(arguments["person"])
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "list_all_tags":
                results = mg_server.get_all_tags()
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "list_all_persons":
                results = mg_server.get_all_persons()
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "query_graph":
                results = mg_server.query(
                    arguments["cypher"],
                    arguments.get("params", {})
                )
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "get_graph_stats":
                results = mg_server.get_graph_stats()
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            elif name == "reindex_notes":
                results = mg_server.reindex_all_notes()
                return [TextContent(type="text", text=json.dumps(results, indent=2))]

            else:
                return [TextContent(type="text", text=f"Unknown tool: {name}")]

        except Exception as e:
            return [TextContent(type="text", text=f"Error: {str(e)}")]

    @server.list_resources()
    async def list_resources() -> list[Resource]:
        # List available note files as resources
        resources = []
        try:
            notes_path = Path(mg_server.notes_root)
            for md_file in notes_path.rglob("*.md"):
                rel_path = md_file.relative_to(notes_path)
                resources.append(Resource(
                    uri=f"note://{rel_path}",
                    name=str(rel_path),
                    description=f"Markdown note: {rel_path}",
                    mimeType="text/markdown"
                ))
        except Exception:
            pass
        return resources[:50]  # Limit to 50 resources

    @server.list_resource_templates()
    async def list_resource_templates() -> list[ResourceTemplate]:
        return [
            ResourceTemplate(
                uriTemplate="note://{path}",
                name="Note file",
                description="Read a markdown note file by path"
            )
        ]

    @server.read_resource()
    async def read_resource(uri: str) -> str:
        if uri.startswith("note://"):
            note_path = uri[7:]  # Remove "note://" prefix
            content = mg_server.read_note_content(note_path)
            return content
        return f"Unknown resource: {uri}"

    return server


async def main():
    if not HAS_MCP:
        print("MCP SDK not installed. Install with: pip install mcp", file=sys.stderr)
        sys.exit(1)

    if not HAS_MGCLIENT:
        print("Warning: pymgclient not installed. Graph queries will fail.", file=sys.stderr)
        print("Install with: pip install pymgclient", file=sys.stderr)

    # Parse configuration from environment
    host = os.environ.get("MEMGRAPH_HOST", "localhost")
    port = int(os.environ.get("MEMGRAPH_PORT", "7687"))
    notes_root = os.environ.get("NOTES_ROOT", os.getcwd())

    # Create server instance
    mg_server = MemgraphNotesServer(host=host, port=port, notes_root=notes_root)

    # Try to connect (will retry on first query if it fails)
    if mg_server.connect():
        print(f"Connected to Memgraph at {host}:{port}", file=sys.stderr)
    else:
        print(f"Warning: Could not connect to Memgraph at {host}:{port}", file=sys.stderr)

    # Create and run MCP server
    server = create_server(mg_server)

    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
