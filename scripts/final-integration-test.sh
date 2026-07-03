#!/bin/bash
# ============================================================
# FINAL INTEGRATION TEST
# Runs every scenario from the assignment requirements + the
# security/edge-case audit. Everything in ONE bash session so
# detached servers stay alive.
# ============================================================
set -u

PASS=0; FAIL=0
ok()   { echo "✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "❌ $1"; FAIL=$((FAIL+1)); }

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

echo "### Waiting for servers..."
BE=000; FE=000
for i in $(seq 1 50); do
  BE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null)
  FE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null)
  [ "$BE" = "200" ] && [ "$FE" = "200" ] && break
  sleep 1
done
echo "Backend: $BE | Frontend: $FE"
[ "$BE" = "200" ] && ok "Backend /health returns 200" || bad "Backend not up"
[ "$FE" = "200" ] && ok "Frontend serves HTML" || bad "Frontend not up"

echo ""
echo "=========================================="
echo "### Backend unit tests (DAG + validation)"
echo "=========================================="

# DAG: linear
R=$(curl -s -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[{"id":"1"},{"id":"2"},{"id":"3"}],"edges":[{"source":"1","target":"2"},{"source":"2","target":"3"}]}')
echo "  linear: $R"
echo "$R" | grep -q '"is_dag":true' && ok "Linear graph is DAG" || bad "Linear graph should be DAG"

# Cycle
R=$(curl -s -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[{"id":"1"},{"id":"2"},{"id":"3"}],"edges":[{"source":"1","target":"2"},{"source":"2","target":"3"},{"source":"3","target":"1"}]}')
echo "  cycle: $R"
echo "$R" | grep -q '"is_dag":false' && ok "Cycle graph is NOT a DAG" || bad "Cycle should not be DAG"

# Self-loop
R=$(curl -s -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[{"id":"a"}],"edges":[{"source":"a","target":"a"}]}')
echo "  self-loop: $R"
echo "$R" | grep -q '"is_dag":false' && ok "Self-loop is NOT a DAG" || bad "Self-loop should not be DAG"

# Empty
R=$(curl -s -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[],"edges":[]}')
echo "  empty: $R"
echo "$R" | grep -q '"num_nodes":0.*"num_edges":0.*"is_dag":true' && ok "Empty pipeline is DAG" || bad "Empty should be DAG"

# Disconnected components (DAG)
R=$(curl -s -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[{"id":"a"},{"id":"b"},{"id":"c"},{"id":"d"}],"edges":[{"source":"a","target":"b"},{"source":"c","target":"d"}]}')
echo "  disconnected: $R"
echo "$R" | grep -q '"is_dag":true' && ok "Disconnected components are DAG" || bad "Disconnected should be DAG"

# Parallel edges
R=$(curl -s -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[{"id":"a"},{"id":"b"}],"edges":[{"source":"a","target":"b"},{"source":"a","target":"b"}]}')
echo "  parallel: $R"
echo "$R" | grep -q '"num_edges":2.*"is_dag":true' && ok "Parallel edges are DAG" || bad "Parallel edges should be DAG"

# Malformed: empty id → 422
SC=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":[{"id":""}],"edges":[]}')
echo "  empty-id status: $SC"
[ "$SC" = "422" ] && ok "Empty node id → 422" || bad "Empty id should be 422 (got $SC)"

# Malformed: non-list nodes → 422
SC=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/pipelines/parse -H "Content-Type: application/json" -d '{"nodes":"x","edges":[]}')
echo "  non-list status: $SC"
[ "$SC" = "422" ] && ok "Non-list nodes → 422" || bad "Non-list should be 422 (got $SC)"

# GET on POST endpoint → 405
SC=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/pipelines/parse)
echo "  GET status: $SC"
[ "$SC" = "405" ] && ok "GET on POST endpoint → 405" || bad "GET should be 405 (got $SC)"

# CORS preflight
SC=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS http://localhost:8000/pipelines/parse -H "Origin: http://localhost:3000" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: Content-Type")
echo "  CORS preflight status: $SC"
[ "$SC" = "200" ] && ok "CORS preflight from localhost:3000 → 200" || bad "CORS preflight failed ($SC)"

