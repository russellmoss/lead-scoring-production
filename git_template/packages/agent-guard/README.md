# agent-guard

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18-brightgreen.svg)](https://nodejs.org)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

<p align="center">
  <img src="docs/assets/demo.gif" alt="agent-guard pre-commit hook catching documentation drift" width="750" />
</p>

---

## The Problem: Context Rot

Every codebase tells two stories: the code itself, and the documentation that explains it. Over time, these stories diverge. A developer adds a new API route but forgets to update the docs. Another renames an environment variable but doesn't touch the README. A third refactors the database schema while the architecture doc still references the old model names.

This is **Context Rot** — the slow decay of documentation accuracy that plagues every long-lived project.

The symptoms are familiar:
- New team members onboard with outdated information
- AI coding assistants hallucinate based on stale context
- Architecture decisions get lost to tribal knowledge
- "The code is the documentation" becomes the reluctant mantra

**agent-guard** solves Context Rot with a four-layer defense system that keeps your documentation perpetually synchronized with your code.

---

## How It Works: Four Layers of Defense

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YOUR CODEBASE                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  LAYER 1: Standing Instructions                               │  │
│  │  ─────────────────────────────────────────────────────────── │  │
│  │  AI agents receive real-time context about your docs.         │  │
│  │  When they modify code, they update documentation inline.     │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  LAYER 2: Generated Inventories                               │  │
│  │  ─────────────────────────────────────────────────────────── │  │
│  │  Deterministic scripts extract truth from code:               │  │
│  │  • API routes → docs/_generated/api-routes.md                 │  │
│  │  • Prisma models → docs/_generated/prisma-models.md           │  │
│  │  • Env vars → docs/_generated/env-vars.md                     │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  LAYER 3: Pre-commit Hook                                     │  │
│  │  ─────────────────────────────────────────────────────────── │  │
│  │  Catches drift before it reaches the repo:                    │  │
│  │  • Detects doc-relevant code changes                          │  │
│  │  • Generates remediation prompts                              │  │
│  │  • Blocks commits until docs are synchronized                 │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  LAYER 4: CI/CD Audits                                        │  │
│  │  ─────────────────────────────────────────────────────────── │  │
│  │  Final safety net in your pipeline:                           │  │
│  │  • GitHub Actions catch drift on every push                   │  │
│  │  • Weekly scheduled health checks                             │  │
│  │  • PR comments with specific remediation steps                │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

```bash
# Install dependencies
npm install

# Initialize agent-guard in your project
npx agent-guard init

# Generate initial documentation inventories
npm run gen:all

# Set up git hooks
npm run prepare
```

---

## Configuration

agent-guard is configured via `agent-docs.config.json`:

```json
{
  "inventories": {
    "apiRoutes": "src/app/api",
    "prismaSchema": "prisma/schema.prisma",
    "envExample": ".env.example"
  },
  "output": "docs/_generated",
  "hooks": {
    "preCommit": true,
    "ciAudit": true
  }
}
```

---

## Documentation Structure

```
docs/
├── ARCHITECTURE.md          # Human-maintained architecture overview
└── _generated/              # Auto-generated inventories (do not edit)
    ├── api-routes.md        # Extracted from src/app/api/**
    ├── prisma-models.md     # Extracted from prisma/schema.prisma
    └── env-vars.md          # Extracted from .env.example
```

---

## How the Layers Work Together

| Layer | Trigger | Action |
|-------|---------|--------|
| **Standing Instructions** | AI agent session | Updates docs alongside code changes |
| **Generated Inventories** | `npm run gen:all` | Regenerates markdown from source files |
| **Pre-commit Hook** | `git commit` | Blocks if generated docs are stale |
| **CI/CD Audits** | Push / PR / Schedule | Fails pipeline if drift detected |

---

## License

MIT
