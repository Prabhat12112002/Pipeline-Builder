/**
 * Sidebar — draggable node palette.
 * Each item is a reactflow DnD source. Drag onto the canvas to create
 * a new node of that type.
 */
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
        <div
          key={node.type}
          className="palette-item"
          onDragStart={(e) => onDragStart(e, node.type)}
          draggable
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
        Drag a node onto the canvas. Connect handles by dragging from a
        source (right) to a target (left).
      </div>
    </aside>
  );
}
