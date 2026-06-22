#!/usr/bin/env python3
"""
memplato_mobile_server.py
MemPlato Mobile — FastAPI + SQLite + numpy + onnxruntime + MCP SSE
Port: 7333 | Termux Note 10 5G | Python 3.13 | No ChromaDB

FIX v1.0.5: прибрано safe_send workaround — використовується request._send напряму.
            /sse endpoint: connect_sse отримує request._send без обгортки.
            /messages/ endpoint: handle_post_message + явний return Response(202).
"""

import os
import json
import uuid
import time
import sqlite3
import hashlib
import datetime
import asyncio                                    # ← NEW
import warnings
warnings.filterwarnings("ignore")

from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional, List, Any
from concurrent.futures import ThreadPoolExecutor  # ← NEW

import numpy as np
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

# MCP SSE підтримка
from mcp.server import Server
from mcp.server.sse import SseServerTransport
from mcp.types import Tool, TextContent
# ─── CONFIG ──────────────────────────────────────────────────────────────────
BASE_DIR = Path.home() / ".memplato_mobile"
DB_PATH = BASE_DIR / "palace.db"
MODEL_DIR = BASE_DIR / "models" / "onnx"
MODEL_FILE = MODEL_DIR / "model.onnx"
TOKENIZER_FILE = MODEL_DIR / "tokenizer.json"
PORT = 7333
EMBEDDING_DIM = 384

# ─── GLOBALS ─────────────────────────────────────────────────────────────────
_ort_session = None
_executor = ThreadPoolExecutor(max_workers=1)
_hook_settings = {"silent_save": True, "desktop_toast": False}

# ─── DB INIT ─────────────────────────────────────────────────────────────────
def init_db():
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA foreign_keys=ON")
    con.executescript("""
CREATE TABLE IF NOT EXISTS drawers (
    id TEXT PRIMARY KEY,
    wing TEXT NOT NULL,
    room TEXT NOT NULL,
    content TEXT NOT NULL,
    source_file TEXT,
    added_by TEXT DEFAULT 'mcp',
    embedding BLOB,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_drawers_wing ON drawers(wing);
CREATE INDEX IF NOT EXISTS idx_drawers_room ON drawers(room);

CREATE TABLE IF NOT EXISTS kg_facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject TEXT NOT NULL,
    predicate TEXT NOT NULL,
    object TEXT NOT NULL,
    valid_from TEXT,
    valid_to TEXT,
    confidence REAL DEFAULT 1.0,
    source_closet TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_kg_subject ON kg_facts(subject);
CREATE INDEX IF NOT EXISTS idx_kg_object ON kg_facts(object);

CREATE TABLE IF NOT EXISTS diary (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_name TEXT NOT NULL,
    entry TEXT NOT NULL,
    topic TEXT DEFAULT 'general',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tunnels (
    id TEXT PRIMARY KEY,
    source_wing TEXT NOT NULL,
    source_room TEXT NOT NULL,
    target_wing TEXT NOT NULL,
    target_room TEXT NOT NULL,
    label TEXT,
    source_drawer_id TEXT,
    target_drawer_id TEXT,
    created_at TEXT NOT NULL
);
""")
    con.commit()
    # Міграція: додаємо колонки якщо їх немає
    for col in ["source_drawer_id", "target_drawer_id"]:
        try:
            con.execute(f"ALTER TABLE tunnels ADD COLUMN {col} TEXT")
            con.commit()
        except Exception:
            pass
    con.close()


def get_con():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA foreign_keys=ON")
    return con

def now_iso():
    return datetime.datetime.utcnow().isoformat()

# ─── TOKENIZER ───────────────────────────────────────────────────────────────
_vocab: dict = {}

def _load_vocab():
    global _vocab
    try:
        import json as _json
        tj = Path(TOKENIZER_FILE)
        if not tj.exists():
            print("[WARN] tokenizer.json not found, using fallback tokenizer")
            return
        data = _json.loads(tj.read_text(encoding="utf-8"))
        _vocab = data["model"]["vocab"]
        print(f"[OK] Vocab loaded: {len(_vocab)} tokens")
    except Exception as e:
        print(f"[WARN] Failed to load vocab: {e}")

def _wordpiece_tokenize_word(word: str, max_chars: int = 100) -> list:
    if len(word) > max_chars:
        return [100]  # [UNK]
    tokens = []
    start = 0
    while start < len(word):
        end = len(word)
        found = None
        while start < end:
            substr = word[start:end]
            candidate = substr if start == 0 else "##" + substr
            if candidate in _vocab:
                found = _vocab[candidate]
                break
            end -= 1
        if found is None:
            return [100]  # [UNK]
        tokens.append(found)
        start = end
    return tokens

def simple_tokenize(text: str, max_len: int = 128) -> dict:
    if not _vocab:
        # fallback якщо словник не завантажився
        ids = [ord(c) % 30522 for c in text.lower()[:max_len - 2]]
        ids = [101] + ids[:max_len - 2] + [102]
        ids += [0] * (max_len - len(ids))
        mask = [1 if i != 0 else 0 for i in ids]
        return {
            "input_ids": np.array([ids], dtype=np.int64),
            "attention_mask": np.array([mask], dtype=np.int64),
            "token_type_ids": np.array([[0] * max_len], dtype=np.int64),
        }

    # нижній регістр (do_lower_case=true)
    text = text.lower()

    # розбиваємо на слова по пробілах і пунктуації
    import re
    words = re.findall(r'\w+|[^\w\s]', text, re.UNICODE)

    ids = [101]  # [CLS]
    for word in words:
        if len(ids) >= max_len - 1:
            break
        ids.extend(_wordpiece_tokenize_word(word))
    ids = ids[:max_len - 1]
    ids.append(102)  # [SEP]

    # padding до max_len
    mask = [1] * len(ids) + [0] * (max_len - len(ids))
    ids  = ids + [0] * (max_len - len(ids))

    return {
        "input_ids": np.array([ids], dtype=np.int64),
        "attention_mask": np.array([mask], dtype=np.int64),
        "token_type_ids": np.array([[0] * max_len], dtype=np.int64),
    }

def get_embedding(text: str) -> Optional[np.ndarray]:
    if _ort_session is None:
        return None
    try:
        inputs = simple_tokenize(text)
        outputs = _ort_session.run(None, inputs)
        vec = outputs[0][0].mean(axis=0)
        norm = np.linalg.norm(vec)
        if norm > 0:
            vec = vec / norm
        return vec.astype(np.float32)
    except Exception as e:
        print(f"[WARN] Embedding failed: {e}")
        return None

