# agent-radar

A tiny external "state radiator" for conductor + multi-agent workflows.

Agents write structured status via the `radar` CLI. You glance at a living dashboard in your MacBook notch (or `radar board --pretty` on any machine).

It is **not** an AI. It is a shared, lock-safe scratchpad in `~/.agent-radar/board.json` (or `$RADAR_BOARD_PATH`).

**Formerly known as agent-doodle (CLI: doodle).**

<!-- Screenshot of the notch UI (compact badge + expanded panel) goes here. -->

## Why

- Stop asking "what's cooking?"
- Separate "what's happening" from "what I need from you"
- Survives agent compaction via disciplined reads + tiny footer hints
- Works for the conductor *and* any number of parallel agents (locking built-in)

## Install

### CLI (`radar`)

```bash
git clone https://github.com/Abeansits/agent-radar.git
cd agent-radar

# Build release CLI and install to ~/.local/bin
swift build -c release
mkdir -p ~/.local/bin
install -m 755 .build/release/radar ~/.local/bin/radar

# Make sure ~/.local/bin is on your PATH (add to ~/.zprofile or ~/.zshrc if needed)
export PATH="$HOME/.local/bin:$PATH"
# (restart your shell or `source` the profile)

radar --help
```

### Notch dashboard (macOS)

```bash
# From the repo dir
swift build -c release
.build/release/RadarNotchApp
```

The app is an accessory (no Dock icon). It lives in the notch and expands on hover. Use the gear (top-right, hover-revealed) → Quit or press ⌘Q.

For auto-start at login, wire up a LaunchAgent plist pointing at the release binary (or the in-app option once implemented).

## Commands

```
radar set "<name>" [--type TYPE] [--status STATUS] [--summary "..."] [--detail "..."]
radar board [--status X] [--all] [--pretty]
radar get "<name>"
radar rm "<name>"
```

See `radar --help`.

## Data Model

Board items are small JSON objects:

```json
{
  "name": "auth middleware",           // stable normalized key (trim + lower)
  "display_name": "Auth Middleware",   // last human casing written
  "type": "session",                   // free-form (session, question, blocker, note...)
  "status": "waiting_on_user",         // active | waiting_on_user | blocked | done
  "summary": "Rate limiting in progress.",
  "detail": "Decision: token bucket vs fixed window?",  // the ask / context (optional)
  "source": "conductor",
  "updated_at": "2026-..."
}
```

- Badge = number of `waiting_on_user` items.
- Default `radar board` hides `done` items (use `--all` to see them).
- See `board.example.json` for a full example.

## Notch UI

- Compact: clipboard icon + red badge (only for `waiting_on_user` count)
- Hover to expand into **Waiting on You / Active / Blocked** sections
- Larger panel (640 px). Cards with a `detail` ask: tap the **entire row** to expand/collapse. The chevron is a passive indicator only (hidden when no detail).
- Cards without detail show no chevron and ignore row clicks.
- Hover the ✓ to mark done (isolated hit area — row tap never marks done).
- Stale items (>6h) are dimmed. Polls the board file ~every 5 s.

## House Style for Agents

Read `AGENTS.md`. The most important parts:

- Always `radar board` (or `get`) on status queries; answer from it.
- Use stable names + put the real ask in `--detail`.
- Prefer update-by-name.

## Portability

`RadarCore` + `radar` CLI have **zero** macOS-only imports. The JSON + CLI are the portable product. The notch is one Mac frontend.

## Development Notes

- Built with SwiftPM + DynamicNotchKit (lifted patterns from Arthur).
- Locking via `flock(LOCK_EX)` around mutations.
- See `docs/STATUS.md` for current implementation status + verification results (post-rename to agent-radar).

## MVP Scope (done)

- Core set/board/get/rm + locking + normalization
- Notch with badge, grouped sections, age dimming, hover
- AGENTS.md + read discipline
- Survives restart

Fast follows tracked in issues.

MIT — see LICENSE.
