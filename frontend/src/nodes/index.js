/**
 * Node registry (Part 1)
 * --------------------------------------------------------------
 * Single source of truth for every node type in the app.
 *
 * Adding a new node is literally ~5 lines here — declare a config
 * object in NODE_CONFIGS and it automatically shows up in the
 * palette, the canvas, and the reactflow nodeTypes map.
 *
 *   timer: {
 *     title: 'Timer', icon: '⏱', color: 'var(--node-timer)',
 *     fields: [{ kind: 'number', key: 'delay', label: 'Delay (s)' }],
 *   }
 *
 * The Text node is the ONE exception — it needs dynamic handles +
 * auto-resize, so it has its own component file (TextNode.js) that
 * imports BaseNode for the visual skeleton but adds custom logic.
 */
import { createNode } from "./BaseNode";
import TextNode from "./TextNode";

/* ---------------- Existing nodes (refactored to use the factory) ---------------- */

const InputNode = createNode({
  type: "input",
  title: "Input",
  icon: "▶",
  badge: "Source",
  color: "var(--node-input)",
  source: true,
  target: false,
  fields: [
    {
      kind: "select",
      key: "inputType",
      label: "Input Type",
      options: [
        { value: "text", label: "Text" },
        { value: "file", label: "File" },
        { value: "url", label: "URL" },
      ],
    },
    { kind: "text", key: "name", label: "Field Name", placeholder: "user_query" },
  ],
  hint: "Start of the pipeline. Emits data downstream.",
});

const OutputNode = createNode({
  type: "output",
  title: "Output",
  icon: "■",
  badge: "Sink",
  color: "var(--node-output)",
  source: false,
  target: true,
  fields: [
    {
      kind: "select",
      key: "format",
      label: "Format",
      options: [
        { value: "json", label: "JSON" },
        { value: "text", label: "Text" },
        { value: "csv", label: "CSV" },
      ],
    },
  ],
  hint: "Terminal node — collects the final result.",
});

const LLMNode = createNode({
  type: "llm",
  title: "LLM",
  icon: "✦",
  color: "var(--node-llm)",
  fields: [
    {
      kind: "select",
      key: "model",
      label: "Model",
      options: [
        { value: "gpt-4o", label: "GPT-4o" },
        { value: "gpt-4o-mini", label: "GPT-4o mini" },
        { value: "claude-3.5-sonnet", label: "Claude 3.5 Sonnet" },
        { value: "glm-4", label: "GLM-4" },
      ],
    },
    { kind: "number", key: "temperature", label: "Temperature", min: 0, max: 2, step: 0.1 },
    { kind: "textarea", key: "systemPrompt", label: "System Prompt", rows: 3 },
  ],
  hint: "Calls a language model with the upstream payload.",
});

/* ---------------- 5 NEW nodes (demonstrate the abstraction) ---------------- */

const TimerNode = createNode({
  type: "timer",
  title: "Timer",
  icon: "⏱",
  badge: "Delay",
  color: "var(--node-timer)",
  fields: [
    { kind: "number", key: "delay", label: "Delay (seconds)", min: 0, step: 1 },
    {
      kind: "select",
      key: "mode",
      label: "Mode",
      options: [
        { value: "once", label: "Run once" },
        { value: "interval", label: "Recurring" },
      ],
    },
  ],
  hint: "Pauses execution for the configured delay.",
});

const EmailNode = createNode({
  type: "email",
  title: "Email",
  icon: "✉",
  color: "var(--node-email)",
  fields: [
    { kind: "text", key: "to", label: "To", placeholder: "user@example.com" },
    { kind: "text", key: "subject", label: "Subject", placeholder: "Pipeline result" },
    { kind: "textarea", key: "body", label: "Body", rows: 3 },
  ],
  hint: "Sends an email with the upstream payload as the body.",
});

const FilterNode = createNode({
  type: "filter",
  title: "Filter",
  icon: "▽",
  color: "var(--node-filter)",
  fields: [
    {
      kind: "select",
      key: "operator",
      label: "Operator",
      options: [
        { value: "contains", label: "contains" },
        { value: "equals", label: "equals" },
        { value: "greater_than", label: "greater than" },
        { value: "less_than", label: "less than" },
        { value: "regex", label: "regex match" },
      ],
    },
    { kind: "text", key: "value", label: "Compare To", placeholder: "expected value" },
  ],
  hint: "Passes payload downstream only if the condition is met.",
});

const MergeNode = createNode({
  type: "merge",
  title: "Merge",
  icon: "⋈",
  badge: "2→1",
  color: "var(--node-merge)",
  source: true,
  target: true,
  fields: [
    {
      kind: "select",
      key: "strategy",
      label: "Strategy",
      options: [
        { value: "concat", label: "Concatenate" },
        { value: "object", label: "Merge as object" },
        { value: "array", label: "Combine as array" },
      ],
    },
  ],
  hint: "Joins two upstream branches into a single payload.",
});

const DebugNode = createNode({
  type: "debug",
  title: "Debug",
  icon: "⌖",
  color: "var(--node-debug)",
  fields: [
    {
      kind: "select",
      key: "logLevel",
      label: "Log Level",
      options: [
        { value: "info", label: "Info" },
        { value: "warn", label: "Warn" },
        { value: "error", label: "Error" },
      ],
    },
    {
      kind: "stat",
      key: "lastValue",
      label: "Last Payload",
    },
  ],
  hint: "Logs the upstream payload to the console without mutating it.",
});

/* ---------------- reactflow nodeTypes map ---------------- */

export const nodeTypes = {
  input: InputNode,
  output: OutputNode,
  llm: LLMNode,
  text: TextNode, // custom — see TextNode.js
  timer: TimerNode,
  email: EmailNode,
  filter: FilterNode,
  merge: MergeNode,
  debug: DebugNode,
};

/* ---------------- Palette metadata (for the sidebar) ---------------- */

export const PALETTE = [
  { type: "input", title: "Input", icon: "▶", color: "var(--node-input)" },
  { type: "output", title: "Output", icon: "■", color: "var(--node-output)" },
  { type: "llm", title: "LLM", icon: "✦", color: "var(--node-llm)" },
  { type: "text", title: "Text", icon: "T", color: "var(--node-text)" },
  { type: "timer", title: "Timer", icon: "⏱", color: "var(--node-timer)" },
  { type: "email", title: "Email", icon: "✉", color: "var(--node-email)" },
  { type: "filter", title: "Filter", icon: "▽", color: "var(--node-filter)" },
  { type: "merge", title: "Merge", icon: "⋈", color: "var(--node-merge)" },
  { type: "debug", title: "Debug", icon: "⌖", color: "var(--node-debug)" },
];

/* Default data factory — gives each new node sensible starting values */
export function defaultNodeData(type) {
  switch (type) {
    case "input":
      return { inputType: "text", name: "user_query" };
    case "output":
      return { format: "json" };
    case "llm":
      return {
        model: "gpt-4o-mini",
        temperature: 0.7,
        systemPrompt: "You are a helpful assistant.",
      };
    case "text":
      return { text: "" };
    case "timer":
      return { delay: 5, mode: "once" };
    case "email":
      return { to: "", subject: "", body: "" };
    case "filter":
      return { operator: "contains", value: "" };
    case "merge":
      return { strategy: "concat" };
    case "debug":
      return { logLevel: "info", lastValue: "(none)" };
    default:
      return {};
  }
}