# CORS disallowed origin
HDR=$(curl -s -X OPTIONS http://localhost:8000/pipelines/parse -H "Origin: https://evil.example.com" -H "Access-Control-Request-Method: POST" -D - -o /dev/null | grep -i "access-control-allow-origin" || echo "none")
echo "  evil origin ACAO header: $HDR"
echo "$HDR" | grep -qi "evil" && bad "Evil origin reflected in CORS" || ok "Evil origin NOT reflected in CORS"

echo ""
echo "=========================================="
echo "### Frontend end-to-end (browser)"
echo "=========================================="
agent-browser close 2>/dev/null
agent-browser set viewport 1440 900 2>&1 | tail -1
agent-browser open http://localhost:3000 2>&1 | tail -2
agent-browser wait 3000

# Override alert to capture messages
agent-browser eval "
  window.__alertMsg = null;
  window.alert = function(msg) { window.__alertMsg = msg; return true; };
  'ready'
" 2>&1 | tail -1

echo ""
echo "--- Test: Empty pipeline submit ---"
agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -1
sleep 2
MSG=$(agent-browser eval "window.__alertMsg" 2>&1 | tail -1)
echo "  alert: $MSG"
echo "$MSG" | grep -q "Number of nodes: 0" && echo "$MSG" | grep -q "Is DAG: true" && ok "Empty pipeline alert correct" || bad "Empty pipeline alert wrong"

echo ""
echo "--- Test: DAG pipeline (3 nodes, 2 edges) ---"
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  s.setState({ nodes: [], edges: [] });
  const a = s.getState().addNode('input',  { x: 80,  y: 120 });
  const b = s.getState().addNode('llm',    { x: 360, y: 120 });
  const c = s.getState().addNode('output', { x: 640, y: 120 });
  s.getState().onConnect({ source: a, target: b });
  s.getState().onConnect({ source: b, target: c });
  return 'added';
})()
" 2>&1 | tail -1
agent-browser eval "window.__alertMsg = null;" 2>&1 | tail -1
agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -1
sleep 2
MSG=$(agent-browser eval "window.__alertMsg" 2>&1 | tail -1)
echo "  alert: $MSG"
echo "$MSG" | grep -q "Number of nodes: 3" && echo "$MSG" | grep -q "Number of edges: 2" && echo "$MSG" | grep -q "Is DAG: true" && ok "DAG pipeline alert correct" || bad "DAG pipeline alert wrong"

echo ""
echo "--- Test: Cycle pipeline (is_dag: false) ---"
# Create a cycle using nodes that have BOTH source and target handles
# (LLM nodes). Output→Input is blocked by onConnect validation because
# Output has no source handle — that's correct UI behavior.
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  s.setState({ nodes: [], edges: [] });
  const a = s.getState().addNode('llm', { x: 80,  y: 120 });
  const b = s.getState().addNode('llm', { x: 360, y: 120 });
  const c = s.getState().addNode('llm', { x: 640, y: 120 });
  s.getState().onConnect({ source: a, target: b });
  s.getState().onConnect({ source: b, target: c });
  s.getState().onConnect({ source: c, target: a }); // creates the cycle
  return JSON.stringify({nodes: s.getState().nodes.length, edges: s.getState().edges.length});
})()
" 2>&1 | tail -1
agent-browser eval "window.__alertMsg = null;" 2>&1 | tail -1
agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -1
sleep 2
MSG=$(agent-browser eval "window.__alertMsg" 2>&1 | tail -1)
echo "  alert: $MSG"
echo "$MSG" | grep -q "Is DAG: false" && ok "Cycle pipeline shows is_dag: false" || bad "Cycle alert wrong"

echo ""
echo "--- Test: Text node variable extraction ---"
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  s.setState({ nodes: [], edges: [] });
  const id = s.getState().addNode('text', { x: 200, y: 200 });
  const node = s.getState().nodes.find(n => n.id === id);
  node.data.onChange(id, 'text', 'Hello {{user}} {{user}} {{ 123 }} {{ 1abc }} {{ validName }}');
  return 'text set';
})()
" 2>&1 | tail -1
agent-browser wait 800
VARS=$(agent-browser eval "
(function(){
  return JSON.stringify(Array.from(document.querySelectorAll('.text-node__var-label')).map(e=>e.textContent));
})()
" 2>&1 | tail -1)
echo "  variable labels: $VARS"
# agent-browser eval returns a JSON-encoded string, so compare against
# the JSON form. Expected: ["user","validName"] (user deduped, 123/1abc rejected)
echo "$VARS" | grep -q 'user.*validName' && echo "$VARS" | grep -qv '123' && echo "$VARS" | grep -qv '1abc' && ok "Variable extraction: dedup + rejects invalid identifiers" || bad "Variable extraction wrong: $VARS"

echo ""
echo "--- Test: Remove all variables removes handles ---"
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  const tn = s.getState().nodes.find(n=>n.type==='text');
  tn.data.onChange(tn.id, 'text', 'No variables here');
  return 'cleared';
})()
" 2>&1 | tail -1
agent-browser wait 600
HCOUNT=$(agent-browser eval "document.querySelectorAll('.text-node__var-handle').length" 2>&1 | tail -1)
echo "  variable handle count after clearing: $HCOUNT"
[ "$HCOUNT" = "0" ] && ok "Handles removed when variables deleted" || bad "Handles not removed ($HCOUNT)"

