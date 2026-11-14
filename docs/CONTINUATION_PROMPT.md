# Continuation prompt — paste this to the next agent

You are continuing a Godot 4.7 game called **Trains** (a Mini Metro-style Polish
rail game: spawn in a random city, reach Kraków by a deadline, rewind time).
Batch 1 (simulation core) and batch 2 (node-based rendering refactor) are done.
Your job is **batch 3: station view**. Work in SMALL slices: one focused change
→ quick verify → PR → wait for human approval. Do not boil the ocean.

## Read first, in this order
1. `docs/MASTER_PLAN.md` — engineering plan, public sim API (§2), rules (§5),
   run/verify commands (§7). Source of truth for HOW to work.
2. `DESIGN.md` — game spec, especially "Station view (top-down WASD)",
   "Controls", "Time", "Riding a train".
3. `AGENTS.md` — repo rules (config-only tunables, no AI assets, no slop, blind
   reviews, keep it simple, ask if unclear).

## Current architecture (batch 2 result — build on it, don't redo it)
- `scenes/main.tscn` → `scripts/main.gd`: input + run lifecycle only.
- `scenes/map/map.tscn` → `scripts/map/map_view.gd`: Line2D tracks
  (`track.tscn`), instanced `station.tscn`/`train.tscn`, Camera2D follow/zoom.
  All visuals are retained-mode nodes; the ONLY `_draw()` left is the isolated
  rewind overlay (`scripts/ui/rewind_overlay.gd`).
- `scenes/ui/hud.tscn` → `scripts/hud.gd`: Control HUD + instanced departure
  board (`departure_board.tscn`, pooled `board_row.tscn`) + shared
  `center_panel.tscn` (pause/end).
- All visual tunables: `config/view.json`. Sim core (`run.gd`, `world.gd`,
  `timetable.gd`, …) is tested and correct — views READ it, never rewrite it.
- Placeholders are config-driven Polygon2D/Line2D nodes inside the scenes; the
  artist swaps them without code changes.

## Batch 3 scope (slice it into small PRs)
Station view per DESIGN: top-down WASD walking on a path graph (paths +
platforms only), entrance spawn, platform signs (next train), departure board
at entrance (E), board by touching a dwelling train (no confirmation), trains
visible arriving/waiting/leaving at platforms, Tab switches station↔map (clock
rate already handled by `Run.advance`). Camera2D follows the player.

**Open decision to resolve FIRST (ask the human, come with a concrete plan):**
OSM data source/format for the walkable path graph per station. CUT ORDER #1:
if OSM is too heavy for the jam, propose hand-authored simple path graphs per
station in `config/` (still data-driven, still nodes) and get approval.

Suggested slicing (each its own PR):
1. Path-graph data format + one station's layout + player scene (placeholder
   sprite, asset slot) + WASD movement along paths + camera follow.
2. Platforms: signs (next train from `World.platform_next`), dwelling trains
   visible at platforms, touch-to-board, disembark puts player on the arrival
   platform. Replace the B/N stand-ins in `main.gd` with real walking.
3. Entrance departure board trigger (E near the board), Tab view switching
   wired to the station scene, rewind restores entrance position (history
   already supports it).

## Do NOT
- Do NOT rewrite the sim core or the batch-2 node architecture.
- Do NOT paint game objects in `_draw()` — nodes/scenes only (master plan §0).
- Do NOT hardcode tunables — `config/*.json` only.
- Do NOT generate art/audio. Labeled placeholder nodes; artist supplies assets
  (master plan §6). Missing asset → say so.
- Do NOT break/narrow the test suite.

## How to verify (keep it quick — one pass, not a marathon)
- `godot --headless --path . --import` then
  `godot --headless --path . -s tests/run_all.gd` → exit 0 (9,732+ checks).
- One play screenshot of the changed surface (Xvfb command in master plan §7;
  throwaway SceneTree script that injects input, saves
  `get_viewport().get_texture().get_image()`, quits — delete it after).
  NOTE: if the human's Godot editor is open on the project, headless editor
  captures race with its session cache — prefer play-mode screenshots.
- Blind reviewer subagents (code quality + bug hunt) given ONLY the code and
  the relevant DESIGN.md sections. Fix findings before the PR.

## Deliverable
Per slice: branch `batch-3-<slug>` off the latest approved branch, commit,
`gh pr create` with what changed / verification (check counts + screenshot) /
decisions / what the next slice should do. Then STOP and wait for human
approval. Update this prompt + `docs/MASTER_PLAN.md` status when a slice lands.
