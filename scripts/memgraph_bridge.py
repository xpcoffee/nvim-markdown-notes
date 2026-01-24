#!/usr/bin/env python3
"""
Memgraph Bridge for nvim-markdown-notes

This script acts as a bridge between Neovim (Lua) and Memgraph database.
It communicates via JSON over stdin/stdout and uses the Bolt protocol
to connect to Memgraph.

Usage:
    python3 memgraph_bridge.py

Protocol:
    Input: JSON objects, one per line
    Output: JSON objects, one per line

Actions:
    - connect: Establish connection to Memgraph
    - health_check: Check if connection is alive
    - update_note: Update a note and its relationships in the graph
    - delete_note: Remove a note and its relationships from the graph
    - query: Execute a Cypher query
    - reindex: Rebuild the entire graph from scratch
"""

import json
import sys
import hashlib
import os
from datetime import datetime
from typing import Optional, Any


# Try to import mgclient (Memgraph client)
try:
    import mgclient
    HAS_MGCLIENT = True
except ImportError:
    HAS_MGCLIENT = False


class MemgraphBridge:
    def __init__(self):
        self.connection: Optional[Any] = None
        self.host: str = "localhost"
        self.port: int = 7687

    def send_response(self, success: bool, data: Any = None, error: str = None):
        """Send a JSON response to stdout."""
        response = {
            "success": success,
            "data": data,
            "error": error
        }
        print(json.dumps(response), flush=True)

    def connect(self, host: str = "localhost", port: int = 7687) -> bool:
        """Establish connection to Memgraph."""
        if not HAS_MGCLIENT:
            self.send_response(False, error="mgclient not installed. Install with: pip install pymgclient")
            return False

        self.host = host
        self.port = port

        try:
            self.connection = mgclient.connect(host=host, port=port)
            self.connection.autocommit = True
            self._ensure_schema()
            self.send_response(True, data={"message": f"Connected to Memgraph at {host}:{port}"})
            return True
        except Exception as e:
            self.connection = None
            self.send_response(False, error=f"Failed to connect: {str(e)}")
            return False

    def _ensure_schema(self):
        """Ensure indexes exist for optimal query performance."""
        if not self.connection:
            return

        cursor = self.connection.cursor()

        # Create indexes for faster lookups
        indexes = [
            "CREATE INDEX ON :Note(path)",
            "CREATE INDEX ON :Note(filename)",
            "CREATE INDEX ON :Person(name)",
            "CREATE INDEX ON :Tag(name)",
        ]

        for index_query in indexes:
            try:
                cursor.execute(index_query)
            except Exception:
                # Index might already exist
                pass

    def health_check(self) -> bool:
        """Check if connection is alive."""
        if not self.connection:
            self.send_response(False, error="Not connected")
            return False

        try:
            cursor = self.connection.cursor()
            cursor.execute("RETURN 1")
            cursor.fetchall()
            self.send_response(True, data={"status": "healthy"})
            return True
        except Exception as e:
            self.connection = None
            self.send_response(False, error=f"Health check failed: {str(e)}")
            return False

    def _compute_content_hash(self, content: str) -> str:
        """Compute a hash of the content for change detection."""
        return hashlib.md5(content.encode()).hexdigest()

    def update_note(self, path: str, title: str, content: str,
                    wikilinks: list, mentions: list, hashtags: list) -> bool:
        """Update a note and its relationships in the graph."""
        if not self.connection:
            self.send_response(False, error="Not connected")
            return False

        try:
            cursor = self.connection.cursor()
            filename = os.path.basename(path)
            content_hash = self._compute_content_hash(content)
            last_modified = datetime.now().isoformat()

            # Merge the note node
            cursor.execute("""
                MERGE (n:Note {path: $path})
                SET n.title = $title,
                    n.filename = $filename,
                    n.content_hash = $content_hash,
                    n.last_modified = $last_modified
                RETURN n
            """, {
                "path": path,
                "title": title,
                "filename": filename,
                "content_hash": content_hash,
                "last_modified": last_modified
            })

            # Delete existing relationships from this note
            cursor.execute("""
                MATCH (n:Note {path: $path})-[r:LINKS_TO|MENTIONS|HAS_TAG]->()
                DELETE r
            """, {"path": path})

            # Create wikilink relationships
            for link in wikilinks:
                target_path = link.get("target_path")
                line_number = link.get("line_number", 0)
                if target_path:
                    cursor.execute("""
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
                person_name = mention.get("name")
                line_number = mention.get("line_number", 0)
                if person_name:
                    cursor.execute("""
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
                tag_name = tag.get("name")
                line_number = tag.get("line_number", 0)
                if tag_name:
                    cursor.execute("""
                        MATCH (source:Note {path: $source_path})
                        MERGE (tag:Tag {name: $tag_name})
                        MERGE (source)-[r:HAS_TAG {line_number: $line_number}]->(tag)
                    """, {
                        "source_path": path,
                        "tag_name": tag_name,
                        "line_number": line_number
                    })

            # Check if this is a person note (in people directory)
            # and create HAS_NOTE relationship
            if "/people/" in path:
                person_name = os.path.splitext(filename)[0]
                cursor.execute("""
                    MERGE (person:Person {name: $person_name})
                    SET person.display_name = $person_name
                    WITH person
                    MATCH (note:Note {path: $path})
                    MERGE (person)-[:HAS_NOTE]->(note)
                """, {
                    "person_name": person_name,
                    "path": path
                })

            self.send_response(True, data={
                "path": path,
                "wikilinks_count": len(wikilinks),
                "mentions_count": len(mentions),
                "hashtags_count": len(hashtags)
            })
            return True

        except Exception as e:
            self.send_response(False, error=f"Failed to update note: {str(e)}")
            return False

    def delete_note(self, path: str) -> bool:
        """Remove a note and its relationships from the graph."""
        if not self.connection:
            self.send_response(False, error="Not connected")
            return False

        try:
            cursor = self.connection.cursor()

            # Delete the note and all its relationships
            cursor.execute("""
                MATCH (n:Note {path: $path})
                DETACH DELETE n
            """, {"path": path})

            # Clean up orphaned tags and persons (no relationships)
            cursor.execute("""
                MATCH (t:Tag)
                WHERE NOT (t)<-[:HAS_TAG]-()
                DELETE t
            """)

            cursor.execute("""
                MATCH (p:Person)
                WHERE NOT (p)<-[:MENTIONS]-() AND NOT (p)-[:HAS_NOTE]->()
                DELETE p
            """)

            self.send_response(True, data={"deleted": path})
            return True

        except Exception as e:
            self.send_response(False, error=f"Failed to delete note: {str(e)}")
            return False

    def query(self, cypher: str, params: dict = None) -> bool:
        """Execute a Cypher query and return results."""
        if not self.connection:
            self.send_response(False, error="Not connected")
            return False

        try:
            cursor = self.connection.cursor()
            cursor.execute(cypher, params or {})

            # Fetch results
            rows = cursor.fetchall()

            # Convert results to serializable format
            results = []
            for row in rows:
                row_data = []
                for item in row:
                    if hasattr(item, 'properties'):
                        # Node or relationship
                        row_data.append(dict(item.properties))
                    else:
                        row_data.append(item)
                results.append(row_data)

            self.send_response(True, data={"results": results, "count": len(results)})
            return True

        except Exception as e:
            self.send_response(False, error=f"Query failed: {str(e)}")
            return False

    def reindex(self, notes: list) -> bool:
        """Rebuild the entire graph from a list of notes."""
        if not self.connection:
            self.send_response(False, error="Not connected")
            return False

        try:
            cursor = self.connection.cursor()

            # Clear the entire graph
            cursor.execute("MATCH (n) DETACH DELETE n")

            # Re-ensure schema
            self._ensure_schema()

            # Index each note
            indexed = 0
            errors = []

            for note in notes:
                try:
                    path = note.get("path", "")
                    title = note.get("title", "")
                    content = note.get("content", "")
                    wikilinks = note.get("wikilinks", [])
                    mentions = note.get("mentions", [])
                    hashtags = note.get("hashtags", [])

                    # Temporarily suppress individual responses
                    self._update_note_internal(
                        cursor, path, title, content,
                        wikilinks, mentions, hashtags
                    )
                    indexed += 1
                except Exception as e:
                    errors.append({"path": note.get("path", "unknown"), "error": str(e)})

            self.send_response(True, data={
                "indexed": indexed,
                "total": len(notes),
                "errors": errors
            })
            return True

        except Exception as e:
            self.send_response(False, error=f"Reindex failed: {str(e)}")
            return False

    def _update_note_internal(self, cursor, path: str, title: str, content: str,
                               wikilinks: list, mentions: list, hashtags: list):
        """Internal method to update a note without sending response."""
        filename = os.path.basename(path)
        content_hash = self._compute_content_hash(content)
        last_modified = datetime.now().isoformat()

        # Merge the note node
        cursor.execute("""
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
            target_path = link.get("target_path")
            line_number = link.get("line_number", 0)
            if target_path:
                cursor.execute("""
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
            person_name = mention.get("name")
            line_number = mention.get("line_number", 0)
            if person_name:
                cursor.execute("""
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
            tag_name = tag.get("name")
            line_number = tag.get("line_number", 0)
            if tag_name:
                cursor.execute("""
                    MATCH (source:Note {path: $source_path})
                    MERGE (tag:Tag {name: $tag_name})
                    MERGE (source)-[r:HAS_TAG {line_number: $line_number}]->(tag)
                """, {
                    "source_path": path,
                    "tag_name": tag_name,
                    "line_number": line_number
                })

        # Check if this is a person note
        if "/people/" in path:
            person_name = os.path.splitext(filename)[0]
            cursor.execute("""
                MERGE (person:Person {name: $person_name})
                SET person.display_name = $person_name
                WITH person
                MATCH (note:Note {path: $path})
                MERGE (person)-[:HAS_NOTE]->(note)
            """, {
                "person_name": person_name,
                "path": path
            })

    def get_stats(self) -> bool:
        """Get graph statistics."""
        if not self.connection:
            self.send_response(False, error="Not connected")
            return False

        try:
            cursor = self.connection.cursor()

            stats = {}

            # Count nodes by type
            cursor.execute("MATCH (n:Note) RETURN count(n) as count")
            stats["notes"] = cursor.fetchone()[0]

            cursor.execute("MATCH (n:Person) RETURN count(n) as count")
            stats["persons"] = cursor.fetchone()[0]

            cursor.execute("MATCH (n:Tag) RETURN count(n) as count")
            stats["tags"] = cursor.fetchone()[0]

            # Count relationships by type
            cursor.execute("MATCH ()-[r:LINKS_TO]->() RETURN count(r) as count")
            stats["links"] = cursor.fetchone()[0]

            cursor.execute("MATCH ()-[r:MENTIONS]->() RETURN count(r) as count")
            stats["mentions"] = cursor.fetchone()[0]

            cursor.execute("MATCH ()-[r:HAS_TAG]->() RETURN count(r) as count")
            stats["tag_usages"] = cursor.fetchone()[0]

            self.send_response(True, data=stats)
            return True

        except Exception as e:
            self.send_response(False, error=f"Failed to get stats: {str(e)}")
            return False

    def run(self):
        """Main loop: read JSON commands from stdin, execute, respond on stdout."""
        while True:
            try:
                line = sys.stdin.readline()
                if not line:
                    break

                line = line.strip()
                if not line:
                    continue

                try:
                    request = json.loads(line)
                except json.JSONDecodeError as e:
                    self.send_response(False, error=f"Invalid JSON: {str(e)}")
                    continue

                action = request.get("action")
                params = request.get("params", {})

                if action == "connect":
                    self.connect(
                        host=params.get("host", "localhost"),
                        port=params.get("port", 7687)
                    )
                elif action == "health_check":
                    self.health_check()
                elif action == "update_note":
                    self.update_note(
                        path=params.get("path", ""),
                        title=params.get("title", ""),
                        content=params.get("content", ""),
                        wikilinks=params.get("wikilinks", []),
                        mentions=params.get("mentions", []),
                        hashtags=params.get("hashtags", [])
                    )
                elif action == "delete_note":
                    self.delete_note(path=params.get("path", ""))
                elif action == "query":
                    self.query(
                        cypher=params.get("cypher", ""),
                        params=params.get("params", {})
                    )
                elif action == "reindex":
                    self.reindex(notes=params.get("notes", []))
                elif action == "stats":
                    self.get_stats()
                elif action == "quit":
                    break
                else:
                    self.send_response(False, error=f"Unknown action: {action}")

            except Exception as e:
                self.send_response(False, error=f"Unexpected error: {str(e)}")


if __name__ == "__main__":
    bridge = MemgraphBridge()
    bridge.run()
