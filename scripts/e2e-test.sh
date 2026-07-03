#!/bin/bash
# End-to-end integration test for the Pipeline Builder.
# Runs entirely in one bash session so detached servers stay alive.
set -u

echo "### Killing any old servers"
pkill -f "uvicorn main" 2>/dev/null
pkill -f "react-scripts" 2>/dev/null
pkill -f "node.*start.js" 2>/dev/null
sleep 2

echo "### Starting backend"
cd /home/z/my-project/backend
setsid uvicorn main:app --host 0.0.0.0 --port 8000 > /tmp/backend.log 2>&1 < /dev/null &
disown

echo "### Starting frontend"
cd /home/z/my-project/frontend
setsid npm start > /tmp/frontend.log 2>&1 < /dev/null &
disown

echo "### Waiting for servers to come up..."
BE=000; FE=000
for i in $(seq 1 50); do
  BE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null)
  FE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null)
  if [ "$BE" = "200" ] && [ "$FE" = "200" ]; then
    echo "Both servers up after ${i}s (BE=$BE FE=$FE)"
    break
  fi
  sleep 1
done
echo "### Final: BE=$BE  FE=$FE"

if [ "$BE" != "200" ] || [ "$FE" != "200" ]; then
  echo "!!! Servers did not come up. Aborting."
  echo "--- backend log ---"; tail -20 /tmp/backend.log
  echo "--- frontend log ---"; tail -20 /tmp/frontend.log
  exit 1
fi

echo ""
echo "=========================================="
echo "### Opening browser at frontend"
echo "=========================================="
agent-browser close 2>/dev/null
agent-browser set viewport 1440 900 2>&1 | tail -1
agent-browser open http://localhost:3000 2>&1 | tail -3
agent-browser wait 3000

echo "### Initial screenshot (empty canvas)"
agent-browser screenshot /home/z/my-project/download/01-initial.png 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### TEST A: Submit on EMPTY pipeline"
echo "=========================================="
# Override window.alert to capture the message (more reliable than
# racing the native dialog with `dialog accept`).
agent-browser eval "
  window.__alertMsg = null;
  window.__alertCalls = 0;
  window.alert = function(msg) {
    window.__alertMsg = msg;
    window.__alertCalls++;
    return true;
  };
  'alert overridden'
" 2>&1 | tail -1

agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -2
sleep 2
echo "Captured alert:"
agent-browser eval "window.__alertMsg" 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### TEST B: Add 3 nodes + 2 edges (DAG), submit"
echo "=========================================="
agent-browser eval "
  const s = window.__pipelineStore;
  const st = s.getState();
  st.addNode('input',  { x: 80,  y: 120 });
  st.addNode('llm',    { x: 360, y: 120 });
  st.addNode('output', { x: 640, y: 120 });
  // Need the IDs to wire edges. addNode returns id.
  const nodes = s.getState().nodes;
  const [a,b,c] = nodes;
  s.getState().onConnect({ source: a.id, target: b.id });
  s.getState().onConnect({ source: b.id, target: c.id });
  JSON.stringify({nodes: nodes.length, edges: s.getState().edges.length})
" 2>&1 | tail -1
agent-browser wait 1000
agent-browser screenshot /home/z/my-project/download/02-three-nodes-dag.png 2>&1 | tail -1

# Reset alert capture and submit
agent-browser eval "window.__alertMsg = null; window.__alertCalls = 0;" 2>&1 | tail -1
agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -2
sleep 2
echo "Captured alert (DAG, expect 3 nodes / 2 edges / is_dag=true):"
agent-browser eval "window.__alertMsg" 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### TEST C: Add a cycle (C->A), submit (expect is_dag=false)"
echo "=========================================="
agent-browser eval "
  const s = window.__pipelineStore;
  const nodes = s.getState().nodes;
  const a = nodes.find(n => n.type === 'input');
  const c = nodes.find(n => n.type === 'output');
  s.getState().onConnect({ source: c.id, target: a.id });
  JSON.stringify({edges: s.getState().edges.length})
" 2>&1 | tail -1
agent-browser wait 800
agent-browser screenshot /home/z/my-project/download/03-cycle.png 2>&1 | tail -1

agent-browser eval "window.__alertMsg = null; window.__alertCalls = 0;" 2>&1 | tail -1
agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -2
sleep 2
echo "Captured alert (cycle, expect is_dag=false):"
agent-browser eval "window.__alertMsg" 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### TEST D: Text node with {{ name }} variable"
echo "=========================================="
agent-browser eval "
  const s = window.__pipelineStore;
  const id = s.getState().addNode('text', { x: 360, y: 360 });
  // Set the text to include a variable
  const node = s.getState().nodes.find(n => n.id === id);
  node.data.onChange(id, 'text', 'Hello {{ name }}, welcome to {{ city }}!');
  JSON.stringify({textNodeId: id})
" 2>&1 | tail -1
agent-browser wait 1000
agent-browser screenshot /home/z/my-project/download/04-text-node-vars.png 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### TEST E: Console errors check"
echo "=========================================="
agent-browser console 2>&1 | tail -15
echo "--- page errors ---"
agent-browser errors 2>&1 | tail -10

echo ""
echo "=========================================="
echo "### Backend log (request trail)"
echo "=========================================="
tail -12 /tmp/backend.log

echo ""
echo "### Done. Screenshots saved to /home/z/my-project/download/"
ls -la /home/z/my-project/download/*.png
