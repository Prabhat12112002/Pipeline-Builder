"""
Pipeline Builder — FastAPI backend (Part 4)
=================================================
Implements `POST /pipelines/parse` which accepts `{ nodes, edges }`
and returns `{ num_nodes, num_edges, is_dag }`.

The DAG check uses DFS with an explicit recursion stack (WHITE/GRAY/BLACK
colouring). A back-edge to a GRAY node means a cycle exists, so the
graph is NOT a DAG. We also handle self-loops and disconnected
components correctly.

CORS is wide-open for local development.

Run:
    cd /home/z/my-project/backend
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from typing import Any, Dict, List

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# --------------------------------------------------------------------------- #
# Models
# --------------------------------------------------------------------------- #


class PipelineNode(BaseModel):
    """A node in the pipeline. We only strictly need `id` for the DAG check,
    but we accept arbitrary extra fields so the frontend can send the full
    reactflow node object without 422-ing."""

    id: str
    type: str | None = None
    data: Dict[str, Any] | None = None
    # Allow any other fields reactflow may include (position, width, ...).
    model_config = {"extra": "allow"}


class PipelineEdge(BaseModel):
    source: str
    target: str
    id: str | None = None
    model_config = {"extra": "allow"}


class PipelinePayload(BaseModel):
    nodes: List[PipelineNode] = Field(default_factory=list)
    edges: List[PipelineEdge] = Field(default_factory=list)


class PipelineAnalysis(BaseModel):
    num_nodes: int
    num_edges: int
    is_dag: bool


# --------------------------------------------------------------------------- #
# DAG detection (DFS with WHITE/GRAY/BLACK colouring)
# --------------------------------------------------------------------------- #

# Colour states for DFS
WHITE, GRAY, BLACK = 0, 1, 2


def is_dag(node_ids: List[str], edges: List[PipelineEdge]) -> bool:
    """Return True iff the directed graph is acyclic.

    Algorithm: iterative DFS (avoids Python recursion-limit issues on
    very large graphs) using a three-colour marking scheme:
      - WHITE: unvisited
      - GRAY:  currently on the recursion stack
      - BLACK: fully explored

    A back-edge to a GRAY node ⇒ cycle ⇒ not a DAG.
    Self-loops (source == target) are cycles and are detected too.
    """
    # Build adjacency list. Only count edges whose endpoints exist in
    # node_ids (defensive — reactflow shouldn't produce dangling edges
    # but we don't want to crash if it does).
    id_set = set(node_ids)
    adj: Dict[str, List[str]] = {nid: [] for nid in node_ids}
    for e in edges:
        if e.source in id_set and e.target in id_set:
            adj[e.source].append(e.target)

    colour: Dict[str, int] = {nid: WHITE for nid in node_ids}

    for start in node_ids:
        if colour[start] != WHITE:
            continue
        # Iterative DFS. Stack holds (node, iterator-over-neighbours).
        # We mark GRAY on push, BLACK on pop.
        stack = [(start, iter(adj[start]))]
        colour[start] = GRAY
        while stack:
            node, neighbours = stack[-1]
            advanced = False
            for nxt in neighbours:
                if colour[nxt] == GRAY:
                    # Back-edge → cycle.
                    return False
                if colour[nxt] == WHITE:
                    colour[nxt] = GRAY
                    stack.append((nxt, iter(adj[nxt])))
                    advanced = True
                    break
            if not advanced:
                # Done with this node.
                colour[node] = BLACK
                stack.pop()
    return True


# --------------------------------------------------------------------------- #
# App
# --------------------------------------------------------------------------- #

app = FastAPI(title="Pipeline Builder API", version="1.0.0")

# CORS — wide open for local dev (frontend on :3000, backend on :8000).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def health():
    """Tiny health check so you can confirm the server is up in the browser."""
    return {"status": "ok", "service": "pipeline-builder-api"}


@app.post("/pipelines/parse", response_model=PipelineAnalysis)
def parse_pipeline(payload: PipelinePayload) -> PipelineAnalysis:
    """Analyse a pipeline graph.

    - num_nodes = len(nodes)
    - num_edges = len(edges)
    - is_dag    = True iff the directed graph (edges.source → edges.target)
                  contains no cycle.
    """
    if payload is None:
        raise HTTPException(status_code=400, detail="Empty request body")

    node_ids = [n.id for n in payload.nodes]
    num_nodes = len(payload.nodes)
    num_edges = len(payload.edges)
    dag = is_dag(node_ids, payload.edges)

    return PipelineAnalysis(
        num_nodes=num_nodes,
        num_edges=num_edges,
        is_dag=dag,
    )


# Convenience: run with `python main.py` too.
if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
