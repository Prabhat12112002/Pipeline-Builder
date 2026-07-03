/**
 * Sidebar — draggable node palette.
 * Each item is a reactflow DnD source. Drag onto the canvas to create
 * a new node of that type.
 */
import React, { useCallback } from "react";
import { PALETTE } from "../nodes";
import { usePipelineStore } from "../store/pipelineStore";

export default function Sidebar({ isOpen }) {
  const addNode = usePipelineStore((state) => state.addNode);

  const onDragStart = (event, nodeType) => {
    event.dataTransfer.setData("application/reactflow", nodeType);
    event.dataTransfer.effectAllowed = "move";
  };

  const handleNodeClick = useCallback(
    (type) => {
      // Spawn node near the canvas center with a slight random offset to prevent stacking
      const x = 150 + Math.floor(Math.random() * 150);
      const y = 100 + Math.floor(Math.random() * 150);
      addNode(type, { x, y });
    },
    [addNode]
  );

  return (
    <aside className={`sidebar ${isOpen ? "" : "sidebar--collapsed"}`}>
      <div className="sidebar__title">Nodes</div>
      {PALETTE.map((node) => (
        <div
          key={node.type}
          className="palette-item"
          onClick={() => handleNodeClick(node.type)}
          onDragStart={(e) => onDragStart(e, node.type)}
          draggable
          style={{ cursor: "pointer" }}
        >
          <span
            className="palette-item__dot"
            style={{ background: node.color }}
          />
          <span style={{ flex: 1 }}>{node.title}</span>
          <span className="palette-item__hint">{node.icon}</span>
        </div>
      ))}
      <div
        style={{
          marginTop: 16,
          padding: "10px 8px",
          fontSize: 11,
          color: "var(--text-muted)",
          lineHeight: 1.5,
          borderTop: "1px solid rgba(148,163,184,0.15)",
        }}
      >
        Click a node or drag it onto the canvas. Connect handles by dragging from a
        source (right) to a target (left).
      </div>
    </aside>
  );
}