echo ""
echo "--- Test: XSS attempt in text node ---"
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  const tn = s.getState().nodes.find(n=>n.type==='text');
  tn.data.onChange(tn.id, 'text', '<script>alert(1)</script> {{ <img src=x> }}');
  return 'xss attempt';
})()
" 2>&1 | tail -1
agent-browser wait 600
# Check no script tags were injected
SCRIPTS=$(agent-browser eval "document.querySelectorAll('script:not([src])').length" 2>&1 | tail -1)
echo "  inline script count after XSS attempt: $SCRIPTS"
# Check the text is displayed as text (escaped), not as HTML
TEXTAREA=$(agent-browser eval "
(function(){
  const ta = document.querySelector('.node-card__textarea');
  return ta ? ta.value : 'no textarea';
})()
" 2>&1 | tail -1)
echo "  textarea value: $TEXTAREA"
[ "$SCRIPTS" -le "1" ] && ok "No script injection from XSS attempt" || bad "Script injected!"

echo ""
echo "--- Test: Text node auto-resize caps at 400x300 ---"
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  const tn = s.getState().nodes.find(n=>n.type==='text');
  tn.data.onChange(tn.id, 'text', Array.from({length:50},(_,i)=>'Line '+i).join('\n') + ' '.repeat(600));
  return 'long text set';
})()
" 2>&1 | tail -1
agent-browser wait 800
DIMS=$(agent-browser eval "
(function(){
  const card = document.querySelector('.node-card');
  return card.offsetWidth + 'x' + card.offsetHeight;
})()
" 2>&1 | tail -1 | tr -d '"')
echo "  card dims: $DIMS"
W=$(echo "$DIMS" | cut -dx -f1)
H=$(echo "$DIMS" | cut -dx -f2)
[ "$W" -le "400" ] && [ "$H" -le "300" ] && ok "Text node caps at 400x300 (got ${W}x${H})" || bad "Text node exceeds caps (${W}x${H})"

echo ""
echo "--- Test: Network failure (backend down) ---"
# Kill the backend to simulate downtime
pkill -f "uvicorn main" 2>/dev/null
sleep 2
agent-browser eval "window.__alertMsg = null;" 2>&1 | tail -1
agent-browser find role button click --name "Submit Pipeline" 2>&1 | tail -1
sleep 2
MSG=$(agent-browser eval "window.__alertMsg" 2>&1 | tail -1)
echo "  alert: $MSG"
echo "$MSG" | grep -qi "Failed to parse pipeline" && ok "Network failure shows 'Failed to parse pipeline' alert" || bad "Network failure alert wrong: $MSG"

echo ""
echo "--- Test: All 9 node types render ---"
# Restart backend for any final checks
cd /home/z/my-project/backend
setsid uvicorn main:app --host 0.0.0.0 --port 8000 > /tmp/backend.log 2>&1 < /dev/null &
disown
sleep 3
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  s.setState({ nodes: [], edges: [] });
  ['input','output','llm','text','timer','email','filter','merge','debug'].forEach((t,i)=>{
    s.getState().addNode(t, { x: 80 + (i%3)*280, y: 80 + Math.floor(i/3)*220 });
  });
  return 'added 9';
})()
" 2>&1 | tail -1
agent-browser wait 1000
NCOUNT=$(agent-browser eval "document.querySelectorAll('.react-flow__node').length" 2>&1 | tail -1)
echo "  nodes on canvas: $NCOUNT"
[ "$NCOUNT" = "9" ] && ok "All 9 node types render" || bad "Expected 9 nodes, got $NCOUNT"

echo ""
echo "--- Test: Error boundary present ---"
# agent-browser eval returns JSON-encoded output, so "yes" comes back
# as '"yes"'. Strip the surrounding quotes for the comparison.
EB=$(agent-browser eval "document.querySelector('.app-shell') ? 'yes' : 'no'" 2>&1 | tail -1 | tr -d '"')
echo "  app-shell rendered: $EB"
[ "$EB" = "yes" ] && ok "App renders (error boundary not triggered)" || bad "App not rendering"

echo ""
echo "=========================================="
echo "### Console errors check"
echo "=========================================="
agent-browser console 2>&1 | grep -ivE "react-devtools|Download the React" | tail -10
PERR=$(agent-browser errors 2>&1 | tail -5)
echo "Page errors: $PERR"

echo ""
echo "=========================================="
echo "### FINAL SUMMARY"
echo "=========================================="
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo ""
if [ "$FAIL" -gt "0" ]; then
  echo "!!! $FAIL test(s) failed — see above."
  exit 1
else
  echo "🎉 ALL TESTS PASSED"
  exit 0
fi
