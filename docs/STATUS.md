# agent-radar — Status & Implementation (formerly agent-radar)

**Date:** 2026-07-02  
**Based on:** `plan-opencode.md` (parallel plan by opencode)

---

## Overview

`agent-radar` is a lightweight external "state radiator" for conductor + multi-agent workflows.

- Agents post structured status via a tiny CLI (`radar set`).
- Humans get a living dashboard in the MacBook notch (badge + hover) or via `radar board --pretty`.
- It is **not** an AI — it's a shared, lock-safe scratchpad (`~/.agent-radar/board.json` or `$RADAR_BOARD_PATH (fallback DOODLE_BOARD_PATH)`).

The goal is to stop asking "what's cooking?" and let agents communicate clearly (especially "what I need from you").

---

## Key Decisions from the Plan

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Locking in MVP | `flock(LOCK_EX)` around read-modify-write. Multiple agents will write on day 1. |
| 2 | Single `set` command | Collapsed from 4 nouns. `type` + `status` handle the rest. |
| 3 | Badge = `waiting_on_user` only | One clear rule. |
| 4 | Source from env | `RADAR_SOURCE (fallback DOODLE_SOURCE)` (fallback `AGENT_NAME`). Survives compaction. |
| 5 | `RADAR_BOARD_PATH (fallback DOODLE_BOARD_PATH)` day one | Testable + overridable. |
| 6 | Poll, don't watch | 5s `Timer` (simple, matches Arthur pattern). |
| 7 | Build CLI + UI together | After locking the data model. |
| 8 | Section order | **Waiting on You → Active → Blocked** |

Name normalization (trim + lower for key, keep `display_name`) and read-side discipline were also locked in.

---

## Data Model

```json
{
  "version": 1,
  "items": [
    {
      "name": "auth middleware",
      "display_name": "Auth Middleware",
      "type": "session",
      "status": "waiting_on_user",
      "summary": "Rate limiting in progress.",
      "detail": "Decision: token bucket vs fixed window. Any existing patterns to follow?",
      "source": "conductor",
      "updated_at": "2026-06-30T14:22:01Z"
    }
  ]
}
```

**Fields:**
- `name`: normalized key (stable)
- `display_name`: last casing written
- `type`: free string (session/question/blocker/note/...)
- `status`: `active` | `waiting_on_user` | `blocked` | `done`
- `summary`: one line
- `detail`: the human-readable ask (optional but powerful)
- `source`, `updated_at`

`done` items are excluded from default `radar board` reads.

---

## Architecture

```
agent-radar/
├── README.md
├── AGENTS.md
├── Package.swift
├── Sources/
│   ├── DoodleCore/       # Pure Foundation (models + flock + store)
│   ├── DoodleCLI/        # `radar` executable
│   └── DoodleNotchApp/   # Mac notch UI
├── board.example.json
└── docs/
```

**Portability rule:** `DoodleCore` and `DoodleCLI` import **nothing** Mac-specific.

---

## Implementation (Completed)

All MVP scope from the plan is implemented (as of 2026-07-02).

### What Was Built

- **DoodleCore**
  - `DoodleItem` + `Board` models + `Identifiable`
  - Name normalization (`trim` + `lowercased`)
  - `BoardStore` with real `flock(LOCK_EX)` + atomic writes
  - Path resolution (`RADAR_BOARD_PATH (fallback DOODLE_BOARD_PATH)` or `~/.agent-radar/board.json`)
  - Date helpers, relative time, `isStale()`, `prettyPrint()`
  - High-level `set` (partial updates), `get`, `remove`

- **DoodleCLI**
  - Full commands: `set`, `board [--status] [--all] [--pretty]`, `get`, `rm`
  - JSON by default (agent-friendly)
  - Human `--pretty` output with sections
  - TIP footer on stderr on every `board` read (re-seeds house style)
  - Env var support documented

- **DoodleNotchApp**
  - `AppDelegate` with DynamicNotchKit setup (hover behavior, debounce)
  - `BoardManager` (`@Observable @MainActor`)
  - 5-second poll for badge count
  - Compact icon + red badge (only for `waiting_on_user`)
  - Expanded view: Waiting on You / Active / Blocked sections
  - Item cards with summary, detail (truncated), source, relative time
  - Age dimming (opacity + styling for >6h old items)
  - Full reload on expand + manual refresh

