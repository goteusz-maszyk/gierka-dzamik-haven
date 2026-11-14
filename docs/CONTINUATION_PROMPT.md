# Continuation prompt — paste this to the next agent

You are continuing a Godot 4.7 game called **Trains** (a Mini Metro-style Polish
rail game: spawn in a random city, reach Kraków by a deadline, rewind time).
Batch 1 (simulation core + a preview) is merged. Your job is **batch 2**.

## Read first, in this order
1. `docs/MASTER_PLAN.md` — the engineering plan, the public sim API, the batch
   roadmap, and the rules. This is your source of truth for HOW to work.
2. `DESIGN.md` — the game spec (what to build).
3. `AGENTS.md` — repo rules (config-only tunables, no AI assets, no slop, blind
   reviews, keep it simple, ask if unclear).

## The most important rule (do not skip)
The batch-1 preview renders everything with immediate-mode `_draw()` calls in
`scripts/main.gd` and `scripts/hud_surface.gd`. **That is the wrong architecture
and your first task is to refactor it to retained-mode Godot nodes and `.tscn`
scenes.** Tracks → `Line2D`; stations/trains → instanced scenes with `Sprite2D`
placeholders + labels; HUD/board/end/pause → `Control` nodes (`Label`,
`ProgressBar`, `Panel`, containers). Code creates/updates nodes and sets their
properties; it does NOT paint game objects in `_draw()`. Every visual element
must be visible/editable in the Godot editor and swappable by an artist without
rewriting draw code. `_draw()` is allowed only for an isolated dynamic effect
(e.g. the rewind VHS overlay), never for game objects. Full details and the
acceptance criteria are in `docs/MASTER_PLAN.md` §0 and §4 (Batch 2).

## Do NOT
- Do NOT rewrite the simulation core (`run.gd`, `world.gd`, `timetable.gd`,
  `train_physics.gd`, `events.gd`, `route_planner.gd`, `player_history.gd`,
  `config_data.gd`). It is correct and covered by 9,732 passing checks. Views
  READ from it via the `World`/`Run` API documented in the master plan.
- Do NOT hardcode tunables — everything goes in `config/*.json`.
- Do NOT generate art or audio. Use labeled placeholder nodes; the artist
  supplies real assets (asset list in the master plan §6).
- Do NOT break the test suite or delete/narrow tests to make them pass.

## Batch 2 scope
1. **Refactor the preview to nodes/scenes** (mandatory first; see above). Keep
   behavior identical: launch into a run, live map with moving trains, HUD
   (clock/deadline/time-left/rewind bar/current train), departure board (E),
   pause (Esc), rewind (hold Space), board (B) / disembark (N) as stand-ins for
   station walking, restart (R), wheel zoom, camera follow.
2. **Map view polish**: hover station names, Kraków highlight, player-train
   highlight, event icons on affected trains (placeholder icon nodes with asset
   slots), zoom min/max from config.

## How to verify (required before calling it done)
- `godot --headless --path . --import` then
  `godot --headless --path . -s tests/run_all.gd` → exit 0, all checks pass.
- Open `scenes/main.tscn` in the editor and confirm the node tree is real
  (stations/trains/HUD as nodes, not one draw script). Capture an editor
  screenshot AND a play screenshot as proof (Xvfb command in master plan §7).
- Run blind reviewer subagents (code quality + bug hunt) given ONLY the code and
  the relevant DESIGN.md sections — not your reasoning or this conversation.
  Fix their findings, add regression tests, re-run the suite.

## Deliverable
Finish batch 2, test it, then open a PR (`gh pr create`, branch `batch-2-...`)
with: what changed, verification (check counts + screenshots), any design
decisions, and what batch 3 should do. Then STOP and wait for human approval —
do not start batch 3. If anything is unclear or a decision is needed (e.g. OSM
data source for batch 3), ask before proceeding, but come with a concrete plan.
