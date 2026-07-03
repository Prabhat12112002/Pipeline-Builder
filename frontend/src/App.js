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

  const onDragOver = useCallback((event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const onDrop = useCallback(
    (event) => {
      event.preventDefault();
      const type = event.dataTransfer.getData("application/reactflow");
      if (!type) return;

      const position = event.currentTarget.getBoundingClientRect();
      // reactflow screen-to-flow conversion happens via the wrapper ref
      // using the reactflow instance from the bound event.
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
        <Sidebar />
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
