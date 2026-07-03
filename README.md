# ⌁ Visual Pipeline Builder

A sleek, premium, and professional node-based workflow editor built on **React + React Flow** (Frontend) and **Python + FastAPI** (Backend). Drag-and-drop components, connect data streams, and analyze structures with automated cycle detection (DAG validation).

---

## ✦ Key Features

- **✦ BaseNode Abstraction Layer** – A modular config DSL factory in `BaseNode.js` that reduces boilerplate. Declarative configurations allow spawning complex new nodes in under 10 lines of code.
- **✦ Live Templating (Text Node)** – Dynamic variable detection using regex parsing. Typing `{{ variable }}` dynamically instantiates a new target handle on the left edge.
- **✦ Interactive UI & Space Optimization** – Responsive side navigation containing the node palette that can be collapsed/expanded via a sleek, unified **Hide Sidebar** SVG control.
- **✦ Animated Zoom & Pan** – Responsive canvas fitting with custom margin buffers (`0.2`) and animated transitions.
- **✦ Directed Acyclic Graph (DAG) Check** – High-performance cycle checking powered by a 3-color DFS traversal algorithm (WHITE/GRAY/BLACK marking) to identify recursive execution loops.
- **✦ Security Hardened** – Robust CORS origin allowlist configurations, Pydantic input validation, generic error masking, and full protection against XSS vulnerabilities.

---

## 📦 Project Architecture

```
Pipeline-Builder/
├── frontend/              # React Application
│   ├── public/            # Public assets & entry template
│   ├── src/
│   │   ├── components/    # Reusable layout UI components
│   │   ├── nodes/         # BaseNode engine & custom configurations
│   │   ├── store/         # Zustand global state (nodes & edges)
│   │   ├── styles/        # Global CSS design system
│   │   └── submit.js      # Backend integration layers
│   └── package.json
│
└── backend/               # FastAPI Application
    ├── main.py            # API routing, validations & DAG analysis
    └── requirements.txt   # Pinned backend dependencies
```

---

## 🚀 Quick Start (Development)

### 1. Backend Service (FastAPI)
Navigate to the `backend` directory, set up your python environment, and start the development server:

```bash
cd backend

# Create & activate a virtual environment
python -m venv .venv
source .venv/bin/activate      # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start the uvicorn server
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```
- Interactive Swagger docs: [http://localhost:8000/docs](http://localhost:8000/docs)
- Uptime monitoring /health: [http://localhost:8000/health](http://localhost:8000/health)

### 2. Frontend client (React)
Navigate to the `frontend` directory, install package dependencies, and spin up the Webpack dev-server:

```bash
cd frontend

# Install packages
npm install

# Start the React dev-server
npm start
```
- Open client: [http://localhost:3000](http://localhost:3000)

---

## 🛠 Tech Stack

- **Frontend Core:** React, React Flow, Zustand (State Management)
- **Styling:** Vanilla CSS Custom Variables (Design System)
- **Backend Core:** FastAPI, Pydantic V2, Starlette
- **Server:** Uvicorn (ASGI)

---

## 🔒 Security Hardening Summary

| Category | Implementation Strategy |
|---|---|
| **CORS Policy** | REST API restricts incoming requests to trusted frontend domains (`ALLOWED_ORIGINS` env configuration). Wildcards (`*`) are disallowed to prevent security leaks. |
| **Data Validation** | Pydantic V2 schemas enforce strict types, reject blank IDs, and restrict payload bounds to mitigate Denial of Service (DoS) attacks. |
| **Error Handling** | Catch-all middleware sanitizes internal stack traces. The client receives a generic `500 Internal server error` message, while the exact trace is logged on the server. |
| **XSS Prevention** | React dynamically escapes DOM interpolation. The Text node regular expression filters and restricts variable extraction strictly to safe JavaScript identifiers `[A-Za-z0-9_$]`. |
