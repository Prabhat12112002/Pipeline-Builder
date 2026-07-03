#!/bin/bash
# Continuation test: cycle detection + text node variable handles.
# Assumes servers are already running from the previous e2e-test.sh run.
set -u

echo "### Server status"
curl -s -o /dev/null -w "backend HTTP %{http_code}\n" http://localhost:8000/
curl -s -o /dev/null -w "frontend HTTP %{http_code}\n" http://localhost:3000/

echo ""
echo "=========================================="
echo "### TEST C (fixed): Add a cycle, expect is_dag=false"
echo "=========================================="
# Use an IIFE so `const` doesn't leak across eval calls.
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  const nodes = s.getState().nodes;
  const a = nodes.find(n => n.type === 'input');
  const c = nodes.find(n => n.type === 'output');
  s.getState().onConnect({ source: c.id, target: a.id });
  return JSON.stringify({totalEdges: s.getState().edges.length});
})()
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
echo "### TEST D (fixed): Text node with {{ name }} + {{ city }} variables"
echo "=========================================="
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  const id = s.getState().addNode('text', { x: 360, y: 420 });
  const node = s.getState().nodes.find(n => n.id === id);
  node.data.onChange(id, 'text', 'Hello {{ name }}, welcome to {{ city }}!');
  return JSON.stringify({textNodeId: id});
})()
" 2>&1 | tail -1
agent-browser wait 1000
agent-browser screenshot /home/z/my-project/download/04-text-node-vars.png 2>&1 | tail -1

# Verify the variable handles were created by inspecting the DOM
echo ""
echo "### Verify variable handles exist in the DOM:"
agent-browser eval "
(function(){
  const handles = document.querySelectorAll('.react-flow__handle');
  const varHandles = document.querySelectorAll('.text-node__var-handle');
  const varLabels = Array.from(document.querySelectorAll('.text-node__var-label')).map(e => e.textContent);
  return JSON.stringify({
    totalHandles: handles.length,
    variableHandles: varHandles.length,
    variableLabels: varLabels
  });
})()
" 2>&1 | tail -1

echo ""
echo "### Verify the text node has auto-resized (check its width):"
agent-browser eval "
(function(){
  const textareas = document.querySelectorAll('.node-card__textarea');
  if (textareas.length === 0) return 'no textareas';
  const last = textareas[textareas.length - 1];
  const card = last.closest('.node-card');
  return JSON.stringify({
    textareaWidth: last.offsetWidth,
    textareaHeight: last.offsetHeight,
    cardWidth: card.offsetWidth,
    cardHeight: card.offsetHeight
  });
})()
" 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### TEST E: Add ALL 5 new node types to verify the abstraction"
echo "=========================================="
agent-browser eval "
(function(){
  const s = window.__pipelineStore;
  const types = ['timer','email','filter','merge','debug'];
  const ids = types.map((t, i) => s.getState().addNode(t, { x: 80 + i*260, y: 560 }));
  return JSON.stringify({added: ids.length, types});
})()
" 2>&1 | tail -1
agent-browser wait 1000
agent-browser screenshot /home/z/my-project/download/05-all-five-new-nodes.png 2>&1 | tail -1

echo ""
echo "### Count all node cards currently on canvas:"
agent-browser eval "document.querySelectorAll('.react-flow__node').length" 2>&1 | tail -1

echo ""
echo "=========================================="
echo "### Final backend log"
echo "=========================================="
tail -8 /tmp/backend.log

echo ""
echo "### Screenshots:"
ls -la /home/z/my-project/download/*.png
