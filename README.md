# Pipeline Builder

A visual node-based pipeline editor built with **React + React Flow** (frontend) and **FastAPI** (backend). Drag nodes onto a canvas, connect them into a directed graph, and submit the pipeline to the backend for structural analysis (node count, edge count, and DAG cycle detection).

---

## Features

- **Node abstraction** — a `createNode(config)` factory lets new node types be added in ~10 lines. Ships with 9 node types (Input, Output, LLM, Text, Timer, Email, Filter, Merge, Debug).
- **Unified design system** — a single CSS file defines colors, typography, shadows, and component styles for a polished, consistent look.
- **Text node with live templating** — type `{{ variableName }}` to dynamically create input handles; the node auto-resizes up to 400×300 px.
- **Backend DAG analysis** — `POST /pipelines/parse` counts nodes/edges and detects cycles via iterative DFS (WHITE/GRAY/BLACK colouring).
- **Error boundary** — the frontend degrades gracefully on render errors.
- **Configurable CORS** — explicit origin allowlist (no wildcard + credentials).

---

## Project structure

```
.
├── frontend/
│   ├── .env.example
│   ├── package.json
│   └── src/
│       ├── App.js                  # main canvas + toolbar
│       ├── index.js                # entry point (wraps App in ErrorBoundary)
│       ├── submit.js               # POST /pipelines/parse + alert
│       ├── components/
│       │   ├── ErrorBoundary.js
│       │   └── Sidebar.js          # draggable node palette
│       ├── nodes/
│       │   ├── BaseNode.js         # createNode() factory abstraction
│       │   ├── TextNode.js         # auto-resize + {{ var }} handles
│       │   └── index.js            # node registry (all 9 types)
│       ├── store/
│       │   └── pipelineStore.js    # zustand store (nodes + edges)
│       └── styles/
│           └── global.css          # design system
│
└── backend/
    ├── .env.example
    ├── requirements.txt
    └── main.py                     # FastAPI app + DAG detection
```

---

## Prerequisites

- **Node.js** ≥ 18 (tested on Node 24)
- **Python** ≥ 3.10 (tested on 3.12)
- `pip` or a virtual environment manager

---

## Setup & run (development)

### 1. Backend

```bash
cd backend

# (optional) create a virtual environment
python -m venv .venv && source .venv/bin/activate

# install dependencies
pip install -r requirements.txt

# copy env template and adjust if needed
cp .env.example .env

# start the server (auto-reloads on file changes)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The API will be available at `http://localhost:8000`.
Interactive docs: `http://localhost:8000/docs`.

### 2. Frontend

```bash
cd frontend

# install dependencies
npm install

# copy env template and adjust if needed
cp .env.example .env

# start the dev server
npm start
```

The app opens at `http://localhost:3000`.

### 3. Use it

1. Drag node types from the left palette onto the canvas.
2. Drag from a node's right handle (source) to another node's left handle (target) to connect them.
3. In a **Text** node, type `Hello {{ name }}` — a labelled input handle appears on the left.
4. Click **⚡ Submit Pipeline** — an alert shows `Number of nodes`, `Number of edges`, and `Is DAG`.

---

## Environment variables

### Frontend (`frontend/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `REACT_APP_API_URL` | `http://localhost:8000` | Backend API base URL |
| `PORT` | `3000` | Dev server port |
| `BROWSER` | `none` | Prevents CRA from auto-opening a browser |
| `DISABLE_ESLINT_PLUGIN` | `true` | Prevents lint errors from blocking the dev build |

### Backend (`backend/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `ALLOWED_ORIGINS` | `http://localhost:3000,...` | Comma-separated CORS allowlist |
| `HOST` | `0.0.0.0` | Server bind address |
| `PORT` | `8000` | Server port |
| `ENABLE_DOCS` | `true` | Show `/docs` OpenAPI UI (set `false` in prod) |
| `LOG_LEVEL` | `INFO` | Logging verbosity |

---

## API reference

### `GET /health`
Returns `{"status":"ok","service":"pipeline-builder-api"}`.

### `POST /pipelines/parse`
Analyse a pipeline graph.

**Request body:**
```json
{
  "nodes": [{"id": "1", "type": "input"}, ...],
  "edges": [{"source": "1", "target": "2"}, ...]
}
```

**Response (200):**
```json
{"num_nodes": 3, "num_edges": 2, "is_dag": true}
```

**Validation (422):** Malformed JSON, non-list `nodes`/`edges`, empty node `id`, empty edge `source`/`target`, or exceeding 10 000 nodes / 50 000 edges.

---

## Production deployment

### Frontend
```bash
cd frontend
npm run build      # outputs optimized static files to frontend/build/
# Serve with any static host (nginx, Vercel, S3+CloudFront, etc.):
npx serve -s build
```
Set `REACT_APP_API_URL` to your production backend URL **before** building (CRA bakes env vars into the bundle at build time).

### Backend
```bash
cd backend
pip install -r requirements.txt
# Run with a production ASGI server (no --reload):
gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000
```
Set `ALLOWED_ORIGINS` to your production frontend URL and `ENABLE_DOCS=false`.

---

## Security notes

| Area | Status |
|------|--------|
| **XSS** | Text node content is rendered in a controlled `<textarea>` (React auto-escapes). Variable names are restricted to `[A-Za-z0-9_$]` by regex, so HTML/script tags in `{{ }}` produce no handle. No `dangerouslySetInnerHTML` anywhere. |
| **CORS** | Explicit origin allowlist (`ALLOWED_ORIGINS` env var). `allow_credentials=False` (no cookies used). If cookie auth is added later, keep credentials False and use an explicit origin list. |
| **CSRF** | Not applicable (no cookie/session auth). If auth is added, implement CSRF tokens. |
| **Input validation** | Pydantic validates types, required fields, non-empty IDs, and enforces size caps (10 000 nodes / 50 000 edges). Malformed input returns 422. |
| **Error leakage** | Custom 500 handler logs stack traces server-side but returns only `{"detail":"Internal server error"}` to the client. |
| **CSP** | Not set (demo app). For production, add a `Content-Security-Policy` header (e.g. via nginx) restricting `script-src` to `'self'`. |
| **Secrets** | No hardcoded secrets. All config is via env vars. |

---

## Pre-publication checklist

Before deploying, run:

```bash
# Frontend — check for known vulnerabilities
cd frontend
npm audit
npm audit fix          # auto-fix what's possible

# Backend — check for known vulnerabilities
cd ../backend
pip install pip-audit
pip-audit -r requirements.txt
```

Also review:
- [ ] `npm audit` shows no high/critical vulnerabilities
- [ ] `pip-audit` shows no known vulnerabilities
- [ ] `ALLOWED_ORIGINS` set to production frontend URL (not localhost)
- [ ] `ENABLE_DOCS=false` in production
- [ ] HTTPS termination configured (reverse proxy)
- [ ] `Content-Security-Policy` header added by reverse proxy
- [ ] Rate limiting on `/pipelines/parse` if exposed publicly

---

## Testing the DAG algorithm

The backend's `is_dag()` function handles all standard cases:

| Graph | Expected `is_dag` |
|-------|-------------------|
| Empty (0 nodes, 0 edges) | `true` |
| Linear: 1→2→3 | `true` |
| Cycle: 1→2→3→1 | `false` |
| Self-loop: A→A | `false` |
| Disconnected trees (no cycle) | `true` |
| Parallel edges: A→B twice | `true` |
| Diamond: A→{B,C}→D | `true` |
| Edge to non-existent node | `true` (dangling edge ignored) |