async def get_embedding_async(text: str):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_executor, get_embedding, text)

def vec_to_blob(v: np.ndarray) -> bytes:
    return v.astype(np.float32).tobytes()
def blob_to_vec(b: bytes) -> np.ndarray:
    return np.frombuffer(b, dtype=np.float32)

def cosine_distance(a: np.ndarray, b: np.ndarray) -> float:
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 1.0
    return float(1.0 - np.dot(a, b) / (na * nb))

# ─── EMBEDDING ───────────────────────────────────────────────────────────────
def load_model():
    global _ort_session
    if not MODEL_FILE.exists():
        print(f"[WARN] ONNX model not found at {MODEL_FILE}. Embeddings disabled.")
        return
    try:
        import onnxruntime as ort
        _ort_session = ort.InferenceSession(str(MODEL_FILE))
        print(f"[OK] ONNX model loaded: {MODEL_FILE}")
        _load_vocab()
    except Exception as e:
        print(f"[WARN] Could not load ONNX model: {e}")

# ─── ВНУТРІШНІ ФУНКЦІЇ (для MCP і REST) ──────────────────────────────────────
def _do_search(query: str, wing: str = None, room: str = None,
               limit: int = 5, max_distance: float = 1.5) -> dict:
    con = get_con()
    where, params = [], []
    if wing:
        where.append("wing=?"); params.append(wing)
    if room:
        where.append("room=?"); params.append(room)
    clause = ("WHERE " + " AND ".join(where)) if where else ""

    if _ort_session is not None:
        q_emb = get_embedding(query)
        if q_emb is not None:
            rows = con.execute(
                f"SELECT id, wing, room, content, embedding FROM drawers {clause}",
                params
            ).fetchall()
            con.close()
            results = []
            for r in rows:
                if r["embedding"] is None:
                    continue
                vec = blob_to_vec(r["embedding"])
                dist = cosine_distance(q_emb, vec)
                if dist <= max_distance:
                    results.append({
                        "id": r["id"], "wing": r["wing"], "room": r["room"],
                        "content": r["content"], "distance": round(dist, 4)
                    })
            results.sort(key=lambda x: x["distance"])
            return {"query": query, "mode": "semantic", "results": results[:limit]}

    keywords = query.lower().split()
    fts_where = " AND ".join([f"lower(content) LIKE ?" for _ in keywords])
    fts_params = [f"%{k}%" for k in keywords]
    if clause:
        full_clause = clause + " AND " + fts_where
        full_params = params + fts_params
    else:
        full_clause = "WHERE " + fts_where
        full_params = fts_params
    rows = con.execute(
        f"SELECT id, wing, room, content FROM drawers {full_clause} LIMIT ?",
        full_params + [limit]
    ).fetchall()
    con.close()
    return {
        "query": query, "mode": "fulltext",
        "results": [{"id": r["id"], "wing": r["wing"], "room": r["room"],
                     "content": r["content"], "distance": None} for r in rows]
    }

def _do_add_drawer(wing: str, room: str, content: str,
                   source_file: str = None, added_by: str = "mcp") -> dict:
    if not content.strip():
        return {"error": "content cannot be empty"}
    con = get_con()
    existing = con.execute(
        "SELECT id FROM drawers WHERE wing=? AND room=? AND content=?",
        (wing, room, content)
    ).fetchone()
    if existing:
        con.close()
        return {"status": "duplicate", "existing_id": existing["id"]}
    drawer_id = str(uuid.uuid4())
    emb = get_embedding(content)
    blob = vec_to_blob(emb) if emb is not None else None
    con.execute(
        "INSERT INTO drawers(id,wing,room,content,source_file,added_by,embedding,created_at) VALUES(?,?,?,?,?,?,?,?)",
        (drawer_id, wing, room, content, source_file, added_by, blob, now_iso())
    )
    con.commit()
    con.close()
    return {"status": "saved", "id": drawer_id}

def _do_kg_add(subject: str, predicate: str, obj: str,
               valid_from: str = None, source_closet: str = None) -> dict:
    con = get_con()
    con.execute(
        "INSERT INTO kg_facts(subject,predicate,object,valid_from,source_closet,created_at) VALUES(?,?,?,?,?,?)",
        (subject, predicate, obj, valid_from, source_closet, now_iso())
    )
    con.commit()
    con.close()
    return {"status": "added"}

def _do_kg_query(entity: str, direction: str = "both", as_of: str = None) -> dict:
    con = get_con()
    date_filter = ""
    date_params = []
    if as_of:
        date_filter = " AND (valid_from IS NULL OR valid_from <= ?) AND (valid_to IS NULL OR valid_to >= ?)"
        date_params = [as_of, as_of]
    else:
        date_filter = " AND valid_to IS NULL"

    results = []
    if direction in ("both", "outgoing"):
        rows = con.execute(
            f"SELECT * FROM kg_facts WHERE subject=? {date_filter} ORDER BY created_at",
            [entity] + date_params
        ).fetchall()
        for r in rows:
            d = dict(r)
            d["direction"] = "outgoing"
            results.append(d)
    if direction in ("both", "incoming"):
        rows = con.execute(
            f"SELECT * FROM kg_facts WHERE object=? {date_filter} ORDER BY created_at",
            [entity] + date_params
        ).fetchall()
        for r in rows:
            d = dict(r)
            d["direction"] = "incoming"
            results.append(d)
    con.close()
    return {"entity": entity, "facts": results}

def _do_kg_invalidate(subject: str, predicate: str, obj: str, ended: str = None) -> dict:
    con = get_con()
    end_time = ended or now_iso()
    res = con.execute(
        "UPDATE kg_facts SET valid_to=? WHERE subject=? AND predicate=? AND object=? AND valid_to IS NULL",
        (end_time, subject, predicate, obj)
    )
    con.commit()
    con.close()
    return {"status": "invalidated", "rows_affected": res.rowcount}

def _do_list_drawers(wing: str = None, room: str = None,
                     limit: int = 20, offset: int = 0) -> dict:
    con = get_con()
    where, params = [], []
    if wing:
        where.append("wing=?"); params.append(wing)
    if room:
        where.append("room=?"); params.append(room)
    clause = ("WHERE " + " AND ".join(where)) if where else ""
    rows = con.execute(
        f"SELECT id, wing, room, substr(content,1,120) as preview, created_at FROM drawers {clause} ORDER BY created_at DESC LIMIT ? OFFSET ?",
        params + [limit, offset]
    ).fetchall()
    total = con.execute(f"SELECT COUNT(*) FROM drawers {clause}", params).fetchone()[0]
    con.close()
    return {"total": total, "offset": offset, "drawers": [dict(r) for r in rows]}

