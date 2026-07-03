/**
 * App — top-level pipeline builder UI.
 * --------------------------------------------------------------
 * Layout: toolbar (top) + sidebar (left palette) + reactflow canvas.
 * Nodes/edges live in the zustand store. Dragging from the palette
 * onto the canvas calls store.addNode(type, position).
 *
 * The Submit button calls submitAndAlert(nodes, edges) which POSTs to
 * the FastAPI backend and alerts the analysis result (Part 4).
 */
import React, { useCallback, useRef, useState } from "react";
import ReactFlow, {
  Background,
  Controls,
  MiniMap,
  ReactFlowProvider,
} from "reactflow";
import "reactflow/dist/style.css";

import Sidebar from "./components/Sidebar";
import { nodeTypes } from "./nodes";
import { usePipelineStore } from "./store/pipelineStore";
import { submitAndAlert } from "./submit";

const flowStyle = { background: "#0b1220" };

function Builder() {
  const reactFlowWrapper = useRef(null);
  const {
    nodes,
    edges,
    onNodesChange,
    onEdgesChange,
    onConnect,
    addNode,
  } = usePipelineStore();
  const [submitting, setSubmitting] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);

  const onDragOver = useCallback((event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const onDrop = useCallback(
    (event) => {
      event.preventDefault();
      const type = event.dataTransfer.getData("application/reactflow");
      if (!type) return;

      // Defensive: ensure the wrapper ref is attached before computing
      // drop coordinates (guards against race conditions on mount).
      if (!reactFlowWrapper.current) return;
      const bounds = reactFlowWrapper.current.getBoundingClientRect();
      const x = event.clientX - bounds.left;
      const y = event.clientY - bounds.top;
      addNode(type, { x, y });
    },
    [addNode]
  );

  const onSubmit = useCallback(async () => {
    setSubmitting(true);
    try {
      await submitAndAlert(nodes, edges);
    } finally {
      setSubmitting(false);
    }
  }, [nodes, edges]);

  return (
    <div className="app-shell">
      {/* Toolbar */}
      <header className="toolbar">
        <div className="toolbar__brand" style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <button
            onClick={() => setIsSidebarOpen(!isSidebarOpen)}
            title={isSidebarOpen ? "Hide Sidebar" : "Show Sidebar"}
            style={{
              background: "none",
              border: "none",
              color: isSidebarOpen ? "var(--text-on-dark)" : "var(--text-muted)",
              cursor: "pointer",
              padding: "6px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              borderRadius: "6px",
              transition: "all 0.15s ease",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = "rgba(255, 255, 255, 0.08)";
              e.currentTarget.style.color = "var(--text-on-dark)";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = "none";
              e.currentTarget.style.color = isSidebarOpen ? "var(--text-on-dark)" : "var(--text-muted)";
            }}
          >
            {/* Hide Sidebar Horiz Vector SVG Icon */}
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
              <line x1="9" y1="3" x2="9" y2="21" />
              {isSidebarOpen ? (
                // Arrow pointing left inside the sidebar layout
                <path d="M16 15l-3-3 3-3" />
              ) : (
                // Arrow pointing right inside the sidebar layout
                <path d="M14 9l3 3-3 3" />
              )}
            </svg>
          </button>
          <span className="toolbar__brand-mark">⌁</span>
          Pipeline Builder
          <span className="toolbar__subtitle">visual node editor</span>
        </div>
        <div className="toolbar__actions">
          <span className="status-pill">
            <span className="status-pill__dot" />
            {nodes.length} nodes · {edges.length} edges
          </span>
          <button
            className="btn btn--primary"
            onClick={onSubmit}
            disabled={submitting}
          >
            {submitting ? (
              <>
                <span className="spinner" />
                Analysing…
              </>
            ) : (
              <>⚡ Submit Pipeline</>
            )}
          </button>
        </div>
      </header>

      {/* Body: sidebar + canvas */}
      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        <Sidebar isOpen={isSidebarOpen} />
        <div className="canvas-wrap" ref={reactFlowWrapper}>
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            nodeTypes={nodeTypes}
            onDrop={onDrop}
            onDragOver={onDragOver}
            fitView
            fitViewOptions={{ padding: 0.2 }}
            deleteKeyCode={["Backspace", "Delete"]}
            style={flowStyle}
          >
            <Background color="#334155" gap={20} size={1.5} />
            <Controls />
            <MiniMap
              nodeColor={(n) => {
                const map = {
                  input: "#3b82f6",
                  output: "#10b981",
                  llm: "#8b5cf6",
                  text: "#ec4899",
                  timer: "#f59e0b",
                  email: "#ef4444",
                  filter: "#06b6d4",
                  merge: "#84cc16",
                  debug: "#64748b",
                };
                return map[n.type] || "#6366f1";
              }}
              maskColor="rgba(11,18,32,0.7)"
              style={{ background: "#0b1220" }}
            />
          </ReactFlow>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <ReactFlowProvider>
      <Builder />
    </ReactFlowProvider>
  );
}
