# agent-radar

A tiny external "state radiator" for conductor + multi-agent workflows.

Agents write structured status via the `radar` CLI. You glance at a living dashboard in your MacBook notch (or `radar board --pretty` on any machine).

It is **not** an AI. It is a shared, lock-safe scratchpad in `~/.agent-radar/board.json` (or `$RADAR_BOARD_PATH`).

**Formerly known as agent-doodle (CLI: doodle).**

## Why

- Stop asking "what's cooking?"
- Separate "what's happening" from "what I need from you"
- Survives agent compaction via disciplined reads + tiny footer hints
- Works for the conductor *and* any number of parallel agents (locking built-in)

## Install / Run (dev)

```bash
# CLI (any machine)
swift run radar set "My task" --status active --summary "Doing the thing"
swift run radar board --pretty

# Notch UI (macOS)
swift run RadarNotchApp
```

## Commands

```
radar set "<name>" [--type TYPE] [--status STATUS] [--summary "..."] [--detail "..."]
radar board [--status X] [--all] [--pretty]
radar get "<name>"
radar rm "<name>"
```

See `radar --help`.

## Data Model (small)

See `plan-opencode.md` and `board.example.json`.

Key points:
- `name` is normalized (stable key)
- `display_name` preserves last human casing
- Badge = count of `status == "waiting_on_user"`
- `done` items hidden from default board reads

## Notch UI

- Compact: clipboard icon + red badge for waiting items
- Hover to expand: sections **Waiting on You / Active / Blocked**
- Cards show name, summary, detail (if present), source, relative time
- Stale items (>6h) are dimmed
- Polls the file ~every 5s for the badge

## House Style for Agents

Read `AGENTS.md`. The most important parts:

- Always `doodle board` (or `get`) on status queries; answer from it.
- Use stable names + put the real ask in `--detail`.
- Prefer update-by-name.

## Portability

`RadarCore` + `radar` CLI have **zero** macOS-only imports. The JSON + CLI are the portable product. The notch is one Mac frontend.

## Development Notes

- Built with SwiftPM + DynamicNotchKit (lifted patterns from Arthur).
- Locking via `flock(LOCK_EX)` around mutations.
- See `plan-opencode.md` for the full rationale and verification checklist.
- See `docs/STATUS.md` for current implementation status + verification results (post-rename to agent-radar).

## MVP Scope (done)

- Core set/board/get/rm + locking + normalization
- Notch with badge, grouped sections, age dimming, hover
- AGENTS.md + read discipline
- Survives restart

Fast follows tracked in the plan.

MIT / whatever — use it.
