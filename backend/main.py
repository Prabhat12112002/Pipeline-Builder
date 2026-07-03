"""
Pipeline Builder — FastAPI backend
=================================================
Implements `POST /pipelines/parse` which accepts `{ nodes, edges }`
and returns `{ num_nodes, num_edges, is_dag }`.

The DAG check uses iterative DFS with WHITE/GRAY/BLACK colouring.
A back-edge to a GRAY node means a cycle exists, so the graph is NOT
a DAG. Self-loops and disconnected components are handled correctly.

Security notes
--------------
- CORS is configured for local development only. In production, set
  `ALLOWED_ORIGINS` to an explicit list of trusted frontend origins.
  `allow_credentials` is False because this API uses no cookies or
  auth headers; if credentials are ever added, origins MUST be
  explicit (never "*").
- No CSRF protection is needed today (no cookie/session auth). If
  cookie-based auth is added later, CSRF tokens become mandatory.
- A custom 500 handler ensures stack traces are logged server-side
  but never leaked to the client.
- Input is validated and size-capped by Pydantic to mitigate DoS.

Run:
    cd backend
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

# --------------------------------------------------------------------------- #
# Logging configuration
# --------------------------------------------------------------------------- #
# Use stdlib logging (never print) so logs can be routed to any sink
# (stdout, file, aggregator) in production.
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
)
logger = logging.getLogger("pipeline_builder")

# --------------------------------------------------------------------------- #
# CORS configuration
# --------------------------------------------------------------------------- #
# Production: set ALLOWED_ORIGINS env var to a comma-separated list of
# trusted frontend URLs, e.g. "https://app.example.com".
# Development: default allows all localhost origins.
_DEFAULT_ORIGINS = "http://localhost:3000,http://127.0.0.1:3000"
_raw_origins = os.environ.get("ALLOWED_ORIGINS", _DEFAULT_ORIGINS)
ALLOWED_ORIGINS: List[str] = [o.strip() for o in _raw_origins.split(",") if o.strip()]

# --------------------------------------------------------------------------- #
# Input size caps (DoS mitigation)
# --------------------------------------------------------------------------- #
MAX_NODES = 10_000
MAX_EDGES = 50_000

# --------------------------------------------------------------------------- #
# Pydantic models
# --------------------------------------------------------------------------- #


class PipelineNode(BaseModel):
    """A node in the pipeline.

    `id` is required and must be non-empty (it is the only field the
    DAG algorithm strictly needs). Other fields are accepted but
    optional so the frontend can send the full reactflow node object.
    """

    id: str
    type: str | None = None
    data: Dict[str, Any] | None = None
    model_config = {"extra": "allow"}

    @field_validator("id")
    @classmethod
    def _id_non_empty(cls, v: str) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("node 'id' must be a non-empty string")
        return v


class PipelineEdge(BaseModel):
    """An edge in the pipeline. `source` and `target` reference node IDs."""

    source: str
    target: str
    id: str | None = None
    model_config = {"extra": "allow"}

    @field_validator("source", "target")
    @classmethod
    def _endpoint_non_empty(cls, v: str) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("edge 'source'/'target' must be non-empty strings")
        return v


class PipelinePayload(BaseModel):
    """Top-level request body. Lists are size-capped to prevent DoS."""

    nodes: List[PipelineNode] = Field(default_factory=list, max_length=MAX_NODES)
    edges: List[PipelineEdge] = Field(default_factory=list, max_length=MAX_EDGES)


class PipelineAnalysis(BaseModel):
    """Response model returned by /pipelines/parse."""

    num_nodes: int
    num_edges: int
    is_dag: bool


class HealthResponse(BaseModel):
    status: str
    service: str


# --------------------------------------------------------------------------- #
# DAG detection (iterative DFS, WHITE/GRAY/BLACK colouring)
# --------------------------------------------------------------------------- #

WHITE, GRAY, BLACK = 0, 1, 2


def is_dag(node_ids: List[str], edges: List[PipelineEdge]) -> bool:
    """Return True iff the directed graph is acyclic.

    Algorithm: iterative DFS (avoids Python recursion-limit issues on
    large graphs) using a three-colour marking scheme:
      - WHITE: unvisited
      - GRAY:  currently on the recursion stack
      - BLACK: fully explored

    A back-edge to a GRAY node ⇒ cycle ⇒ not a DAG.
    Self-loops (source == target) are cycles and are detected too.
    Edges referencing non-existent nodes are ignored (defensive —
    reactflow should not produce dangling edges, but we never crash).
    Multiple parallel edges between the same pair do not constitute a
    cycle and correctly return True.
    """
    id_set = set(node_ids)
    adj: Dict[str, List[str]] = {nid: [] for nid in node_ids}
    for e in edges:
        if e.source in id_set and e.target in id_set:
            adj[e.source].append(e.target)

    colour: Dict[str, int] = {nid: WHITE for nid in node_ids}

    for start in node_ids:
        if colour[start] != WHITE:
            continue
        stack: List[tuple] = [(start, iter(adj[start]))]
        colour[start] = GRAY
        while stack:
            node, neighbours = stack[-1]
            advanced = False
            for nxt in neighbours:
                if colour[nxt] == GRAY:
                    return False  # back-edge → cycle
                if colour[nxt] == WHITE:
                    colour[nxt] = GRAY
                    stack.append((nxt, iter(adj[nxt])))
                    advanced = True
                    break
            if not advanced:
                colour[node] = BLACK
                stack.pop()
    return True


# --------------------------------------------------------------------------- #
# App
# --------------------------------------------------------------------------- #

app = FastAPI(
    title="Pipeline Builder API",
    version="1.0.0",
    # Disable docs in production by setting env var if desired.
    docs_url="/docs" if os.environ.get("ENABLE_DOCS", "true").lower() == "true" else None,
    redoc_url=None,
)

# CORS — configured for local dev. See ALLOWED_ORIGINS note above.
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    # No cookies or credential-based auth is used. If credentials are
    # ever added, keep this False and use an explicit origin list.
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)


# --------------------------------------------------------------------------- #
# Exception handlers — never leak stack traces to the client
# --------------------------------------------------------------------------- #


@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception):
    """Catch-all for unexpected errors. Log the full traceback server-side,
    return a generic 500 to the client (no internal details leaked)."""
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )


# --------------------------------------------------------------------------- #
# Routes
# --------------------------------------------------------------------------- #


@app.get("/health", response_model=HealthResponse)
@app.get("/", response_model=HealthResponse)
def health() -> HealthResponse:
    """Health check endpoint for uptime monitoring / load balancers."""
    return HealthResponse(status="ok", service="pipeline-builder-api")


@app.post("/pipelines/parse", response_model=PipelineAnalysis)
def parse_pipeline(payload: PipelinePayload) -> PipelineAnalysis:
    """Analyse a pipeline graph.

    - num_nodes = len(nodes)
    - num_edges = len(edges)
    - is_dag    = True iff the directed graph (edges.source → edges.target)
                  contains no cycle.
    """
    # Pydantic has already validated structure and size caps by this
    # point. If the body is missing/invalid, a 422 was returned before
    # reaching here.
    node_ids = [n.id for n in payload.nodes]
    num_nodes = len(payload.nodes)
    num_edges = len(payload.edges)

    try:
        dag = is_dag(node_ids, payload.edges)
    except Exception:
        logger.exception("DAG computation failed")
        # Re-raise as a generic 500 via the exception handler.
        raise

    return PipelineAnalysis(
        num_nodes=num_nodes,
        num_edges=num_edges,
        is_dag=dag,
    )


# Convenience: run with `python main.py`.
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "8000")),
        reload=bool(os.environ.get("RELOAD", "")),
    )
