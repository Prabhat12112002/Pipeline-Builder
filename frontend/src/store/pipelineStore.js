/**
 * Pipeline store (zustand)
 * --------------------------------------------------------------
 * Holds reactflow nodes + edges and exposes mutators. The node
 * `data.onChange(id, key, value)` callback (used by BaseNode fields)
 * routes through here so field edits update reactflow state.
 *
 * Connection validation: onConnect rejects edges that start from a
 * node with no source handle or end at a node with no target handle
 * (e.g. Output → Input is invalid because Output has no source).
 * This prevents invisible/dangling edges and React Flow warnings.
 */
import { create } from "zustand";
import { applyNodeChanges, applyEdgeChanges, addEdge } from "reactflow";
import { defaultNodeData } from "../nodes";

let nodeSeq = 1;

// Pre-compute which node types have source/target handles by reading
// the config. The factory-wrapped nodes store their config on the
// component; the Text node always has both handles. We use a static
// map keyed by type for O(1) lookups in onConnect.
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

  onNodesChange: (changes) =>
    set({ nodes: applyNodeChanges(changes, get().nodes) }),
  onEdgesChange: (changes) =>
    set({ edges: applyEdgeChanges(changes, get().edges) }),

  // Validate the connection before adding it: both endpoints must
  // exist and the source node must have a source handle, the target
  // node must have a target handle.
  onConnect: (conn) => {
    const { nodes } = get();
    const srcNode = nodes.find((n) => n.id === conn.source);
    const tgtNode = nodes.find((n) => n.id === conn.target);
    if (!srcNode || !tgtNode) return;
    const srcConfig = HANDLE_MAP[srcNode.type];
    const tgtConfig = HANDLE_MAP[tgtNode.type];
    if (!srcConfig?.source || !tgtConfig?.target) return;
    set({
      edges: addEdge({ ...conn, animated: true }, get().edges),
    });
  },

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
// the browser console or automated tests. The process.env.NODE_ENV
// guard ensures CRA's production build dead-code-eliminates this.
if (typeof window !== "undefined" && process.env.NODE_ENV !== "production") {
  // eslint-disable-next-line no-undef
  window.__pipelineStore = usePipelineStore;
}
