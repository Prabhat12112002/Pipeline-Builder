/**
 * BaseNode — the shared node abstraction (Part 1)
 * --------------------------------------------------------------
 * Every node in the pipeline builder shares the same skeleton:
 *   - a colored header strip (icon + title + badge)
 *   - a body with zero or more form fields
 *   - a right "source" handle and/or a left "target" handle
 *
 * Instead of copy-pasting that skeleton into Input/Output/LLM/Text/
 * Timer/Email/etc., we declare a node as a plain config object and
 * `createNode(config)` returns a ready-to-use React component.
 *
 * A "field" is one of:
 *   { kind: 'text',    key, label, placeholder? }
 *   { kind: 'textarea',key, label, placeholder?, rows? }
 *   { kind: 'number',  key, label, min?, max?, step? }
 *   { kind: 'select',  key, label, options: [{value,label}] }
 *   { kind: 'stat',    key, label }              // read-only value display
 *   { kind: 'custom',  key, render: ({value, onChange, data, id}) => ReactNode }
 *
 * Node config shape:
 *   {
 *     type:   'timer',                 // reactflow node type id
 *     title:  'Timer',
 *     icon:   '⏱',                     // emoji or short glyph
 *     color:  'var(--node-timer)',     // css var or hex
 *     badge?: 'Source',                // small uppercase tag
 *     source?: true,                   // show right source handle (default true)
 *     target?: true,                   // show left target handle (default true)
 *     fields: [ ...fieldDefs ],
 *     minWidth?: 220,
 *   }
 *
 * Field values are stored on `data` (reactflow node data) under the
 * field's `key`. The component calls `data.onChange(id, key, value)`
 * to mutate state — wired up by the parent store.
 */
import React, { useCallback } from "react";
import { Handle, Position } from "reactflow";

/* ---------------- Field renderers ---------------- */

function TextField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <input
        className="node-card__input"
        type="text"
        value={value ?? ""}
        placeholder={field.placeholder}
        onChange={(e) => onChange(field.key, e.target.value)}
      />
    </div>
  );
}

function TextareaField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <textarea
        className="node-card__textarea"
        rows={field.rows ?? 3}
        value={value ?? ""}
        placeholder={field.placeholder}
        onChange={(e) => onChange(field.key, e.target.value)}
      />
    </div>
  );
}

function NumberField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <input
        className="node-card__input"
        type="number"
        min={field.min}
        max={field.max}
        step={field.step ?? 1}
        value={value ?? ""}
        onChange={(e) =>
          onChange(field.key, e.target.value === "" ? "" : Number(e.target.value))
        }
      />
    </div>
  );
}

function SelectField({ field, value, onChange }) {
  return (
    <div className="node-card__field">
      {field.label && <label className="node-card__label">{field.label}</label>}
      <select
        className="node-card__select"
        value={value ?? ""}
        onChange={(e) => onChange(field.key, e.target.value)}
      >
        {field.options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}

function StatField({ field, value }) {
  return (
    <div className="node-card__stat">
      <span>{field.label}</span>
      <span className="node-card__stat-value">{String(value ?? "—")}</span>
    </div>
  );
}

const FIELD_COMPONENTS = {
  text: TextField,
  textarea: TextareaField,
  number: NumberField,
  select: SelectField,
  stat: StatField,
};

/* ---------------- BaseNode component ---------------- */

function BaseNode({ id, data, config, children }) {
  const onChange = useCallback(
    (key, value) => {
      if (typeof data?.onChange === "function") {
        data.onChange(id, key, value);
      }
    },
    [data, id]
  );

  const showSource = config.source !== false;
  const showTarget = config.target !== false;
  const minWidth = config.minWidth ?? 220;
  const maxWidth = config.maxWidth;
  const width = config.width;

  return (
    <div className="node-card" style={{ minWidth, maxWidth, width }}>
      {showSource && (
        <Handle
          type="source"
          position={Position.Right}
          {...(config.sourceId ? { id: config.sourceId } : {})}
          style={{ borderColor: config.color, ...config.sourceStyle }}
        />
      )}

      <div className="node-card__header">
        <span
          className="node-card__icon"
          style={{ background: config.color }}
        >
          {config.icon}
        </span>
        <span className="node-card__title">{config.title}</span>
        {config.badge && <span className="node-card__badge">{config.badge}</span>}
      </div>

      <div className="node-card__body">
        {config.fields.map((field) => {
          if (field.kind === "custom") {
            return (
              <div className="node-card__field" key={field.key}>
                {field.label && (
                  <label className="node-card__label">{field.label}</label>
                )}
                {field.render({
                  value: data?.[field.key],
                  onChange: (v) => onChange(field.key, v),
                  data,
                  id,
                })}
              </div>
            );
          }
          const Comp = FIELD_COMPONENTS[field.kind];
          if (!Comp) return null;
          return (
            <Comp
              key={field.key}
              field={field}
              value={data?.[field.key]}
              onChange={onChange}
            />
          );
        })}

        {config.hint && <div className="node-card__hint">{config.hint}</div>}
      </div>

      {showTarget && (
        <Handle
          type="target"
          position={Position.Left}
          {...(config.targetId ? { id: config.targetId } : {})}
          style={{ borderColor: config.color, ...config.targetStyle }}
        />
      )}

      {children}
    </div>
  );
}

/* ---------------- Factory: createNode(config) ---------------- */

/**
 * Given a node config object, returns a React component usable as a
 * reactflow node type. New nodes can be added in ~5 lines:
 *
 *   export default createNode({
 *     type: 'timer', title: 'Timer', icon: '⏱',
 *     color: 'var(--node-timer)',
 *     fields: [{ kind: 'number', key: 'delay', label: 'Delay (s)' }],
 *   });
 */
export function createNode(config) {
  const Component = React.memo(function CreatedNode(props) {
    return <BaseNode {...props} config={config} />;
  });
  Component.displayName = `${config.type}_Node`;
  return Component;
}

/* Re-export BaseNode for nodes that need custom rendering beyond the
   config DSL (e.g. the Text node with dynamic handles + auto-resize). */
export { BaseNode };

export default BaseNode;
