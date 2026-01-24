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
import sys
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


def create_server(mg_server: MemgraphNotesServer) -> Server:
    """Create the MCP server with tools and resources."""
    server = Server("memgraph-notes")

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="search_notes",
                description="Search for notes by title or filename pattern",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Search query to match against note titles"
                        }
                    },
                    "required": ["query"]
                }
            ),
            Tool(
                name="get_backlinks",
                description="Find all notes that link to a specific note (backlinks)",
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
                description="Find notes related to a specific note (sharing tags or mentions)",
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
                description="Get full context for a note including all its relationships (links, backlinks, tags, mentions)",
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
                name="find_by_tag",
                description="Find all notes with a specific hashtag",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "tag": {
                            "type": "string",
                            "description": "Tag name (with or without # prefix)"
                        }
                    },
                    "required": ["tag"]
                }
            ),
            Tool(
                name="find_by_mention",
                description="Find all notes that mention a specific person",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "person": {
                            "type": "string",
                            "description": "Person name (with or without @ prefix)"
                        }
                    },
                    "required": ["person"]
                }
            ),
            Tool(
                name="list_all_tags",
                description="List all tags used in the notes with their usage counts",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
            Tool(
                name="list_all_persons",
                description="List all persons mentioned in notes",
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
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        try:
            if name == "search_notes":
                results = mg_server.search_notes(arguments["query"])
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
