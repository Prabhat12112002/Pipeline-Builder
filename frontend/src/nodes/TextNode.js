/**
 * TextNode (Part 3)
 * --------------------------------------------------------------
 * Two custom behaviours on top of the shared node-card skeleton:
 *
 *  1. AUTO-RESIZE
 *     The textarea's width/height grow to fit content, capped so the
 *     ENTIRE node card stays within 400px wide × 300px tall. We
 *     measure the card's "chrome" (header + padding + hint) live and
 *     subtract it from MAX_HEIGHT to get the textarea's height budget.
 *
 *  2. DYNAMIC VARIABLE HANDLES
 *     Scanning the text for `{{ variableName }}` patterns and rendering
 *     one left-side target Handle per unique variable. Handles are
 *     removed when the variable is deleted from the text. The default
 *     target handle is always preserved.
 *
 * VARIABLE REGEX CHOICE & XSS SAFETY
 *   The regex `/\{\{\s*([A-Za-z_$][\w$]*)\s*\}\}/g` only captures
 *   valid JavaScript identifiers (letter/underscore/$ followed by
 *   word chars or $). This deliberately rejects:
 *     - `{{ 123 }}`      (starts with a digit)
 *     - `{{ 1abc }}`     (starts with a digit)
 *     - `{{ a-b }}`      (hyphen is not a valid identifier char)
 *     - `{{ <script> }}` (angle brackets aren't identifier chars)
 *   Because captured names are restricted to `[A-Za-z0-9_$]`, they
 *   cannot contain HTML and are safe to render as handle IDs and
 *   text labels. React's JSX `{name}` auto-escapes regardless, so
 *   there is no XSS vector even if a name somehow contained markup.
 *
 *   Internal spaces inside the braces are tolerated and trimmed:
 *     `{{ name }}`, `{{name}}`, `{{  name  }}` all extract "name".
 *
 * Variables are de-duplicated, preserving insertion order so handle
 * positions stay stable while typing.
 */
import React, { useCallback, useEffect, useRef, useMemo } from "react";
import { Handle, Position } from "reactflow";

const MAX_WIDTH = 400;
const MIN_WIDTH = 220;
const MAX_HEIGHT = 300;

// Match {{ name }} where `name` is a valid JS identifier. Internal
// whitespace inside the braces is allowed and trimmed. See header
// comment for the security rationale behind this character class.
const VAR_REGEX = /\{\{\s*([A-Za-z_$][\w$]*)\s*\}\}/g;

function extractVariables(text) {
  if (!text) return [];
  const seen = new Set();
  const ordered = [];
  let m;
  // Reset lastIndex because the regex has the global flag.
  VAR_REGEX.lastIndex = 0;
  while ((m = VAR_REGEX.exec(text)) !== null) {
    const name = m[1];
    if (!seen.has(name)) {
      seen.add(name);
      ordered.push(name);
    }
  }
  return ordered;
}

export default function TextNode({ id, data }) {
  const textareaRef = useRef(null);
  const text = data?.text ?? "";

  const variables = useMemo(() => extractVariables(text), [text]);

  const onChange = useCallback(
    (key, value) => {
      if (typeof data?.onChange === "function") {
        data.onChange(id, key, value);
      }
    },
    [data, id]
  );

  // Auto-resize: measure scroll dimensions and clamp so the ENTIRE
  // node card stays within 400×300. We compute the "chrome" height
  // (header + body padding + hint) dynamically and subtract it from
  // MAX_HEIGHT to get the textarea's available height budget.
  const resize = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    const card = el.closest(".node-card");
    if (!card) return;

    // Reset textarea size so scrollHeight/scrollWidth reflect content.
    el.style.height = "auto";
    el.style.width = "auto";

    // Chrome height = everything in the card EXCEPT the textarea
    // (header, body padding, hint, gaps). Measured live so we stay
    // accurate even if the hint line wraps.
    const chromeHeight = Math.max(0, card.offsetHeight - el.offsetHeight);

    const availableHeight = Math.max(40, MAX_HEIGHT - chromeHeight);
    const newHeight = Math.min(el.scrollHeight, availableHeight);

    // Width: grow to fit, clamped to [MIN_WIDTH, MAX_WIDTH].
    const newWidth = Math.min(
      Math.max(el.scrollWidth, MIN_WIDTH),
      MAX_WIDTH
    );

    el.style.height = `${newHeight}px`;
    el.style.width = `${newWidth}px`;
  }, []);

  // Re-measure whenever the text changes (including programmatic edits).
  useEffect(() => {
    resize();
  }, [text, resize]);

  // Re-measure on mount.
  useEffect(() => {
    resize();
  }, [resize]);

  const handleChange = (e) => {
    onChange("text", e.target.value);
  };

  return (
    <div
      className="node-card"
      style={{
        width: "auto",
        minWidth: MIN_WIDTH,
        maxWidth: MAX_WIDTH,
        position: "relative",
      }}
    >
      {/* Source handle on the right */}
      <Handle
        type="source"
        position={Position.Right}
        style={{ borderColor: "var(--node-text)" }}
      />

      {/* Header strip (re-use BaseNode's styling via a matching markup) */}
      <div className="node-card__header">
        <span
          className="node-card__icon"
          style={{ background: "var(--node-text)" }}
        >
          T
        </span>
        <span className="node-card__title">Text</span>
        <span className="node-card__badge">Template</span>
      </div>

      <div className="node-card__body" style={{ alignItems: "stretch" }}>
        <textarea
          ref={textareaRef}
          className="node-card__textarea"
          value={text}
          placeholder="Type here… use {{ name }} to inject variables"
          onChange={handleChange}
          rows={2}
          style={{
            width: "100%",
            height: "auto",
            maxWidth: MAX_WIDTH - 24,
            overflow: "hidden",
            overflowWrap: "anywhere",
          }}
        />
        <div className="node-card__hint">
          {variables.length > 0
            ? `Variables: ${variables.join(", ")}`
            : "Tip: write {{ name }} to add an input handle."}
        </div>
      </div>

      {/* Default target handle on the left (kept for top-level input) */}
      <Handle
        type="target"
        position={Position.Left}
        id="__default__"
        style={{
          borderColor: "var(--node-text)",
          top: "50%",
        }}
      />

      {/* Dynamic variable handles — one per {{ var }} on the left,
          stacked below the default handle. */}
      {variables.map((name, i) => {
        const offset = 50 + (i + 1) * 22; // px from top of node
        return (
          <React.Fragment key={name}>
            <Handle
              type="target"
              position={Position.Left}
              id={`var__${name}`}
              className="text-node__var-handle"
              style={{ top: `${offset}px` }}
            />
            <span
              className="text-node__var-label"
              style={{ top: `${offset}px` }}
            >
              {name}
            </span>
          </React.Fragment>
        );
      })}
    </div>
  );
}
