# AGENTS.md — How to use agent-doodle

This is the **house style** for posting to the shared status board. It survives compaction because conductors re-read it (or it's in the system prompt).

## Core Rules

1. **On any "what's the status?" or progress question, first run the board and answer from it.**
   ```
   # Do this:
   doodle board
   # (or doodle get "the relevant name")
   # Then base your reply on the returned items. Do NOT re-derive from chat history alone.
   ```

2. **Use `doodle set` to communicate state.** Never just say it in prose if it belongs on the board.

3. **Use stable names.** The name is the key after normalization (trim + lower). 
   - Good: `"Auth middleware"`, `"rate limit decision"`
   - Updating the same thing later with slightly different casing still hits the same record thanks to normalization.

4. **Put the human-readable ask in `--detail`.** 
   - `summary` = one line "what's happening".
   - `detail` = the actual question or context the user needs to see: "Decision: token bucket vs fixed window. Existing patterns?"

5. **Prefer updating an existing item by name over creating new ones.** The board is a living dashboard, not a log.

6. **Set the right status (see semantics above):**
   - `active` — working on it, no immediate human action needed.
   - `waiting_on_user` — actionable by the human (drives badge and "Waiting on You").
   - `blocked` — stuck on something *not* the human.
   - `done` — finished (excluded from normal `doodle board` reads).

7. **Source attribution happens automatically** from `DOODLE_SOURCE` or `AGENT_NAME` env. Set it in your shell/session so humans know who wrote it.

## Single-writer model (conductor curates)

The board is **single-writer** in practice: the conductor is the curator who owns the overall state. Individual sessions/agents **report** status, questions, and blockers to the conductor (via `doodle set`), rather than directly editing or assuming ownership of the board.

- Sessions post facts and asks.
- Conductor reads the board, acts on `waiting_on_user` items, clears/sets statuses as appropriate, and keeps the picture coherent.
- Do not treat the board as a free-for-all chat log or per-agent scratchpad.

## Status semantics (human actionability)

- `waiting_on_user`: actionable by the **human** (conductor). This is what the badge and "Waiting on You" section highlight.
- `blocked`: stuck on something that is **not** the human (external dependency, other agent, infra, etc.).
- `active`: in progress, no immediate human action required.
- `done`: finished (hidden from default reads).

When posting, choose the status that accurately signals who needs to do what next.

## Typical Flow (Conductor Example)

```bash
# At the start of a task or when something changes
doodle set "Auth middleware" --type session --status active --summary "Implementing rate limiting" --detail "Chose token bucket. Any org patterns?"

# When you need the human
doodle set "Auth middleware" --status waiting_on_user --summary "Rate limiting design" --detail "Token bucket vs fixed window + existing patterns?"

# Later, after user answers or you make progress
doodle set "Auth middleware" --status active --summary "Proceeding with token bucket (per user)"

# When finished
doodle set "Auth middleware" --status done --summary "Rate limiting complete"
```

## Reading (Critical)

```bash
doodle board                 # default: current actionable items as JSON
doodle board --pretty        # human readable (you can show user)
doodle board --status waiting_on_user
doodle get "auth middleware"
```

Always prefer reading the board over guessing or re-summarizing from previous chat messages.

## Tip Re-seeding

Every `doodle board` prints this footer (on stderr):

```
TIP: use stable names, put the human-readable ask in --detail, prefer updating existing items by name. Read with `doodle board` on status questions.
```

This keeps the house style alive even after context compaction.

## Environment

- `DOODLE_BOARD_PATH` — use a project-specific board if desired.
- `DOODLE_SOURCE` — your identity (e.g. "conductor", "search-agent", "reviewer-3").

That's it. Small surface, high signal.