def _do_diary_write(agent_name: str, entry: str, topic: str = "general") -> dict:
    con = get_con()
    con.execute(
        "INSERT INTO diary(agent_name,entry,topic,created_at) VALUES(?,?,?,?)",
        (agent_name, entry, topic, now_iso())
    )
    con.commit()
    con.close()
    return {"status": "written"}

def _do_diary_read(agent_name: str, last_n: int = 10) -> dict:
    con = get_con()
    rows = con.execute(
        "SELECT * FROM diary WHERE agent_name=? ORDER BY created_at DESC LIMIT ?",
        (agent_name, last_n)
    ).fetchall()
    con.close()
    return {"agent": agent_name, "entries": [dict(r) for r in rows]}

def _do_status() -> dict:
    con = get_con()
    drawers = con.execute("SELECT COUNT(*) FROM drawers").fetchone()[0]
    wings = con.execute("SELECT COUNT(DISTINCT wing) FROM drawers").fetchone()[0]
    rooms = con.execute("SELECT COUNT(DISTINCT wing||'~'||room) FROM drawers").fetchone()[0]
    kg_active = con.execute("SELECT COUNT(*) FROM kg_facts WHERE valid_to IS NULL").fetchone()[0]
    con.close()
    return {
        "status": "ok",
        "server": "memplato Mobile v1.0.7",
        "drawers": drawers,
        "wings": wings,
        "rooms": rooms,
        "kg_facts_active": kg_active,
        "embeddings": _ort_session is not None,
        "port": PORT
    }

# ─── MCP СЕРВЕР ──────────────────────────────────────────────────────────────
mcp_server = Server("memplato-mobile")

