/**
 * submit.js (Part 4 — Frontend)
 * --------------------------------------------------------------
 * Collects the current pipeline (nodes + edges) and POSTs it to the
 * FastAPI backend at POST /pipelines/parse. On success, shows a
 * friendly alert with num_nodes / num_edges / is_dag. Network and
 * server errors are surfaced as alerts too.
 *
 * The backend API base URL is configurable via the
 * `REACT_APP_API_URL` environment variable (see `.env.example`).
 * It defaults to http://localhost:8000 for local development.
 *
 * XSS safety: the alert message is built from server-returned
 * numbers/booleans only — no user-supplied string is interpolated
 * into the DOM. The `alert()` call is a native browser dialog and
 * cannot execute HTML/script.
 */

/**
 * Base URL of the backend API. Configurable via env var so the same
 * build can target staging/prod without code changes.
 */
const API_BASE_URL =
  process.env.REACT_APP_API_URL || "http://localhost:8000";

const ENDPOINT = `${API_BASE_URL}/pipelines/parse`;

/**
 * Submit the current pipeline to the backend for analysis.
 * @param {Array} nodes  — reactflow nodes array
 * @param {Array} edges  — reactflow edges array
 * @returns {Promise<{num_nodes:number, num_edges:number, is_dag:boolean}>}
 */
export async function submitPipeline(nodes, edges) {
  // Strip reactflow-internal fields to keep the payload lean but
  // preserve everything the backend (and any future feature) needs.
  const payload = {
    nodes: (nodes ?? []).map((n) => ({
      id: n.id,
      type: n.type,
      data: n.data,
      position: n.position,
    })),
    edges: (edges ?? []).map((e) => ({
      id: e.id,
      source: e.source,
      target: e.target,
      sourceHandle: e.sourceHandle ?? null,
      targetHandle: e.targetHandle ?? null,
    })),
  };

  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    // Network error — backend not running, wrong URL, or CORS
    // preflight failed. Surface a clear, actionable message.
    throw new Error(
      `Could not reach the backend at ${API_BASE_URL}.\n` +
        `Is the FastAPI server running? ` +
        `(cd backend && uvicorn main:app --reload)\n` +
        `Detail: ${err.message}`
    );
  }

  if (!response.ok) {
    let detail = "";
    try {
      const errBody = await response.json();
      // Pydantic 422 returns { detail: [...] }; flatten for display.
      if (Array.isArray(errBody.detail)) {
        detail = errBody.detail
          .map((d) => d.msg || JSON.stringify(d))
          .join("; ");
      } else {
        detail = errBody.detail || JSON.stringify(errBody);
      }
    } catch (_) {
      detail = await response.text().catch(() => "");
    }
    throw new Error(
      `Backend returned ${response.status} ${response.statusText}` +
        (detail ? `\n${detail}` : "")
    );
  }

  return response.json();
}

/**
 * Build the friendly alert message from the backend response.
 * Only numbers and a boolean are interpolated — no user input —
 * so there is no XSS surface even if alert() were replaced.
 */
export function formatResult(result) {
  const dag = result.is_dag ? "true ✓" : "false ✗";
  return (
    `Pipeline Analysis:\n` +
    `Number of nodes: ${result.num_nodes}\n` +
    `Number of edges: ${result.num_edges}\n` +
    `Is DAG: ${dag}`
  );
}

/**
 * One-shot helper used by the Submit button: calls submitPipeline,
 * alerts the result, and alerts on error. Returns the raw result on
 * success so callers can do more with it.
 */
export async function submitAndAlert(nodes, edges) {
  try {
    const result = await submitPipeline(nodes, edges);
    alert(formatResult(result));
    return result;
  } catch (err) {
    alert(`Failed to parse pipeline:\n${err.message}`);
    throw err;
  }
}
