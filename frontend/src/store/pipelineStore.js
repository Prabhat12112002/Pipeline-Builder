/**
 * Pipeline store (zustand)
 * --------------------------------------------------------------
 * Holds reactflow nodes + edges and exposes mutators. The node
 * `data.onChange(id, key, value)` callback (used by BaseNode fields)
 * routes through here so field edits update reactflow state.
 */
import { create } from "zustand";
import { applyNodeChanges, applyEdgeChanges, addEdge } from "reactflow";
import { defaultNodeData } from "../nodes";

let nodeSeq = 1;

export const usePipelineStore = create((set, get) => ({
  nodes: [],
  edges: [],

  onNodesChange: (changes) =>
    set({ nodes: applyNodeChanges(changes, get().nodes) }),
  onEdgesChange: (changes) =>
    set({ edges: applyEdgeChanges(changes, get().edges) }),
  onConnect: (conn) =>
    set({
      edges: addEdge({ ...conn, animated: true }, get().edges),
    }),

  addNode: (type, position) => {
    const id = `${type}_${nodeSeq++}`;
    const node = {
      id,
      type,
      position,
      data: {
        ...defaultNodeData(type),
        onChange: (nodeId, key, value) => {
          set({
            nodes: get().nodes.map((n) =>
              n.id === nodeId
                ? { ...n, data: { ...n.data, [key]: value } }
                : n
            ),
          });
        },
      },
    };
    set({ nodes: [...get().nodes, node] });
    return id;
  },

  setNodes: (nodes) => set({ nodes }),
  setEdges: (edges) => set({ edges }),
}));

// Dev convenience: expose the store on window so it can be driven from
// the browser console or automated tests. Removed in production builds
// by the dead-code elimination of the `if (process.env.NODE_ENV ...)`
// guard.
if (typeof window !== "undefined" && process.env.NODE_ENV !== "production") {
  // eslint-disable-next-line no-undef
  window.__pipelineStore = usePipelineStore;
}