- **Documentation**
  - `README.md`
  - `AGENTS.md` (strong emphasis on **read discipline** + stable names + `--detail`)
  - `board.example.json`

### Build & Structure

- SwiftPM with 3 targets:
  - `DoodleCore` (library)
  - `radar` (CLI executable)
  - `DoodleNotchApp` (UI executable)
- Depends on local `../DynamicNotchKit` (same branch as Arthur)
- Clean build: `swift build`

---

## Verification (Plan Checklist) — post-fix (2026-07-02)

All items completed and passing (fixes applied on top of baseline 66d2326):

1. Build + manual `set` / `board` — ✅
2. **Concurrency test**: scripts/stress.sh (60 parallel `radar set` distinct names) — ✅ (60/60 every run; sidecar lock + empirical repro)
3. Name normalization test — ✅ (now also in `swift test`)
4. `done` exclusion + `--all` — ✅ (now also in `swift test`)
5. Notch build + badge logic — ✅
6. Age-dimming (backdated 7h item) — ✅ (shows "7h ago", dims in UI)
7. Full loop + restart survival — ✅ (file-backed state)
8. Human-readable `--pretty` — ✅
9. Portability boundary — ✅ (Core/CLI have zero AppKit/SwiftUI)

## Fixes Applied (post-baseline commits)

- **fix: sidecar lock** — board.json.lock (stable inode) for flock; data uses .atomic. Prevents the inode race that lost updates at scale (previously ~26/60).
- **fix: corrupt backup** — on decode fail inside withLock: rename to `board.json.corrupt-<ISO-ts>`, stderr warning, then fresh. No more silent wipe.
- **fix: status validation** — CLI rejects unknown --status (e.g. "waiting") with exit 2 + list of valid: active, waiting_on_user, blocked, done.
- **test: real tests + stress** — Added `Tests/DoodleCoreTests` (normalization, done-exclusion, corrupt backup) + `scripts/stress.sh`. `swift test` and 3x stress now pass.

Stress test (`./scripts/stress.sh 60`) repeatedly proves the lock fix at scale: exactly 60 items survive 60 concurrent writers.

See git log for the 4 separate fix commits.

---

## How to Use

### CLI

```bash
# Post status (from any agent)
RADAR_SOURCE (fallback DOODLE_SOURCE)=conductor swift run radar set "Auth middleware" \
  --type session \
  --status waiting_on_user \
  --summary "Rate limiting in progress." \
  --detail "Decision: token bucket vs fixed window?"

# Read (agents should do this on status questions)
swift run radar board                 # JSON (default)
swift run radar board --pretty        # Human readable
swift run radar board --status waiting_on_user
swift run radar get "auth middleware"
swift run radar rm "old task"
```

### Notch UI

```bash
swift run DoodleNotchApp
```

- Lives in the notch.
- Badge shows count of `waiting_on_user` items.
- Hover to expand full dashboard.
- Polls every ~5 seconds.
- Subtle gear (⌘+Q or menu) in top-right of expanded header for Quit (app-level NSEvent handler; no misleading Menu shortcut).

---

## House Style (AGENTS.md Highlights)

Key rules agents should follow:

- On any status/progress question: **first run `radar board` (or `get`) and answer from it**. Do not re-derive from chat history.
- Use stable names.
- Put the real human ask in `--detail`.
- Prefer updating by name over creating duplicates.
- Set proper status (`waiting_on_user` drives the badge).

The `radar board` command prints a footer tip on stderr to re-seed the style after compaction.

---

## Out of MVP (Future)

- Multiple named boards / project scoping
- Done archive / history
- In-notch editing (mark done, etc.)
- MCP server wrapper
- Mermaid diagrams, export

---

## Current State

- Fully functional MVP.
- Core is rock-solid (locking + normalization tested under concurrency).
- Ready for real conductor sessions.
- State survives restarts and lives in a single JSON file.

**Suggested next action:** Run a full loop with an actual multi-agent conductor session and observe the notch + board reads in practice.

---

## Files

- `plan-opencode.md` — original plan
- `README.md`
- `AGENTS.md`
- `Sources/DoodleCore/`, `DoodleCLI/`, `DoodleNotchApp/`

Generated from live implementation work (using sub-agents for verification).

---

*Document created 2026-07-02. Markdown is the source of truth for this project.*