@mcp_server.list_tools()
async def list_mcp_tools():
    return [
        Tool(
            name="memplato_status",
            description="Palace overview — total drawers, wings, rooms",
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
        Tool(
            name="memplato_search",
            description="Semantic search in memplato drawers",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search keywords"},
                    "wing": {"type": "string", "description": "Filter by wing (optional)"},
                    "room": {"type": "string", "description": "Filter by room (optional)"},
                    "limit": {"type": "integer", "description": "Max results", "default": 5},
                    "max_distance": {"type": "number", "description": "Max cosine distance (0-2)", "default": 1.5}
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="memplato_add_drawer",
            description="Save memory/content into memplato",
            inputSchema={
                "type": "object",
                "properties": {
                    "wing": {"type": "string", "description": "Project/category name"},
                    "room": {"type": "string", "description": "Aspect/subcategory"},
                    "content": {"type": "string", "description": "Content to store"},
                    "source_file": {"type": "string", "description": "Source file (optional)"},
                    "added_by": {"type": "string", "description": "Who is filing", "default": "mcp"}
                },
                "required": ["wing", "room", "content"]
            }
        ),
        Tool(
            name="memplato_get_drawer",
            description="Get a single drawer by ID",
            inputSchema={
                "type": "object",
                "properties": {
                    "drawer_id": {"type": "string", "description": "Drawer UUID"}
                },
                "required": ["drawer_id"]
            }
        ),
        Tool(
            name="memplato_list_drawers",
            description="List drawers with optional wing/room filter",
            inputSchema={
                "type": "object",
                "properties": {
                    "wing": {"type": "string", "description": "Filter by wing"},
                    "room": {"type": "string", "description": "Filter by room"},
                    "limit": {"type": "integer", "default": 20},
                    "offset": {"type": "integer", "default": 0}
                }
            }
        ),
        Tool(
            name="memplato_delete_drawer",
            description="Delete a drawer by ID (irreversible)",
            inputSchema={
                "type": "object",
                "properties": {
                    "drawer_id": {"type": "string"}
                },
                "required": ["drawer_id"]
            }
        ),
        Tool(
            name="memplato_kg_add",
            description="Add fact to knowledge graph: subject → predicate → object",
            inputSchema={
                "type": "object",
                "properties": {
                    "subject": {"type": "string"},
                    "predicate": {"type": "string"},
                    "object": {"type": "string"},
                    "valid_from": {"type": "string", "description": "YYYY-MM-DD"},
                    "source_closet": {"type": "string"}
                },
                "required": ["subject", "predicate", "object"]
            }
        ),
        Tool(
            name="memplato_kg_query",
            description="Query knowledge graph for entity relationships",
            inputSchema={
                "type": "object",
                "properties": {
                    "entity": {"type": "string"},
                    "direction": {"type": "string", "default": "both"},
                    "as_of": {"type": "string", "description": "YYYY-MM-DD filter"}
                },
                "required": ["entity"]
            }
        ),
        Tool(
            name="memplato_kg_invalidate",
            description="Mark a KG fact as no longer true",
            inputSchema={
                "type": "object",
                "properties": {
                    "subject": {"type": "string"},
                    "predicate": {"type": "string"},
                    "object": {"type": "string"},
                    "ended": {"type": "string", "description": "YYYY-MM-DD"}
                },
                "required": ["subject", "predicate", "object"]
            }
        ),
        Tool(
            name="memplato_kg_timeline",
            description="Chronological timeline of KG facts for an entity",
            inputSchema={
                "type": "object",
                "properties": {
                    "entity": {"type": "string"}
                }
            }
        ),
        Tool(
            name="memplato_kg_stats",
            description="Knowledge graph statistics",
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
        Tool(
            name="memplato_diary_write",
            description="Write entry to agent diary",
            inputSchema={
                "type": "object",
                "properties": {
                    "agent_name": {"type": "string"},
                    "entry": {"type": "string"},
                    "topic": {"type": "string", "default": "general"}
                },
                "required": ["agent_name", "entry"]
            }
        ),
        Tool(
            name="memplato_diary_read",
            description="Read recent diary entries",
            inputSchema={
                "type": "object",
                "properties": {
                    "agent_name": {"type": "string"},
                    "last_n": {"type": "integer", "default": 10}
                },
                "required": ["agent_name"]
            }
        ),
        Tool(
            name="memplato_list_wings",
            description="List all wings with drawer counts",
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
        Tool(
            name="memplato_list_rooms",
            description="List rooms within a wing or all rooms",
            inputSchema={
                "type": "object",
                "properties": {
                    "wing": {"type": "string"}
                }
            }
        ),
        Tool(
                name="memplato_get_taxonomy",
        description="Full taxonomy: wing → room → drawer count",
                inputSchema={"type": "object", "properties": {}, "required": []}
    ),
    Tool(
        name="memplato_update_drawer",
        description="Update an existing drawer's content and/or metadata (wing, room).",
        inputSchema={
            "type": "object",
            "properties": {
                "drawer_id": {"type": "string", "description": "ID of the drawer to update"},
                "content": {"type": "string", "description": "New content (optional)"},
                "wing": {"type": "string", "description": "New wing (optional)"},
                "room": {"type": "string", "description": "New room (optional)"}
            },
            "required": ["drawer_id"]
        }
    ),
    Tool(
        name="memplato_get_aaak_spec",
        description="Get the AAAK dialect specification — the compressed memory format.",
        inputSchema={"type": "object", "properties": {}, "required": []}
    ),
    Tool(
                name="memplato_hook_settings",
        description="Get or set hook behavior: silent_save and desktop_toast flags.",
        inputSchema={
            "type": "object",
            "properties": {
                "silent_save": {"type": "boolean"},
                "desktop_toast": {"type": "boolean"}
            }
        }
    ),
    Tool(
        name="memplato_check_duplicate",
        description="Check if content already exists in the palace before filing.",
        inputSchema={
            "type": "object",
            "properties": {
                "content": {"type": "string"},
                "threshold": {"type": "number", "default": 0.9}
            },
            "required": ["content"]
        }
    ),
    Tool(
        name="memplato_graph_stats",
        description="Palace graph overview: total rooms, tunnel connections, edges between wings.",
        inputSchema={"type": "object", "properties": {}, "required": []}
    ),
    Tool(
        name="memplato_find_tunnels",
        description="Find rooms that bridge two wings.",
        inputSchema={
            "type": "object",
            "properties": {
                "wing_a": {"type": "string"},
                "wing_b": {"type": "string"}
            }
        }
    ),
    Tool(
                name="memplato_traverse",
        description="Walk the palace graph from a room. Shows connected ideas across wings.",
        inputSchema={
            "type": "object",
            "properties": {
                "start_room": {"type": "string"},
                "max_hops": {"type": "integer", "default": 2}
            },
            "required": ["start_room"]
        }
    ),
    Tool(
        name="memplato_create_tunnel",
        description="Create a cross-wing tunnel linking two palace locations.",
        inputSchema={
            "type": "object",
            "properties": {
                "source_wing": {"type": "string"},
                "source_room": {"type": "string"},
                "target_wing": {"type": "string"},
                "target_room": {"type": "string"},
                "label": {"type": "string"},
                "source_drawer_id": {"type": "string"},
                "target_drawer_id": {"type": "string"}
            },
            "required": ["source_wing", "source_room", "target_wing", "target_room"]
        }
    ),
    Tool(
        name="memplato_list_tunnels",
        description="List all explicit cross-wing tunnels. Optionally filter by wing.",
        inputSchema={
            "type": "object",
            "properties": {
                "wing": {"type": "string"}
            }
        }
    ),
    Tool(
        name="memplato_delete_tunnel",
        description="Delete an explicit tunnel by its ID.",
        inputSchema={
            "type": "object",
            "properties": {
                "tunnel_id": {"type": "string"}
            },
            "required": ["tunnel_id"]
        }
    ),
    Tool(
                name="memplato_follow_tunnels",
        description="Follow tunnels from a room to see what it connects to in other wings.",
        inputSchema={
            "type": "object",
            "properties": {
                "wing": {"type": "string"},
                "room": {"type": "string"}
            },
            "required": ["wing", "room"]
        }
    ),
    Tool(
        name="memplato_memories_filed_away",
        description="Check if a recent palace checkpoint was saved. Returns message count and timestamp.",
        inputSchema={"type": "object", "properties": {}, "required": []}
    ),
    Tool(
        name="memplato_reconnect",
        description="Force reconnect to the palace database. Use after external scripts modified the palace directly.",
        inputSchema={"type": "object", "properties": {}, "required": []}
    ),
    ]

@mcp_server.call_tool()
async def call_mcp_tool(name: str, arguments: dict):
    try:
        if name == "memplato_status":
            result = _do_status()

        elif name == "memplato_search":
            result = _do_search(
                query=arguments["query"],
                wing=arguments.get("wing"),
                room=arguments.get("room"),
                limit=int(arguments.get("limit", 5)),
                max_distance=float(arguments.get("max_distance", 1.5))
            )

        elif name == "memplato_add_drawer":
            result = _do_add_drawer(
                wing=arguments["wing"],
                room=arguments["room"],
                content=arguments["content"],
                source_file=arguments.get("source_file"),
                added_by=arguments.get("added_by", "mcp")
            )

        elif name == "memplato_get_drawer":
            con = get_con()
            row = con.execute(
                "SELECT id,wing,room,content,source_file,added_by,created_at FROM drawers WHERE id=?",
                (arguments["drawer_id"],)
            ).fetchone()
            con.close()
            result = dict(row) if row else {"error": "not found"}

        elif name == "memplato_list_drawers":
            result = _do_list_drawers(
                wing=arguments.get("wing"),
                room=arguments.get("room"),
                limit=int(arguments.get("limit", 20)),
                offset=int(arguments.get("offset", 0))
            )

        elif name == "memplato_delete_drawer":
            con = get_con()
            row = con.execute("SELECT id FROM drawers WHERE id=?", (arguments["drawer_id"],)).fetchone()
            if not row:
                result = {"error": "not found"}
            else:
                con.execute("DELETE FROM drawers WHERE id=?", (arguments["drawer_id"],))
                con.commit()
                result = {"status": "deleted", "id": arguments["drawer_id"]}
            con.close()

        elif name == "memplato_kg_add":
            result = _do_kg_add(
                subject=arguments["subject"],
                predicate=arguments["predicate"],
                obj=arguments["object"],
                valid_from=arguments.get("valid_from"),
                source_closet=arguments.get("source_closet")
            )

        elif name == "memplato_kg_query":
            result = _do_kg_query(
                entity=arguments["entity"],
                direction=arguments.get("direction", "both"),
                as_of=arguments.get("as_of")
            )

        elif name == "memplato_kg_invalidate":
            result = _do_kg_invalidate(
                subject=arguments["subject"],
                predicate=arguments["predicate"],
                obj=arguments["object"],
                ended=arguments.get("ended")
            )

        elif name == "memplato_kg_timeline":
            con = get_con()
            entity = arguments.get("entity")
            if entity:
                rows = con.execute(
                    "SELECT * FROM kg_facts WHERE subject=? OR object=? ORDER BY created_at",
                    (entity, entity)
                ).fetchall()
            else:
                rows = con.execute("SELECT * FROM kg_facts ORDER BY created_at").fetchall()
            con.close()
            result = {"entity": entity, "timeline": [dict(r) for r in rows]}

        elif name == "memplato_kg_stats":
            con = get_con()
            total = con.execute("SELECT COUNT(*) FROM kg_facts").fetchone()[0]
            active = con.execute("SELECT COUNT(*) FROM kg_facts WHERE valid_to IS NULL").fetchone()[0]
            entities = con.execute("SELECT COUNT(DISTINCT subject) FROM kg_facts").fetchone()[0]
            rels = con.execute("SELECT COUNT(DISTINCT predicate) FROM kg_facts").fetchone()[0]
            con.close()
            result = {"total": total, "active": active, "expired": total - active,
                      "entities": entities, "relationship_types": rels}

        elif name == "memplato_diary_write":
            result = _do_diary_write(
                agent_name=arguments["agent_name"],
                entry=arguments["entry"],
                topic=arguments.get("topic", "general")
            )

        elif name == "memplato_diary_read":
            result = _do_diary_read(
                agent_name=arguments["agent_name"],
                last_n=int(arguments.get("last_n", 10))
            )

        elif name == "memplato_list_wings":
            con = get_con()
            rows = con.execute(
                "SELECT wing, COUNT(*) as cnt FROM drawers GROUP BY wing ORDER BY wing"
            ).fetchall()
            con.close()
            result = {"wings": [{"wing": r["wing"], "drawers": r["cnt"]} for r in rows]}

        elif name == "memplato_list_rooms":
            con = get_con()
            wing = arguments.get("wing")
            if wing:
                rows = con.execute(
                    "SELECT room, COUNT(*) as cnt FROM drawers WHERE wing=? GROUP BY room ORDER BY room",
                    (wing,)
                ).fetchall()
            else:
                rows = con.execute(
                    "SELECT wing, room, COUNT(*) as cnt FROM drawers GROUP BY wing, room ORDER BY wing, room"
                ).fetchall()
            con.close()
            result = {"rooms": [dict(r) for r in rows]}

        elif name == "memplato_get_taxonomy":
            con = get_con()
            rows = con.execute(
                "SELECT wing, room, COUNT(*) as cnt FROM drawers GROUP BY wing, room ORDER BY wing, room"
            ).fetchall()
            con.close()
            taxonomy = {}
            for r in rows:
                if r["wing"] not in taxonomy:
                    taxonomy[r["wing"]] = {}
                taxonomy[r["wing"]][r["room"]] = r["cnt"]
            result = {"taxonomy": taxonomy}

        elif name == "memplato_update_drawer":
            con = get_con()
            row = con.execute("SELECT * FROM drawers WHERE id=?", (arguments["drawer_id"],)).fetchone()
            if not row:
                con.close()
                result = {"error": "not found"}
            else:
                new_content = arguments.get("content") or row["content"]
                new_wing = arguments.get("wing") or row["wing"]
                new_room = arguments.get("room") or row["room"]
                emb = get_embedding(new_content) if arguments.get("content") else None
                blob = vec_to_blob(emb) if emb is not None else row["embedding"]
                con.execute(
                    "UPDATE drawers SET wing=?, room=?, content=?, embedding=? WHERE id=?",
                    (new_wing, new_room, new_content, blob, arguments["drawer_id"])
                )
                con.commit()
                result = {"status": "updated", "id": arguments["drawer_id"]}
            con.close()

        elif name == "memplato_get_aaak_spec":
            result = {
                "spec": "AAAK v1 — compressed memory dialect. Key patterns: SESSION:date|actions|ALC.req:notes|★★★. Entity codes: USR=user, AGT=agent, PRJ=project, SYS=system. Emotions: ★=notable, ✓=done, ✗=failed, ⚡=urgent, ♻=recurring."
            }

        elif name == "memplato_hook_settings":
            global _hook_settings
            if "silent_save" in arguments:
                _hook_settings["silent_save"] = bool(arguments["silent_save"])
            if "desktop_toast" in arguments:
                _hook_settings["desktop_toast"] = bool(arguments["desktop_toast"])
            result = _hook_settings

        elif name == "memplato_check_duplicate":
            content = arguments["content"]
            threshold = float(arguments.get("threshold", 0.9))
            con = get_con()

            # Early exit: якщо база порожня — не витрачаємо час на embedding
            count = con.execute("SELECT COUNT(*) FROM drawers").fetchone()[0]
            if count == 0:
                con.close()
                result = {"is_duplicate": False, "best_similarity": 0.0}
            else:
                emb = await get_embedding_async(content)
                if emb is None:
                    existing = con.execute(
                        "SELECT id, wing, room FROM drawers WHERE content=?", (content,)
                    ).fetchone()
                    con.close()
                    if existing:
                        result = {"is_duplicate": True, "similarity": 1.0,
                                  "existing_id": existing["id"],
                                  "wing": existing["wing"], "room": existing["room"]}
                    else:
                        result = {"is_duplicate": False}
                else:
                    rows = [(r["id"], r["wing"], r["room"], r["content"], r["embedding"])
                            for r in con.execute(
                            "SELECT id, wing, room, content, embedding FROM drawers"
                        ).fetchall()]
                    con.close()
                    best_sim, best_row = 0.0, None
                    for row_id, row_wing, row_room, row_content, row_emb in rows:
                        if row_emb is None:
                            continue
                        vec = blob_to_vec(row_emb)
                        sim = max(0.0, min(1.0, 1.0 - cosine_distance(emb, vec)))
                        if sim > best_sim:
                            best_sim = sim
                            best_row = (row_id, row_wing, row_room, row_content)
                    if best_row and best_sim >= threshold:
                        row_id, row_wing, row_room, row_content = best_row
                        words_new = set(content.lower().split())
                        words_stored = set(row_content.lower().split())
                        if len(words_new) < 10 and len(words_stored) < 10:
                            union = words_new | words_stored
                            jaccard = len(words_new & words_stored) / len(union) if union else 0.0
                            is_dup = jaccard >= 0.68
                        else:
                            is_dup = True
                        result = {
                            "is_duplicate": is_dup,
                            "similarity": round(best_sim, 4),
                            "existing_id": row_id if is_dup else None,
                            "wing": row_wing if is_dup else None,
                            "room": row_room if is_dup else None
                        }
                    else:
                        result = {"is_duplicate": False, "best_similarity": round(best_sim, 4)}

        elif name == "memplato_graph_stats":
            con = get_con()
            total_rooms = con.execute(
                "SELECT COUNT(DISTINCT wing||'~'||room) FROM drawers"
            ).fetchone()[0]
            total_wings = con.execute("SELECT COUNT(DISTINCT wing) FROM drawers").fetchone()[0]
            total_tunnels = con.execute("SELECT COUNT(*) FROM tunnels").fetchone()[0]
            wing_pairs = con.execute(
                "SELECT source_wing, target_wing, COUNT(*) as cnt FROM tunnels GROUP BY source_wing, target_wing"
            ).fetchall()
            con.close()
            result = {
                "total_rooms": total_rooms,
                "total_wings": total_wings,
                "total_tunnels": total_tunnels,
                "wing_connections": [dict(r) for r in wing_pairs]
            }

        elif name == "memplato_find_tunnels":
            wing_a = arguments.get("wing_a")
            wing_b = arguments.get("wing_b")
            con = get_con()
            if wing_a and wing_b:
                rows = con.execute(
                    "SELECT * FROM tunnels WHERE (source_wing=? AND target_wing=?) OR (source_wing=? AND target_wing=?) ORDER BY created_at",
                    (wing_a, wing_b, wing_b, wing_a)
                ).fetchall()
            elif wing_a:
                rows = con.execute(
                    "SELECT * FROM tunnels WHERE source_wing=? OR target_wing=? ORDER BY created_at",
                    (wing_a, wing_a)
                ).fetchall()
            else:
                rows = con.execute("SELECT * FROM tunnels ORDER BY created_at").fetchall()
            con.close()
            result = {"tunnels": [dict(r) for r in rows]}

        elif name == "memplato_traverse":
            start_room = arguments["start_room"]
            max_hops = int(arguments.get("max_hops", 2))
            con = get_con()
            visited_rooms = set()
            current_rooms = [start_room]
            all_nodes = []
            current_hop = 0
            while current_rooms and current_hop < max_hops:
                next_rooms = []
                for room in current_rooms:
                    if room in visited_rooms:
                        continue
                    visited_rooms.add(room)
                    drawers = con.execute(
                        "SELECT id, wing, room, substr(content,1,100) as preview FROM drawers WHERE room=?",
                        (room,)
                    ).fetchall()
                    tunnels = con.execute(
                        "SELECT * FROM tunnels WHERE source_room=? OR target_room=?",
                        (room, room)
                    ).fetchall()
                    connected = []
                    for t in tunnels:
                        next_room = t["target_room"] if t["source_room"] == room else t["source_room"]
                        connected.append({"room": next_room, "label": t["label"]})
                        next_rooms.append(next_room)
                    all_nodes.append({
                        "hop": current_hop,
                        "room": room,
                        "drawers": [dict(d) for d in drawers],
                        "connected_to": connected
                    })
                current_rooms = next_rooms
                current_hop += 1
            con.close()
            result = {"start_room": start_room, "nodes": all_nodes}

        elif name == "memplato_create_tunnel":
            tunnel_id = str(uuid.uuid4())
            con = get_con()
            con.execute(
                "INSERT INTO tunnels(id,source_wing,source_room,target_wing,target_room,label,source_drawer_id,target_drawer_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                (tunnel_id, arguments["source_wing"], arguments["source_room"],
                 arguments["target_wing"], arguments["target_room"],
                 arguments.get("label"), arguments.get("source_drawer_id"),
                 arguments.get("target_drawer_id"), now_iso())
            )
            con.commit()
            con.close()
            result = {"status": "created", "id": tunnel_id}

        elif name == "memplato_list_tunnels":
            con = get_con()
            wing = arguments.get("wing")
            if wing:
                rows = con.execute(
                    "SELECT * FROM tunnels WHERE source_wing=? OR target_wing=? ORDER BY created_at",
                    (wing, wing)
                ).fetchall()
            else:
                rows = con.execute("SELECT * FROM tunnels ORDER BY created_at").fetchall()
            con.close()
            result = {"tunnels": [dict(r) for r in rows]}

        elif name == "memplato_delete_tunnel":
            con = get_con()
            row = con.execute("SELECT id FROM tunnels WHERE id=?", (arguments["tunnel_id"],)).fetchone()
            if not row:
                result = {"error": "tunnel not found"}
            else:
                con.execute("DELETE FROM tunnels WHERE id=?", (arguments["tunnel_id"],))
                con.commit()
                result = {"status": "deleted", "id": arguments["tunnel_id"]}
            con.close()

        elif name == "memplato_follow_tunnels":
            wing = arguments["wing"]
            room = arguments["room"]
            con = get_con()
            rows = con.execute(
                "SELECT * FROM tunnels WHERE (source_wing=? AND source_room=?) OR (target_wing=? AND target_room=?)",
                (wing, room, wing, room)
            ).fetchall()
            connected = []
            for t in rows:
                if t["source_room"] == room and t["source_wing"] == wing:
                    other_wing, other_room = t["target_wing"], t["target_room"]
                else:
                    other_wing, other_room = t["source_wing"], t["source_room"]
                drawers = con.execute(
                    "SELECT id, substr(content,1,100) as preview FROM drawers WHERE wing=? AND room=?",
                    (other_wing, other_room)
                ).fetchall()
                connected.append({
                    "wing": other_wing,
                    "room": other_room,
                    "label": t["label"],
                    "drawers": [dict(d) for d in drawers]
                })
            con.close()
            result = {"wing": wing, "room": room, "connected": connected}

        elif name == "memplato_memories_filed_away":
            con = get_con()
            last = con.execute(
                "SELECT created_at FROM drawers ORDER BY created_at DESC LIMIT 1"
            ).fetchone()
            count = con.execute("SELECT COUNT(*) FROM drawers").fetchone()[0]
            con.close()
            result = {
                "status": "ok",
                "total_drawers": count,
                "last_saved": last["created_at"] if last else None
            }

        elif name == "memplato_reconnect":
            try:
                con = get_con()
                con.execute("SELECT 1")
                con.close()
                result = {"status": "reconnected", "db": str(DB_PATH)}
            except Exception as e:
                result = {"status": "error", "message": str(e)}

        else:
            result = {"error": f"Unknown tool: {name}"}

        return [TextContent(type="text", text=json.dumps(result, ensure_ascii=False, default=str))]

    except Exception as e:
        return [TextContent(type="text", text=json.dumps({"error": str(e)}))]

# ─── LIFESPAN ────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    load_model()
    print(f"[OK] memplato Mobile v1.0.7 running on port {PORT}")
    yield

app = FastAPI(title="memplato Mobile", version="1.0.7", lifespan=lifespan)

# ─── MCP SSE ENDPOINTS ───────────────────────────────────────────────────────
# FIX v1.0.5: використовуємо request._send напряму, без safe_send обгортки.
# /messages/ повертає явний Response(202) щоб FastAPI не відправляв свою відповідь.
sse_transport = SseServerTransport("/messages/")

# FIX v1.0.5: NoResponse — MCP вже відправив відповідь через request._send.
# FastAPI після завершення функції намагається відправити СВОЮ відповідь поверх.
# NoResponse.__call__ робить нічого — блокує цю другу відповідь на рівні Python.
class NoResponse(Response):
    async def __call__(self, scope, receive, send):
        pass  # Навмисно нічого не робимо


@app.get("/sse")
async def sse_endpoint(request: Request):
    async with sse_transport.connect_sse(
        request.scope, request.receive, request._send
    ) as streams:
        await mcp_server.run(
            streams[0], streams[1],
            mcp_server.create_initialization_options()
        )
    return NoResponse()


@app.post("/messages/")
async def messages_endpoint(request: Request):
    await sse_transport.handle_post_message(
        request.scope, request.receive, request._send
    )
    return NoResponse()

# ─── PYDANTIC MODELS ─────────────────────────────────────────────────────────
class DrawerIn(BaseModel):
    wing: str
    room: str
    content: str
    source_file: Optional[str] = None
    added_by: Optional[str] = "mcp"

class DrawerUpdate(BaseModel):
    wing: Optional[str] = None
    room: Optional[str] = None
    content: Optional[str] = None

class KgFactIn(BaseModel):
    subject: str
    predicate: str
    object: str
    valid_from: Optional[str] = None
    source_closet: Optional[str] = None

class KgInvalidate(BaseModel):
    subject: str
    predicate: str
    object: str
    ended: Optional[str] = None

class DiaryIn(BaseModel):
    agent_name: str
    entry: str
    topic: Optional[str] = "general"

class TunnelIn(BaseModel):
    source_wing: str
    source_room: str
    target_wing: str
    target_room: str
    label: Optional[str] = None
    source_drawer_id: Optional[str] = None
    target_drawer_id: Optional[str] = None

class SearchIn(BaseModel):
    query: str
    wing: Optional[str] = None
    room: Optional[str] = None
    limit: Optional[int] = 5
    max_distance: Optional[float] = 1.5

# ─── STATUS ──────────────────────────────────────────────────────────────────
@app.get("/")
def status():
    return _do_status()

@app.get("/health")
def health():
    return {"status": "ok"}

# ─── WINGS ───────────────────────────────────────────────────────────────────
@app.get("/wings")
def list_wings():
    con = get_con()
    rows = con.execute(
        "SELECT wing, COUNT(*) as cnt FROM drawers GROUP BY wing ORDER BY wing"
    ).fetchall()
    con.close()
    return {"wings": [{"wing": r["wing"], "drawers": r["cnt"]} for r in rows]}

# ─── ROOMS ───────────────────────────────────────────────────────────────────
@app.get("/rooms")
def list_rooms(wing: Optional[str] = Query(default=None)):
    con = get_con()
    if wing:
        rows = con.execute(
            "SELECT room, COUNT(*) as cnt FROM drawers WHERE wing=? GROUP BY room ORDER BY room",
            (wing,)
        ).fetchall()
    else:
        rows = con.execute(
            "SELECT wing, room, COUNT(*) as cnt FROM drawers GROUP BY wing, room ORDER BY wing, room"
        ).fetchall()
    con.close()
    return {"rooms": [dict(r) for r in rows]}

# ─── DRAWERS ─────────────────────────────────────────────────────────────────
@app.get("/drawers")
def list_drawers(
    wing: Optional[str] = Query(default=None),
    room: Optional[str] = Query(default=None),
    limit: int = Query(default=20),
    offset: int = Query(default=0)
):
    return _do_list_drawers(wing, room, limit, offset)

@app.post("/drawers")
def add_drawer(d: DrawerIn):
    result = _do_add_drawer(d.wing, d.room, d.content, d.source_file, d.added_by)
    if "error" in result:
        raise HTTPException(400, result["error"])
    return result

@app.get("/drawers/{drawer_id}")
def get_drawer(drawer_id: str):
    con = get_con()
    row = con.execute(
        "SELECT id,wing,room,content,source_file,added_by,created_at FROM drawers WHERE id=?",
        (drawer_id,)
    ).fetchone()
    con.close()
    if not row:
        raise HTTPException(404, "Drawer not found")
    return dict(row)

@app.patch("/drawers/{drawer_id}")
def update_drawer(drawer_id: str, upd: DrawerUpdate):
    con = get_con()
    row = con.execute("SELECT * FROM drawers WHERE id=?", (drawer_id,)).fetchone()
    if not row:
        con.close()
        raise HTTPException(404, "Drawer not found")
    new_content = upd.content if upd.content is not None else row["content"]
    new_wing = upd.wing if upd.wing is not None else row["wing"]
    new_room = upd.room if upd.room is not None else row["room"]
    emb = get_embedding(new_content) if upd.content else None
    blob = vec_to_blob(emb) if emb is not None else row["embedding"]
    con.execute(
        "UPDATE drawers SET wing=?, room=?, content=?, embedding=? WHERE id=?",
        (new_wing, new_room, new_content, blob, drawer_id)
    )
    con.commit()
    con.close()
    return {"status": "updated", "id": drawer_id}

@app.delete("/drawers/{drawer_id}")
def delete_drawer(drawer_id: str):
    con = get_con()
    row = con.execute("SELECT id FROM drawers WHERE id=?", (drawer_id,)).fetchone()
    if not row:
        con.close()
        raise HTTPException(404, "Drawer not found")
    con.execute("DELETE FROM drawers WHERE id=?", (drawer_id,))
    con.commit()
    con.close()
    return {"status": "deleted", "id": drawer_id}

# ─── SEARCH ──────────────────────────────────────────────────────────────────
@app.post("/search")
def search(s: SearchIn):
    return _do_search(s.query, s.wing, s.room, s.limit, s.max_distance)

# ─── KNOWLEDGE GRAPH ─────────────────────────────────────────────────────────
@app.post("/kg/add")
def kg_add(f: KgFactIn):
    return _do_kg_add(f.subject, f.predicate, f.object, f.valid_from, f.source_closet)

@app.get("/kg/query")
def kg_query(
    entity: str = Query(...),
    direction: Optional[str] = Query(default="both"),
    as_of: Optional[str] = Query(default=None)
):
    return _do_kg_query(entity, direction, as_of)

@app.post("/kg/invalidate")
def kg_invalidate(inv: KgInvalidate):
    return _do_kg_invalidate(inv.subject, inv.predicate, inv.object, inv.ended)

@app.get("/kg/timeline")
def kg_timeline(entity: Optional[str] = Query(default=None)):
    con = get_con()
    if entity:
        rows = con.execute(
            "SELECT * FROM kg_facts WHERE subject=? OR object=? ORDER BY created_at",
            (entity, entity)
        ).fetchall()
    else:
        rows = con.execute("SELECT * FROM kg_facts ORDER BY created_at").fetchall()
    con.close()
    return {"entity": entity, "timeline": [dict(r) for r in rows]}

@app.get("/kg/stats")
def kg_stats():
    con = get_con()
    total = con.execute("SELECT COUNT(*) FROM kg_facts").fetchone()[0]
    active = con.execute("SELECT COUNT(*) FROM kg_facts WHERE valid_to IS NULL").fetchone()[0]
    expired = total - active
    entities = con.execute("SELECT COUNT(DISTINCT subject) FROM kg_facts").fetchone()[0]
    rels = con.execute("SELECT COUNT(DISTINCT predicate) FROM kg_facts").fetchone()[0]
    con.close()
    return {"total": total, "active": active, "expired": expired,
            "entities": entities, "relationship_types": rels}

# ─── DIARY ───────────────────────────────────────────────────────────────────
@app.post("/diary/write")
def diary_write(d: DiaryIn):
    return _do_diary_write(d.agent_name, d.entry, d.topic)

@app.get("/diary/read")
def diary_read(
    agent_name: str = Query(...),
    last_n: int = Query(default=10)
):
    return _do_diary_read(agent_name, last_n)

# ─── TUNNELS ─────────────────────────────────────────────────────────────────
@app.post("/tunnels")
def create_tunnel(t: TunnelIn):
    con = get_con()
    tunnel_id = str(uuid.uuid4())
    con.execute(
        "INSERT INTO tunnels(id,source_wing,source_room,target_wing,target_room,label,source_drawer_id,target_drawer_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
        (tunnel_id, t.source_wing, t.source_room, t.target_wing, t.target_room,
         t.label, t.source_drawer_id, t.target_drawer_id, now_iso())
    )
    con.commit()
    con.close()
    return {"status": "created", "id": tunnel_id}

@app.get("/tunnels")
def list_tunnels(wing: Optional[str] = Query(default=None)):
    con = get_con()
    if wing:
        rows = con.execute(
            "SELECT * FROM tunnels WHERE source_wing=? OR target_wing=? ORDER BY created_at",
            (wing, wing)
        ).fetchall()
    else:
        rows = con.execute("SELECT * FROM tunnels ORDER BY created_at").fetchall()
    con.close()
    return {"tunnels": [dict(r) for r in rows]}

@app.delete("/tunnels/{tunnel_id}")
def delete_tunnel(tunnel_id: str):
    con = get_con()
    row = con.execute("SELECT id FROM tunnels WHERE id=?", (tunnel_id,)).fetchone()
    if not row:
        con.close()
        raise HTTPException(404, "Tunnel not found")
    con.execute("DELETE FROM tunnels WHERE id=?", (tunnel_id,))
    con.commit()
    con.close()
    return {"status": "deleted", "id": tunnel_id}

# ─── TAXONOMY ────────────────────────────────────────────────────────────────
@app.get("/taxonomy")
def get_taxonomy():
    con = get_con()
    rows = con.execute(
        "SELECT wing, room, COUNT(*) as cnt FROM drawers GROUP BY wing, room ORDER BY wing, room"
    ).fetchall()
    con.close()
    taxonomy = {}
    for r in rows:
        if r["wing"] not in taxonomy:
            taxonomy[r["wing"]] = {}
        taxonomy[r["wing"]][r["room"]] = r["cnt"]
    return {"taxonomy": taxonomy}

# ─── WAL CHECKPOINT ──────────────────────────────────────────────────────────
@app.post("/checkpoint")
def checkpoint():
    con = get_con()
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.commit()
    con.close()
    return {"status": "checkpoint done"}

# ============================================================
# STREAMABLE HTTP MCP (for Claude.ai / Perplexity web)
# POST /mcp  ->  handles JSON-RPC directly, returns JSON
# ============================================================
from fastapi.responses import StreamingResponse as SR
import asyncio

@app.post("/mcp")
async def mcp_streamable_http(request: Request):
    body = await request.json()
    method = body.get("method", "")
    req_id = body.get("id")
    params = body.get("params", {})

    # --- initialize ---
    if method == "initialize":
        result = {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "memplato-mobile", "version": "1.0.7"}
        }

    # --- tools/list ---
    elif method == "tools/list":
        tools_list = await list_mcp_tools()
        result = {"tools": [
            {
                "name": t.name,
                "description": t.description or "",
                "inputSchema": t.inputSchema
            }
            for t in tools_list
        ]}

    # --- tools/call ---
    elif method == "tools/call":
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})
        content = await call_mcp_tool(tool_name, arguments)
        result = {
            "content": [{"type": "text", "text": c.text} for c in content]
        }

    # --- notifications (ignore) ---
    elif method.startswith("notifications/"):
        return Response(status_code=202)

    else:
        return JSONResponse({
            "jsonrpc": "2.0", "id": req_id,
            "error": {"code": -32601, "message": f"Method not found: {method}"}
        })

    return JSONResponse({
        "jsonrpc": "2.0",
        "id": req_id,
        "result": result
    })

# ─── RUN ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)