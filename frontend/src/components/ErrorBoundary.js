/**
 * ErrorBoundary
 * --------------------------------------------------------------
 * Catches uncaught rendering errors anywhere in the child tree and
 * shows a friendly fallback UI instead of a white screen. Errors are
 * logged to the console (in production, route to your error tracker).
 *
 * React requires error boundaries to be class components (as of
 * React 18 there is no hook equivalent).
 */
import React from "react";

export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    // In production, forward to Sentry / Datadog / etc.
    // eslint-disable-next-line no-console
    console.error("Uncaught error:", error, errorInfo);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      return (
        <div
          style={{
            height: "100vh",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 16,
            background: "#0f172a",
            color: "#e2e8f0",
            fontFamily:
              '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
            padding: 24,
            textAlign: "center",
          }}
        >
          <div style={{ fontSize: 48 }}>⚠️</div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700 }}>
            Something went wrong
          </h1>
          <p style={{ margin: 0, color: "#94a3b8", maxWidth: 420 }}>
            An unexpected error occurred while rendering the pipeline
            builder. You can try reloading the page.
          </p>
          <button
            onClick={() => window.location.reload()}
            style={{
              marginTop: 8,
              padding: "10px 20px",
              borderRadius: 10,
              border: "none",
              background: "linear-gradient(135deg, #6366f1, #8b5cf6)",
              color: "#fff",
              fontSize: 14,
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            Reload page
          </button>
          {this.state.error && (
            <details
              style={{
                marginTop: 16,
                maxWidth: 600,
                color: "#64748b",
                fontSize: 12,
              }}
            >
              <summary style={{ cursor: "pointer" }}>Error details</summary>
              <pre
                style={{
                  textAlign: "left",
                  overflow: "auto",
                  background: "#1e293b",
                  padding: 12,
                  borderRadius: 8,
                  marginTop: 8,
                }}
              >
                {this.state.error?.message || String(this.state.error)}
              </pre>
            </details>
          )}
        </div>
      );
    }

    return this.props.children;
  }
}
