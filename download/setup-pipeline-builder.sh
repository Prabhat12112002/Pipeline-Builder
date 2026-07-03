#!/usr/bin/env bash
# =====================================================================
# Pipeline Builder — one-shot setup script
# ---------------------------------------------------------------------
# Creates the entire project (frontend + backend) in a folder called
# `pipeline-builder/` in the current directory.
#
# USAGE:
#   1. Save this file as setup-pipeline-builder.sh
#   2. bash setup-pipeline-builder.sh
#   3. cd pipeline-builder
#   4. Follow the README to install + run
#
# Safe to re-run — existing files are overwritten.
# =====================================================================
set -euo pipefail

ROOT="pipeline-builder"
echo "▶ Creating project in ./$ROOT ..."
mkdir -p "$ROOT"/{backend,frontend/public,frontend/src/{components,nodes,store,styles}}

# ---------------------------------------------------------------------
# README.md
# ---------------------------------------------------------------------
cat > "$ROOT/README.md" <<'EOF_README'
# Pipeline Builder

A visual node-based pipeline editor built with **React + React Flow** (frontend)
and **FastAPI** (backend). Drag nodes onto a canvas, connect them, and submit the
pipeline to the backend for structural analysis (node count, edge count, DAG check).

## Quick start

### Backend
```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### Frontend (new terminal)
```bash
cd frontend
npm install
npm start
```
Open http://localhost:3000

## Environment variables
- Frontend: `REACT_APP_API_URL` (default http://localhost:8000) — see frontend/.env.example
- Backend:  `ALLOWED_ORIGINS`, `HOST`, `PORT`, `ENABLE_DOCS`, `LOG_LEVEL` — see backend/.env.example

## API
- `GET /health` → `{"status":"ok"}`
- `POST /pipelines/parse` body `{nodes, edges}` → `{num_nodes, num_edges, is_dag}`

## Production
- Frontend: `npm run build` → serve static `build/` folder (set REACT_APP_API_URL first)
- Backend: `gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker` behind nginx
- Run `npm audit` and `pip-audit -r requirements.txt` before launch
- Set ALLOWED_ORIGINS to your frontend URL, ENABLE_DOCS=false in prod
EOF_README

# ---------------------------------------------------------------------
# backend/main.py
# ---------------------------------------------------------------------
cat > "$ROOT/backend/main.py" <<'EOF_MAIN'
"""Pipeline Builder — FastAPI backend.

POST /pipelines/parse  → {num_nodes, num_edges, is_dag}
GET  /health           → {status, service}

DAG check: iterative DFS with WHITE/GRAY/BLACK colouring.
"""
from __future__ import annotations
import logging
import os
from typing import Any, Dict, List
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
)
logger = logging.getLogger("pipeline_builder")

_DEFAULT_ORIGINS = "http://localhost:3000,http://127.0.0.1:3000"
_raw = os.environ.get("ALLOWED_ORIGINS", _DEFAULT_ORIGINS)
ALLOWED_ORIGINS: List[str] = [o.strip() for o in _raw.split(",") if o.strip()]

MAX_NODES = 10_000
MAX_EDGES = 50_000


class PipelineNode(BaseModel):
    id: str
    type: str | None = None
    data: Dict[str, Any] | None = None
    model_config = {"extra": "allow"}

    @field_validator("id")
    @classmethod
    def _id_non_empty(cls, v):
        if not isinstance(v, str) or not v.strip():
            raise ValueError("node 'id' must be a non-empty string")
        return v


class PipelineEdge(BaseModel):
    source: str
    target: str
    id: str | None = None
    model_config = {"extra": "allow"}

    @field_validator("source", "target")
    @classmethod
    def _endpoint_non_empty(cls, v):
        if not isinstance(v, str) or not v.strip():
            raise ValueError("edge 'source'/'target' must be non-empty strings")
        return v


class PipelinePayload(BaseModel):
    nodes: List[PipelineNode] = Field(default_factory=list, max_length=MAX_NODES)
    edges: List[PipelineEdge] = Field(default_factory=list, max_length=MAX_EDGES)


class PipelineAnalysis(BaseModel):
    num_nodes: int
    num_edges: int
    is_dag: bool


class HealthResponse(BaseModel):
    status: str
    service: str


WHITE, GRAY, BLACK = 0, 1, 2


def is_dag(node_ids: List[str], edges: List[PipelineEdge]) -> bool:
    """True iff the directed graph is acyclic. Iterative DFS, 3-colour."""
    id_set = set(node_ids)
    adj: Dict[str, List[str]] = {n: [] for n in node_ids}
    for e in edges:
        if e.source in id_set and e.target in id_set:
            adj[e.source].append(e.target)
    colour = {n: WHITE for n in node_ids}
    for start in node_ids:
        if colour[start] != WHITE:
            continue
        stack = [(start, iter(adj[start]))]
        colour[start] = GRAY
        while stack:
            node, neighbours = stack[-1]
            advanced = False
            for nxt in neighbours:
                if colour[nxt] == GRAY:
                    return False
                if colour[nxt] == WHITE:
                    colour[nxt] = GRAY
                    stack.append((nxt, iter(adj[nxt])))
                    advanced = True
                    break
            if not advanced:
                colour[node] = BLACK
                stack.pop()
    return True


app = FastAPI(
    title="Pipeline Builder API",
    version="1.0.0",
    docs_url="/docs" if os.environ.get("ENABLE_DOCS", "true").lower() == "true" else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)


@app.exception_handler(Exception)
async def _unhandled(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


@app.get("/health", response_model=HealthResponse)
@app.get("/", response_model=HealthResponse)
def health():
    return HealthResponse(status="ok", service="pipeline-builder-api")


@app.post("/pipelines/parse", response_model=PipelineAnalysis)
def parse_pipeline(payload: PipelinePayload):
    node_ids = [n.id for n in payload.nodes]
    try:
        dag = is_dag(node_ids, payload.edges)
    except Exception:
        logger.exception("DAG computation failed")
        raise
    return PipelineAnalysis(
        num_nodes=len(payload.nodes),
        num_edges=len(payload.edges),
        is_dag=dag,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "8000")),
        reload=bool(os.environ.get("RELOAD", "")),
    )
EOF_MAIN

# ---------------------------------------------------------------------
# backend/requirements.txt
# ---------------------------------------------------------------------
cat > "$ROOT/backend/requirements.txt" <<'EOF_REQ'
fastapi==0.128.0
uvicorn[standard]==0.44.0
pydantic==2.12.5
starlette==0.50.0
EOF_REQ

# ---------------------------------------------------------------------
# backend/.env.example
# ---------------------------------------------------------------------
cat > "$ROOT/backend/.env.example" <<'EOF_BENV'
ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
HOST=0.0.0.0
PORT=8000
ENABLE_DOCS=true
LOG_LEVEL=INFO
EOF_BENV

# ---------------------------------------------------------------------
# frontend/package.json
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/package.json" <<'EOF_PKG'
{
  "name": "pipeline-builder-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "reactflow": "^11.11.4",
    "zustand": "^4.5.5"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "devDependencies": {
    "react-scripts": "5.0.1"
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version", "last 1 safari version"]
  }
}
EOF_PKG

# ---------------------------------------------------------------------
# frontend/.env  +  .env.example
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/.env" <<'EOF_FENV'
REACT_APP_API_URL=http://localhost:8000
BROWSER=none
PORT=3000
DISABLE_ESLINT_PLUGIN=true
EOF_FENV

cat > "$ROOT/frontend/.env.example" <<'EOF_FENVEX'
REACT_APP_API_URL=http://localhost:8000
DISABLE_ESLINT_PLUGIN=true
EOF_FENVEX

# ---------------------------------------------------------------------
# frontend/public/index.html
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/public/index.html" <<'EOF_HTML'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#0f172a" />
    <title>Pipeline Builder</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
EOF_HTML

# ---------------------------------------------------------------------
# frontend/src/index.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/index.js" <<'EOF_INDEX'
import React from "react";
import ReactDOM from "react-dom/client";
import "./styles/global.css";
import App from "./App";
import ErrorBoundary from "./components/ErrorBoundary";

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);
EOF_INDEX

# ---------------------------------------------------------------------
# frontend/src/App.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/App.js" <<'EOF_APP'
import React, { useCallback, useRef, useState } from "react";
import ReactFlow, { Background, Controls, MiniMap, ReactFlowProvider } from "reactflow";
import "reactflow/dist/style.css";
import Sidebar from "./components/Sidebar";
import { nodeTypes } from "./nodes";
import { usePipelineStore } from "./store/pipelineStore";
import { submitAndAlert } from "./submit";

const flowStyle = { background: "#0b1220" };

function Builder() {
  const reactFlowWrapper = useRef(null);
  const { nodes, edges, onNodesChange, onEdgesChange, onConnect, addNode } =
    usePipelineStore();
  const [submitting, setSubmitting] = useState(false);

  const onDragOver = useCallback((event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const onDrop = useCallback((event) => {
    event.preventDefault();
    const type = event.dataTransfer.getData("application/reactflow");
    if (!type) return;
    if (!reactFlowWrapper.current) return;
    const bounds = reactFlowWrapper.current.getBoundingClientRect();
    addNode(type, { x: event.clientX - bounds.left, y: event.clientY - bounds.top });
  }, [addNode]);

  const onSubmit = useCallback(async () => {
    setSubmitting(true);
    try { await submitAndAlert(nodes, edges); }
    finally { setSubmitting(false); }
  }, [nodes, edges]);

  return (
    <div className="app-shell">
      <header className="toolbar">
        <div className="toolbar__brand">
          <span className="toolbar__brand-mark">⌁</span>
          Pipeline Builder
          <span className="toolbar__subtitle">visual node editor</span>
        </div>
        <div className="toolbar__actions">
          <span className="status-pill">
            <span className="status-pill__dot" />
            {nodes.length} nodes · {edges.length} edges
          </span>
          <button className="btn btn--primary" onClick={onSubmit} disabled={submitting}>
            {submitting ? (<><span className="spinner" />Analysing…</>)
                        : (<>⚡ Submit Pipeline</>)}
          </button>
        </div>
      </header>
      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        <Sidebar />
        <div className="canvas-wrap" ref={reactFlowWrapper}>
          <ReactFlow
            nodes={nodes} edges={edges}
            onNodesChange={onNodesChange} onEdgesChange={onEdgesChange}
            onConnect={onConnect} nodeTypes={nodeTypes}
            onDrop={onDrop} onDragOver={onDragOver}
            fitView deleteKeyCode={["Backspace", "Delete"]} style={flowStyle}
          >
            <Background color="#334155" gap={20} size={1.5} />
            <Controls />
            <MiniMap
              nodeColor={(n) => ({
                input:"#3b82f6",output:"#10b981",llm:"#8b5cf6",text:"#ec4899",
                timer:"#f59e0b",email:"#ef4444",filter:"#06b6d4",merge:"#84cc16",
                debug:"#64748b",
              }[n.type] || "#6366f1")}
              maskColor="rgba(11,18,32,0.7)" style={{ background: "#0b1220" }}
            />
          </ReactFlow>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (<ReactFlowProvider><Builder /></ReactFlowProvider>);
}
EOF_APP

# ---------------------------------------------------------------------
# frontend/src/submit.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/submit.js" <<'EOF_SUBMIT'
const API_BASE_URL = process.env.REACT_APP_API_URL || "http://localhost:8000";
const ENDPOINT = `${API_BASE_URL}/pipelines/parse`;

export async function submitPipeline(nodes, edges) {
  const payload = {
    nodes: (nodes ?? []).map((n) => ({ id: n.id, type: n.type, data: n.data, position: n.position })),
    edges: (edges ?? []).map((e) => ({
      id: e.id, source: e.source, target: e.target,
      sourceHandle: e.sourceHandle ?? null, targetHandle: e.targetHandle ?? null,
    })),
  };
  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    throw new Error(
      `Could not reach the backend at ${API_BASE_URL}.\n` +
      `Is the FastAPI server running? (cd backend && uvicorn main:app --reload)\n` +
      `Detail: ${err.message}`
    );
  }
  if (!response.ok) {
    let detail = "";
    try {
      const errBody = await response.json();
      detail = Array.isArray(errBody.detail)
        ? errBody.detail.map((d) => d.msg || JSON.stringify(d)).join("; ")
        : errBody.detail || JSON.stringify(errBody);
    } catch (_) { detail = await response.text().catch(() => ""); }
    throw new Error(`Backend returned ${response.status} ${response.statusText}` + (detail ? `\n${detail}` : ""));
  }
  return response.json();
}

export function formatResult(result) {
  const dag = result.is_dag ? "true ✓" : "false ✗";
  return (
    `Pipeline Analysis:\n` +
    `Number of nodes: ${result.num_nodes}\n` +
    `Number of edges: ${result.num_edges}\n` +
    `Is DAG: ${dag}`
  );
}

export async function submitAndAlert(nodes, edges) {
  try {
    const result = await submitPipeline(nodes, edges);
    alert(formatResult(result));
    return result;
  } catch (err) {
    alert(`Failed to parse pipeline:\n${err.message}`);
    throw err;
  }
}
EOF_SUBMIT

# ---------------------------------------------------------------------
# frontend/src/components/Sidebar.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/components/Sidebar.js" <<'EOF_SIDEBAR'
import React from "react";
import { PALETTE } from "../nodes";

export default function Sidebar() {
  const onDragStart = (event, nodeType) => {
    event.dataTransfer.setData("application/reactflow", nodeType);
    event.dataTransfer.effectAllowed = "move";
  };
  return (
    <aside className="sidebar">
      <div className="sidebar__title">Nodes</div>
      {PALETTE.map((node) => (
        <div key={node.type} className="palette-item"
             onDragStart={(e) => onDragStart(e, node.type)} draggable>
          <span className="palette-item__dot" style={{ background: node.color }} />
          <span style={{ flex: 1 }}>{node.title}</span>
          <span className="palette-item__hint">{node.icon}</span>
        </div>
      ))}
      <div style={{ marginTop: 16, padding: "10px 8px", fontSize: 11,
            color: "var(--text-muted)", lineHeight: 1.5,
            borderTop: "1px solid rgba(148,163,184,0.15)" }}>
        Drag a node onto the canvas. Connect handles by dragging from a
        source (right) to a target (left).
      </div>
    </aside>
  );
}
EOF_SIDEBAR

# ---------------------------------------------------------------------
# frontend/src/components/ErrorBoundary.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/components/ErrorBoundary.js" <<'EOF_EB'
import React from "react";

export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }
  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }
  componentDidCatch(error, errorInfo) {
    console.error("Uncaught error:", error, errorInfo);
  }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ height: "100vh", display: "flex", flexDirection: "column",
          alignItems: "center", justifyContent: "center", gap: 16,
          background: "#0f172a", color: "#e2e8f0",
          fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
          padding: 24, textAlign: "center" }}>
          <div style={{ fontSize: 48 }}>⚠️</div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700 }}>Something went wrong</h1>
          <p style={{ margin: 0, color: "#94a3b8", maxWidth: 420 }}>
            An unexpected error occurred. You can try reloading the page.
          </p>
          <button onClick={() => window.location.reload()} style={{
            marginTop: 8, padding: "10px 20px", borderRadius: 10, border: "none",
            background: "linear-gradient(135deg, #6366f1, #8b5cf6)", color: "#fff",
            fontSize: 14, fontWeight: 600, cursor: "pointer" }}>
            Reload page
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
EOF_EB

# ---------------------------------------------------------------------
# frontend/src/store/pipelineStore.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/store/pipelineStore.js" <<'EOF_STORE'
import { create } from "zustand";
import { applyNodeChanges, applyEdgeChanges, addEdge } from "reactflow";
import { defaultNodeData } from "../nodes";

let nodeSeq = 1;

const HANDLE_MAP = {
  input:  { source: true,  target: false },
  output: { source: false, target: true  },
  llm:    { source: true,  target: true  },
  text:   { source: true,  target: true  },
  timer:  { source: true,  target: true  },
  email:  { source: true,  target: true  },
  filter: { source: true,  target: true  },
  merge:  { source: true,  target: true  },
  debug:  { source: true,  target: true  },
};

export const usePipelineStore = create((set, get) => ({
  nodes: [],
  edges: [],
  onNodesChange: (changes) => set({ nodes: applyNodeChanges(changes, get().nodes) }),
  onEdgesChange: (changes) => set({ edges: applyEdgeChanges(changes, get().edges) }),
  onConnect: (conn) => {
    const { nodes } = get();
    const srcNode = nodes.find((n) => n.id === conn.source);
    const tgtNode = nodes.find((n) => n.id === conn.target);
    if (!srcNode || !tgtNode) return;
    if (!HANDLE_MAP[srcNode.type]?.source || !HANDLE_MAP[tgtNode.type]?.target) return;
    set({ edges: addEdge({ ...conn, animated: true }, get().edges) });
  },
  addNode: (type, position) => {
    const id = `${type}_${nodeSeq++}`;
    const node = {
      id, type, position,
      data: {
        ...defaultNodeData(type),
        onChange: (nodeId, key, value) => {
          set({ nodes: get().nodes.map((n) =>
            n.id === nodeId ? { ...n, data: { ...n.data, [key]: value } } : n) });
        },
      },
    };
    set({ nodes: [...get().nodes, node] });
    return id;
  },
  setNodes: (nodes) => set({ nodes }),
  setEdges: (edges) => set({ edges }),
}));

if (typeof window !== "undefined" && process.env.NODE_ENV !== "production") {
  window.__pipelineStore = usePipelineStore;
}
EOF_STORE

# ---------------------------------------------------------------------
# frontend/src/nodes/BaseNode.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/nodes/BaseNode.js" <<'EOF_BASE'
import React, { useCallback } from "react";
import { Handle, Position } from "reactflow";

function TextField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <input className="node-card__input" type="text" value={value ?? ""}
             placeholder={field.placeholder}
             onChange={(e) => onChange(field.key, e.target.value)} />
    </div>
  );
}
function TextareaField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <textarea className="node-card__textarea" rows={field.rows ?? 3}
                value={value ?? ""} placeholder={field.placeholder}
                onChange={(e) => onChange(field.key, e.target.value)} />
    </div>
  );
}
function NumberField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <input className="node-card__input" type="number" min={field.min} max={field.max}
             step={field.step ?? 1} value={value ?? ""}
             onChange={(e) => onChange(field.key, e.target.value === "" ? "" : Number(e.target.value))} />
    </div>
  );
}
function SelectField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <select className="node-card__select" value={value ?? ""}
              onChange={(e) => onChange(field.key, e.target.value)}>
        {field.options.map((opt) => (
          <option key={opt.value} value={opt.value}>{opt.label}</option>
        ))}
      </select>
    </div>
  );
}
function StatField({ field, value }) {
  return (
    <div className="node-card__stat">
      <span>{field.label}</span>
      <span className="node-card__stat-value">{String(value ?? "—")}</span>
    </div>
  );
}

const FIELD_COMPONENTS = { text: TextField, textarea: TextareaField, number: NumberField, select: SelectField, stat: StatField };

function BaseNode({ id, data, config }) {
  const onChange = useCallback((key, value) => {
    if (typeof data?.onChange === "function") data.onChange(id, key, value);
  }, [data, id]);
  const showSource = config.source !== false;
  const showTarget = config.target !== false;
  const minWidth = config.minWidth ?? 220;
  return (
    <div className="node-card" style={{ minWidth }}>
      {showSource && <Handle type="source" position={Position.Right} style={{ borderColor: config.color }} />}
      <div className="node-card__header">
        <span className="node-card__icon" style={{ background: config.color }}>{config.icon}</span>
        <span className="node-card__title">{config.title}</span>
        {config.badge && <span className="node-card__badge">{config.badge}</span>}
      </div>
      <div className="node-card__body">
        {config.fields.map((field) => {
          if (field.kind === "custom") {
            return (
              <div className="node-card__field" key={field.key}>
                {field.label && <label className="node-card__label">{field.label}</label>}
                {field.render({ value: data?.[field.key], onChange: (v) => onChange(field.key, v), data, id })}
              </div>
            );
          }
          const Comp = FIELD_COMPONENTS[field.kind];
          if (!Comp) return null;
          return <Comp key={field.key} field={field} value={data?.[field.key]} onChange={onChange} />;
        })}
        {config.hint && <div className="node-card__hint">{config.hint}</div>}
      </div>
      {showTarget && <Handle type="target" position={Position.Left} style={{ borderColor: config.color }} />}
    </div>
  );
}

export function createNode(config) {
  const Component = React.memo(function CreatedNode(props) {
    return <BaseNode {...props} config={config} />;
  });
  Component.displayName = `${config.type}_Node`;
  return Component;
}

export { BaseNode };
export default BaseNode;
EOF_BASE

# ---------------------------------------------------------------------
# frontend/src/nodes/TextNode.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/nodes/TextNode.js" <<'EOF_TEXT'
import React, { useCallback, useEffect, useRef, useMemo } from "react";
import { Handle, Position } from "reactflow";

const MAX_WIDTH = 400;
const MIN_WIDTH = 220;
const MAX_HEIGHT = 300;

// Match {{ name }} where name is a valid JS identifier. Internal
// whitespace allowed + trimmed. Rejects {{123}}, {{1abc}}, {{<script>}}.
const VAR_REGEX = /\{\{\s*([A-Za-z_$][\w$]*)\s*\}\}/g;

function extractVariables(text) {
  if (!text) return [];
  const seen = new Set();
  const ordered = [];
  let m;
  VAR_REGEX.lastIndex = 0;
  while ((m = VAR_REGEX.exec(text)) !== null) {
    const name = m[1];
    if (!seen.has(name)) { seen.add(name); ordered.push(name); }
  }
  return ordered;
}

export default function TextNode({ id, data }) {
  const textareaRef = useRef(null);
  const text = data?.text ?? "";
  const variables = useMemo(() => extractVariables(text), [text]);

  const onChange = useCallback((key, value) => {
    if (typeof data?.onChange === "function") data.onChange(id, key, value);
  }, [data, id]);

  const resize = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    const card = el.closest(".node-card");
    if (!card) return;
    el.style.height = "auto";
    el.style.width = "auto";
    const chromeHeight = Math.max(0, card.offsetHeight - el.offsetHeight);
    const availableHeight = Math.max(40, MAX_HEIGHT - chromeHeight);
    const newHeight = Math.min(el.scrollHeight, availableHeight);
    const newWidth = Math.min(Math.max(el.scrollWidth, MIN_WIDTH), MAX_WIDTH);
    el.style.height = `${newHeight}px`;
    el.style.width = `${newWidth}px`;
  }, []);

  useEffect(() => { resize(); }, [text, resize]);
  useEffect(() => { resize(); }, [resize]);

  const handleChange = (e) => onChange("text", e.target.value);

  return (
    <div className="node-card" style={{ width: "auto", minWidth: MIN_WIDTH, maxWidth: MAX_WIDTH, position: "relative" }}>
      <Handle type="source" position={Position.Right} style={{ borderColor: "var(--node-text)" }} />
      <div className="node-card__header">
        <span className="node-card__icon" style={{ background: "var(--node-text)" }}>T</span>
        <span className="node-card__title">Text</span>
        <span className="node-card__badge">Template</span>
      </div>
      <div className="node-card__body" style={{ alignItems: "stretch" }}>
        <textarea ref={textareaRef} className="node-card__textarea" value={text}
                  placeholder="Type here… use {{ name }} to inject variables"
                  onChange={handleChange} rows={2}
                  style={{ width: "100%", height: "auto", maxWidth: MAX_WIDTH - 24,
                           overflow: "hidden", overflowWrap: "anywhere" }} />
        <div className="node-card__hint">
          {variables.length > 0
            ? `Variables: ${variables.join(", ")}`
            : "Tip: write {{ name }} to add an input handle."}
        </div>
      </div>
      <Handle type="target" position={Position.Left} id="__default__"
              style={{ borderColor: "var(--node-text)", top: "50%" }} />
      {variables.map((name, i) => {
        const offset = 50 + (i + 1) * 22;
        return (
          <React.Fragment key={name}>
            <Handle type="target" position={Position.Left} id={`var__${name}`}
                    className="text-node__var-handle" style={{ top: `${offset}px` }} />
            <span className="text-node__var-label" style={{ top: `${offset}px` }}>{name}</span>
          </React.Fragment>
        );
      })}
    </div>
  );
}
EOF_TEXT

# ---------------------------------------------------------------------
# frontend/src/nodes/index.js
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/nodes/index.js" <<'EOF_NODES'
import { createNode } from "./BaseNode";
import TextNode from "./TextNode";

const InputNode = createNode({
  type: "input", title: "Input", icon: "▶", badge: "Source",
  color: "var(--node-input)", source: true, target: false,
  fields: [
    { kind: "select", key: "inputType", label: "Input Type",
      options: [{value:"text",label:"Text"},{value:"file",label:"File"},{value:"url",label:"URL"}] },
    { kind: "text", key: "name", label: "Field Name", placeholder: "user_query" },
  ],
  hint: "Start of the pipeline. Emits data downstream.",
});

const OutputNode = createNode({
  type: "output", title: "Output", icon: "■", badge: "Sink",
  color: "var(--node-output)", source: false, target: true,
  fields: [
    { kind: "select", key: "format", label: "Format",
      options: [{value:"json",label:"JSON"},{value:"text",label:"Text"},{value:"csv",label:"CSV"}] },
  ],
  hint: "Terminal node — collects the final result.",
});

const LLMNode = createNode({
  type: "llm", title: "LLM", icon: "✦", color: "var(--node-llm)",
  fields: [
    { kind: "select", key: "model", label: "Model",
      options: [{value:"gpt-4o",label:"GPT-4o"},{value:"gpt-4o-mini",label:"GPT-4o mini"},
                {value:"claude-3.5-sonnet",label:"Claude 3.5 Sonnet"},{value:"glm-4",label:"GLM-4"}] },
    { kind: "number", key: "temperature", label: "Temperature", min: 0, max: 2, step: 0.1 },
    { kind: "textarea", key: "systemPrompt", label: "System Prompt", rows: 3 },
  ],
  hint: "Calls a language model with the upstream payload.",
});

const TimerNode = createNode({
  type: "timer", title: "Timer", icon: "⏱", badge: "Delay", color: "var(--node-timer)",
  fields: [
    { kind: "number", key: "delay", label: "Delay (seconds)", min: 0, step: 1 },
    { kind: "select", key: "mode", label: "Mode",
      options: [{value:"once",label:"Run once"},{value:"interval",label:"Recurring"}] },
  ],
  hint: "Pauses execution for the configured delay.",
});

const EmailNode = createNode({
  type: "email", title: "Email", icon: "✉", color: "var(--node-email)",
  fields: [
    { kind: "text", key: "to", label: "To", placeholder: "user@example.com" },
    { kind: "text", key: "subject", label: "Subject", placeholder: "Pipeline result" },
    { kind: "textarea", key: "body", label: "Body", rows: 3 },
  ],
  hint: "Sends an email with the upstream payload as the body.",
});

const FilterNode = createNode({
  type: "filter", title: "Filter", icon: "▽", color: "var(--node-filter)",
  fields: [
    { kind: "select", key: "operator", label: "Operator",
      options: [{value:"contains",label:"contains"},{value:"equals",label:"equals"},
                {value:"greater_than",label:"greater than"},{value:"less_than",label:"less than"},
                {value:"regex",label:"regex match"}] },
    { kind: "text", key: "value", label: "Compare To", placeholder: "expected value" },
  ],
  hint: "Passes payload downstream only if the condition is met.",
});

const MergeNode = createNode({
  type: "merge", title: "Merge", icon: "⋈", badge: "2→1", color: "var(--node-merge)",
  source: true, target: true,
  fields: [
    { kind: "select", key: "strategy", label: "Strategy",
      options: [{value:"concat",label:"Concatenate"},{value:"object",label:"Merge as object"},
                {value:"array",label:"Combine as array"}] },
  ],
  hint: "Joins two upstream branches into a single payload.",
});

const DebugNode = createNode({
  type: "debug", title: "Debug", icon: "⌖", color: "var(--node-debug)",
  fields: [
    { kind: "select", key: "logLevel", label: "Log Level",
      options: [{value:"info",label:"Info"},{value:"warn",label:"Warn"},{value:"error",label:"Error"}] },
    { kind: "stat", key: "lastValue", label: "Last Payload" },
  ],
  hint: "Logs the upstream payload to the console without mutating it.",
});

export const nodeTypes = {
  input: InputNode, output: OutputNode, llm: LLMNode, text: TextNode,
  timer: TimerNode, email: EmailNode, filter: FilterNode, merge: MergeNode, debug: DebugNode,
};

export const PALETTE = [
  { type: "input", title: "Input", icon: "▶", color: "var(--node-input)" },
  { type: "output", title: "Output", icon: "■", color: "var(--node-output)" },
  { type: "llm", title: "LLM", icon: "✦", color: "var(--node-llm)" },
  { type: "text", title: "Text", icon: "T", color: "var(--node-text)" },
  { type: "timer", title: "Timer", icon: "⏱", color: "var(--node-timer)" },
  { type: "email", title: "Email", icon: "✉", color: "var(--node-email)" },
  { type: "filter", title: "Filter", icon: "▽", color: "var(--node-filter)" },
  { type: "merge", title: "Merge", icon: "⋈", color: "var(--node-merge)" },
  { type: "debug", title: "Debug", icon: "⌖", color: "var(--node-debug)" },
];

export function defaultNodeData(type) {
  switch (type) {
    case "input": return { inputType: "text", name: "user_query" };
    case "output": return { format: "json" };
    case "llm": return { model: "gpt-4o-mini", temperature: 0.7, systemPrompt: "You are a helpful assistant." };
    case "text": return { text: "" };
    case "timer": return { delay: 5, mode: "once" };
    case "email": return { to: "", subject: "", body: "" };
    case "filter": return { operator: "contains", value: "" };
    case "merge": return { strategy: "concat" };
    case "debug": return { logLevel: "info", lastValue: "(none)" };
    default: return {};
  }
}
EOF_NODES

# ---------------------------------------------------------------------
# frontend/src/styles/global.css  (the design system — long but essential)
# ---------------------------------------------------------------------
cat > "$ROOT/frontend/src/styles/global.css" <<'EOF_CSS'
:root {
  --bg-app:#0f172a;--bg-panel:#1e293b;--bg-card:#ffffff;--bg-card-header:#f8fafc;--bg-input:#f1f5f9;
  --text-primary:#0f172a;--text-secondary:#475569;--text-muted:#94a3b8;--text-on-dark:#e2e8f0;
  --border:#e2e8f0;--border-strong:#cbd5e1;
  --accent:#6366f1;--accent-hover:#4f46e5;--accent-soft:rgba(99,102,241,0.12);
  --success:#10b981;--warning:#f59e0b;--danger:#ef4444;--info:#0ea5e9;
  --node-input:#3b82f6;--node-output:#10b981;--node-llm:#8b5cf6;--node-text:#ec4899;
  --node-timer:#f59e0b;--node-email:#ef4444;--node-filter:#06b6d4;--node-merge:#84cc16;--node-debug:#64748b;
  --shadow-sm:0 1px 2px rgba(15,23,42,0.06);--shadow-md:0 4px 12px rgba(15,23,42,0.12);
  --shadow-lg:0 12px 32px rgba(15,23,42,0.20);--shadow-node:0 6px 20px rgba(15,23,42,0.15);
  --radius-sm:6px;--radius-md:10px;--radius-lg:14px;
  --font-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans",sans-serif;
  --font-mono:"SF Mono","Fira Code","JetBrains Mono",Menlo,Consolas,monospace;
}
*{box-sizing:border-box;}
html,body,#root{height:100%;margin:0;padding:0;}
body{font-family:var(--font-sans);color:var(--text-primary);background:var(--bg-app);
  -webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;overflow:hidden;}
.app-shell{display:flex;flex-direction:column;height:100vh;width:100vw;background:var(--bg-app);}
.toolbar{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:12px 20px;
  background:linear-gradient(180deg,#1e293b 0%,#0f172a 100%);border-bottom:1px solid rgba(148,163,184,0.18);
  color:var(--text-on-dark);flex-shrink:0;z-index:10;}
.toolbar__brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:17px;letter-spacing:-0.01em;}
.toolbar__brand-mark{width:28px;height:28px;border-radius:8px;
  background:linear-gradient(135deg,var(--accent) 0%,#8b5cf6 100%);display:grid;place-items:center;
  color:#fff;font-size:15px;box-shadow:0 4px 10px rgba(99,102,241,0.45);}
.toolbar__subtitle{font-size:12px;color:var(--text-muted);font-weight:500;margin-left:6px;}
.toolbar__actions{display:flex;align-items:center;gap:10px;}
.btn{display:inline-flex;align-items:center;gap:8px;padding:9px 16px;border-radius:var(--radius-md);
  border:1px solid transparent;font-size:14px;font-weight:600;font-family:var(--font-sans);cursor:pointer;
  transition:all 0.15s ease;user-select:none;white-space:nowrap;}
.btn:disabled{opacity:0.55;cursor:not-allowed;}
.btn--primary{background:linear-gradient(135deg,var(--accent) 0%,#8b5cf6 100%);color:#fff;
  box-shadow:0 4px 14px rgba(99,102,241,0.4);}
.btn--primary:hover:not(:disabled){transform:translateY(-1px);box-shadow:0 6px 18px rgba(99,102,241,0.55);}
.btn--primary:active:not(:disabled){transform:translateY(0);}
.btn--ghost{background:rgba(148,163,184,0.12);color:var(--text-on-dark);border-color:rgba(148,163,184,0.22);}
.btn--ghost:hover:not(:disabled){background:rgba(148,163,184,0.2);}
.btn--small{padding:6px 10px;font-size:12px;}
.sidebar{width:220px;flex-shrink:0;background:var(--bg-panel);border-right:1px solid rgba(148,163,184,0.15);
  padding:16px 12px;overflow-y:auto;color:var(--text-on-dark);}
.sidebar__title{font-size:11px;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);
  margin:4px 4px 10px;font-weight:700;}
.palette-item{display:flex;align-items:center;gap:10px;padding:10px 12px;margin-bottom:6px;
  border-radius:var(--radius-md);background:rgba(148,163,184,0.08);border:1px solid transparent;
  color:var(--text-on-dark);cursor:grab;font-size:13px;font-weight:500;transition:all 0.15s ease;user-select:none;}
.palette-item:hover{background:rgba(148,163,184,0.16);border-color:rgba(148,163,184,0.3);transform:translateX(2px);}
.palette-item:active{cursor:grabbing;}
.palette-item__dot{width:10px;height:10px;border-radius:50%;flex-shrink:0;
  box-shadow:0 0 0 3px rgba(255,255,255,0.08);}
.palette-item__hint{margin-left:auto;font-size:11px;color:var(--text-muted);}
.canvas-wrap{flex:1;position:relative;min-height:0;}
.react-flow{background:#0b1220;}
.react-flow__background{background:#0b1220;}
.react-flow__pane{cursor:grab;}
.react-flow__pane:active{cursor:grabbing;}
.react-flow__edge-path{stroke:#94a3b8;stroke-width:2;}
.react-flow__edge.selected .react-flow__edge-path{stroke:var(--accent);stroke-width:3;}
.react-flow__edge.animated .react-flow__edge-path{stroke-dasharray:6 4;animation:dashdraw 0.6s linear infinite;}
@keyframes dashdraw{to{stroke-dashoffset:-10;}}
.react-flow__handle{width:12px;height:12px;background:#fff;border:2px solid var(--accent);border-radius:50%;
  transition:all 0.15s ease;}
.react-flow__handle:hover{background:var(--accent);transform:scale(1.25);}
.react-flow__handle.connectionindicator{cursor:crosshair;}
.text-node__var-handle{background:#fff;border:2px solid var(--node-text);}
.text-node__var-handle:hover{background:var(--node-text);}
.node-card{width:220px;background:var(--bg-card);border-radius:var(--radius-lg);border:1px solid var(--border);
  box-shadow:var(--shadow-node);overflow:hidden;font-family:var(--font-sans);
  transition:box-shadow 0.15s ease,transform 0.15s ease;}
.react-flow__node.selected .node-card{box-shadow:0 0 0 2px var(--accent),var(--shadow-lg);}
.node-card__header{display:flex;align-items:center;gap:8px;padding:9px 12px;background:var(--bg-card-header);
  border-bottom:1px solid var(--border);font-size:13px;font-weight:700;color:var(--text-primary);}
.node-card__icon{width:22px;height:22px;border-radius:6px;display:grid;place-items:center;color:#fff;
  font-size:13px;flex-shrink:0;}
.node-card__title{flex:1;letter-spacing:-0.01em;}
.node-card__badge{font-size:10px;text-transform:uppercase;letter-spacing:0.06em;color:var(--text-muted);font-weight:700;}
.node-card__body{padding:12px;display:flex;flex-direction:column;gap:8px;}
.node-card__field{display:flex;flex-direction:column;gap:4px;}
.node-card__label{font-size:11px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;
  letter-spacing:0.04em;}
.node-card__input,.node-card__textarea,.node-card__select{width:100%;padding:7px 9px;
  border:1px solid var(--border-strong);border-radius:var(--radius-sm);background:var(--bg-input);
  font-size:13px;font-family:var(--font-sans);color:var(--text-primary);outline:none;
  transition:border-color 0.15s ease,box-shadow 0.15s ease;}
.node-card__input:focus,.node-card__textarea:focus,.node-card__select:focus{border-color:var(--accent);
  box-shadow:0 0 0 3px var(--accent-soft);background:#fff;}
.node-card__textarea{resize:none;font-family:var(--font-mono);line-height:1.4;}
.node-card__hint{font-size:11px;color:var(--text-muted);line-height:1.4;}
.node-card__stat{display:flex;justify-content:space-between;align-items:center;font-size:12px;
  color:var(--text-secondary);padding:4px 0;}
.node-card__stat-value{font-weight:700;color:var(--text-primary);font-family:var(--font-mono);}
.text-node__var-label{position:absolute;left:18px;font-size:10px;font-weight:600;color:var(--node-text);
  background:#fff;padding:1px 6px;border-radius:4px;border:1px solid var(--border);white-space:nowrap;
  pointer-events:none;transform:translateY(-50%);}
.status-pill{display:inline-flex;align-items:center;gap:6px;padding:5px 10px;border-radius:999px;
  font-size:11px;font-weight:600;background:rgba(16,185,129,0.15);color:#6ee7b7;
  border:1px solid rgba(16,185,129,0.3);}
.status-pill__dot{width:7px;height:7px;border-radius:50%;background:var(--success);box-shadow:0 0 6px var(--success);}
.spinner{width:14px;height:14px;border:2px solid rgba(255,255,255,0.35);border-top-color:#fff;
  border-radius:50%;animation:spin 0.7s linear infinite;}
@keyframes spin{to{transform:rotate(360deg);}}
::-webkit-scrollbar{width:10px;height:10px;}
::-webkit-scrollbar-track{background:transparent;}
::-webkit-scrollbar-thumb{background:rgba(148,163,184,0.35);border-radius:999px;border:2px solid transparent;
  background-clip:padding-box;}
::-webkit-scrollbar-thumb:hover{background:rgba(148,163,184,0.55);background-clip:padding-box;}
EOF_CSS

echo ""
echo "✅ Project created in ./$ROOT"
echo ""
echo "Next steps:"
echo "  cd $ROOT/backend && pip install -r requirements.txt && uvicorn main:app --reload --port 8000"
echo "  cd $ROOT/frontend && npm install && npm start"
echo ""
echo "File count: $(find $ROOT -type f | wc -l)"
