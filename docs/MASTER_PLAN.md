# Trains — master plan & agent continuation guide

Read this whole file before touching code. It is the source of truth for how
the project is built and how to continue it. `DESIGN.md` is the game spec;
this file is the engineering plan + rules for AI agents working on it.

---

## 0. Prime directive: scenes, not `_draw()`

**Batch 2 completed this refactor** (the old batch-1 preview painted everything
with immediate-mode `_draw()` calls; that throwaway is gone — `hud_surface.gd`
deleted, map/HUD are now nodes/scenes). The rule below still governs all new
rendering work: nothing may regress to `_draw()` for game objects.

**Rule for all rendering work from here on:**
- Build **retained-mode node trees and `.tscn` scenes**. Tracks are `Line2D`,
  stations and trains are instanced scenes (`Sprite2D`/`Node2D` + collision +
  labels), HUD is `Control` nodes (`Label`, `ProgressBar`, `Panel`, `VBoxContainer`).
- Code's job is to **create/update nodes and set their properties** (position,
  text, color, texture), NOT to paint pixels in `_draw()`.
- `_draw()` is acceptable ONLY for genuinely dynamic vector effects that have
  no node equivalent (e.g. the rewind VHS scanline overlay) — and even that
  should be a dedicated node/shader, isolated, not mixed into game rendering.
- Every visual element must be **editor-visible** and **asset-swappable**: an
  artist must be able to replace a placeholder by editing a scene or dropping
  a texture into a designated slot, without rewriting draw code.
- If you find yourself writing `draw_*` to represent a game object, STOP and
  make a node/scene instead.

The sim core (`scripts/run.gd`, `world.gd`, `timetable.gd`, etc.) is correct and
tested — do NOT rewrite it. Rendering reads from it; it never renders.

---

## 1. What exists (batch 1, merged status: PR #1)

### Simulation core — DONE, tested, do not rewrite
Pure headless sim implementing DESIGN's invariant
`state = f(timetable, events, time)`. No nodes, no UI. All `RefCounted` with
`class_name`. Time unit = in-game minutes since midnight (float). Distance = km.

| File | Responsibility |
|------|----------------|
| `scripts/config_data.gd` | `ConfigData.load_file(name)` → Dictionary from `config/<name>.json`. |
| `scripts/train_physics.gd` | `section_time(...)`, `section_progress(...)` — closed-form accel/cruise/brake. |
| `scripts/timetable.gd` | Seeded schedule generation + events applied as shifts + pure queries. |
| `scripts/world.gd` | Thin facade over one Timetable. **The only thing views/Run touch.** |
| `scripts/events.gd` | `Events.generate(events_config, network, rng)` — seeded, one event/train. |
| `scripts/route_planner.gd` | `fastest_arrival(world, network, from, t)` — exact, ignores events. |
| `scripts/player_history.gd` | Monotonic player log for rewind (`record_*`, `state_at`, `truncate_after`). |
| `scripts/run.gd` | One run: clock, deadline fixed point, rewind meter, board/disembark, finish. |

### Preview — REFACTORED to nodes/scenes (batch 2, PR pending)
`scenes/main.tscn` now instances `scenes/map/map.tscn` (Line2D tracks,
instanced `station.tscn`/`train.tscn`, Camera2D) and `scenes/ui/hud.tscn`
(Control HUD, departure board, pause/end panels). `scripts/hud_surface.gd`
is deleted. The only remaining `_draw()` is the isolated rewind overlay
(`scripts/ui/rewind_overlay.gd`), to be replaced by a VHS shader in batch 4.

### Config — all tunables live here (AGENTS.md rule)
`config/network.json` (stations, lines, km, first departures), `trains.json`
(categories, dwell, number prefixes), `time.json` (clock rates, buffer, rewind),
`events.json` (counts, types, ranges), `view.json` (colors, sizes, zoom — used
by the preview; keep using it for the node-based views too).

### Tests — 9,732 checks, 0 failures
`tests/run_all.gd` runs everything; `tests/run_one.gd -- res://tests/test_x.gd`
runs one file. Harness in `tests/harness.gd` (`ok/eq/near`). Hand-computed
expectations, not smoke tests. **Any change must keep the suite green and add
regression tests for fixed bugs.**

---

## 2. Public API contract (views read these; do not change signatures lightly)

### Run (`scripts/run.gd`)
```
Run.create(seed_value: int) -> Run        # generates everything, seeds history
# fields: seed_value, start_station, start_time, deadline, clock, world,
#         events, history, player_station ("" when riding),
#         player_train ("" when in station), rewind_meter, finished, arrival_time
advance(real_seconds: float, view: String)  # view "map"|"station"; finishes at Kraków
rewind(real_seconds: float) -> float        # returns minutes actually moved; no-op when finished
board(train_id: String)                     # assert: dwelling at player_station
disembark()                                 # assert: riding & dwelling; finishes at Kraków
time_remaining() -> float                   # max(0, deadline - clock)
minutes_late() -> float                     # arrival_time - deadline (when finished)
```

### World (`scripts/world.gd`) — the view's data source
```
train_state(train_id, t) -> Dictionary
# {phase: "before"|"moving"|"dwelling"|"finished"|"cancelled",
#  station_id, platform, from_station, to_station, progress (0..1), km, delay}
base_train_state(train_id, t) -> Dictionary   # ignores events
departures(station_id, t, count) -> Array      # board rows, sorted, incl. cancelled
base_departures(station_id, t, count) -> Array
platform_next(station_id, platform, t) -> Dictionary
effective_arrival(train_id, station_id) -> float          # INF if never/cancelled
effective_arrival_after(train_id, station_id, after_index) -> float
stop_index(train_id, station_id) -> int
base_timetables() -> Dictionary   # train_id -> {info, stops[]} (snapshots)
train_ids() -> Array[String]
train_info(train_id) -> Dictionary
# {train_number, line_id, line_name, color, category, direction "F"|"R",
#  stops: [{station_id, platform}], destination (name)}
```
Board row shape: `{train_id, train_number, line_id, destination, platform,
departure, delay, cancelled}`.

### Phase boundaries (critical for animation/boarding)
Dwelling on `[arrival, departure)`, moving on `[departure, next arrival)`,
finished only at `t >= last departure`. Every stop dwells 2 min incl. origin
and terminus. At the exact arrival instant the phase is "dwelling".

---

## 3. Design decisions already made (don't re-litigate)
- Network: 11 real cities, 6 lines, Kraków hub. Start cities: Warszawa, Łódź,
  Poznań, Wrocław, Katowice. Distances = real rail km in `network.json`.
- First departures tuned per line so a perfect run arrives ~08:30 (deadline
  09:00 − 30-min buffer) → ~5-min runs. If you retune, re-verify the run target.
- Deadline = fastest ride duration + buffer; start = 09:00 − deadline. Duration
  is ride time (arrival − departure), NOT time-since-start (fixed point converges).
- Dwell at every stop incl. origin/terminus (manual disembark at Kraków works).
- Manual disembark only — no marks, no auto-disembark (DESIGN "Riding a train").
- Finish requires a Kraków arrival AFTER the boarding stop (stop-order based,
  so reverse L6-R Rzeszów→Kraków still finishes correctly). See `_board_stop_index`.
- Rewind after finish is a no-op.

---

## 4. Batch roadmap

### Batch 2 — node-based rendering refactor + map view (DONE, PR pending)
Delivered as one small slice (refactor only; the task-2 polish items already
existed in the batch-1 draw code and carried over as nodes):
- `scenes/map/map.tscn` + `scripts/map/map_view.gd`: Line2D tracks per line
  (`track.tscn`), instanced `station.tscn`/`train.tscn`, Camera2D follow + zoom.
- `scenes/ui/hud.tscn` + `scripts/hud.gd`: Control HUD (clock/deadline/time-left,
  rewind ProgressBar, current train, message), instanced `departure_board.tscn`
  (pooled `board_row.tscn` rows), shared `center_panel.tscn` for pause + end.
- `scripts/ui/rewind_overlay.gd`: isolated `_draw()` tint/scanlines (batch 4
  replaces with a VHS shader). `hud_surface.gd` deleted.
- All visual tunables in `config/view.json`; placeholders are config-driven
  Polygon2D/Line2D nodes the artist swaps inside the scenes.
- Verified: suite 9,732 checks / 0 failures; play/board/pause/rewind screenshots
  in `docs/screenshots/batch-2/`; clean runtime (no script errors/warnings from
  the new code).

### Batch 3 — station view (top-down WASD) (NEXT)
- OSM-based walkable path graph per station (DESIGN: paths + platforms only).
  Data source/format is an open decision — propose, document, get approval.
  CUT ORDER #1: if OSM is too heavy, use a hand-authored simple path graph per
  station (still data-driven, still nodes), and say so.
- Player scene (Sprite2D placeholder, asset slot), WASD movement along paths,
  Camera2D follow. Entrance spawn point. Platforms with signs (next train).
  Departure board at entrance (E). Board by touching a dwelling train (no
  confirmation). Trains visible at platforms arriving/waiting/leaving.
- Tab switches station↔map; clock rate changes per view (already in Run.advance).

### Batch 4 — rewind UX + events surfacing + end/pause polish
- VHS/tape effect while rewinding (isolated shader/overlay node, NOT mixed draw).
- Event popups (only your train, only map view), icons on all affected trains.
- End screen: arrival, deadline, minutes late/early, seed (display-only), restart.
- Pause menu (Esc) freezes clock/trains/player (Run already stops via not advancing).

### Batch 5 — artist assets + audio + final tuning
- Replace placeholders with artist assets (see §6 asset list). NEVER generate
  art/audio yourself (AGENTS.md). Wire asset slots; if an asset is missing, say
  so and keep a labeled placeholder.
- Fonts must render Polish diacritics (already verified with Noto). 1920×1080
  pixel-art-compatible scaling (DESIGN) — set stretch/viewport accordingly.
- Tune run length, zoom, event feel via config only.

### Cut order if time runs short (DESIGN, first cut first)
1. OSM station layouts → hand-authored path graphs
2. Reroute (already Future)
3. Slow down event
4. Multiple start cities
5. Events entirely
**Rewind and the station↔map loop are NEVER cut.**

---

## 5. Rules for every agent (from AGENTS.md + this plan)
- **Scenes/nodes, not `_draw()`** (§0). This is the #1 rule.
- **Config, not hardcoded values.** Every tunable in `config/*.json`. New
  tunable = new config entry, never a magic number in code.
- **No AI-generated assets.** Code only. Art/audio come from the artist. Missing
  asset → say so, keep a labeled placeholder, never fabricate.
- **No slop.** No filler, no half-done implementations presented as working, no
  speculative features, no decorative comments. Every line earns its place.
- **Keep it simple.** Straightforward solution over abstraction. A human must
  read it without decoding cleverness.
- **Don't rewrite the sim core.** It is tested and correct. Views read it.
- **Tests stay green.** Run `godot --headless --path . -s tests/run_all.gd`.
  Add regression tests for any bug you fix. Hand-computed expectations, not
  tautologies. Don't narrow/delete tests to make them pass.
- **Blind reviews before done.** After writing/fixing code, run reviewer
  subagents given ONLY the code + relevant DESIGN.md section — never the
  conversation or your reasoning. Fresh eyes, not rubber stamps.
- **Verify visually.** For UI, open it in a browser/editor or capture a
  screenshot; "should work" is not done. Headless boot + rendered screenshot.
- **Ask if unclear.** Don't assume context. But have a concrete plan.
- **Work in batches.** Finish a batch, test it, open a PR, wait for approval
  before the next batch.

---

## 6. Asset list for the artist (keep small — 2-day jam, 1 artist)
Placeholders are code-colored nodes now; each needs a real asset slot:
- Player character (top-down sprite, station view).
- Train sprite (top-down, tinted per line color) — map + station view.
- Station marker / platform tile (map + station view).
- Track style (Mini Metro clean line) — may stay vector Line2D.
- Event icons: drunk driver, slow down, cancel (small, readable on map).
- Departure board / platform sign frame (UI).
- Rewind VHS overlay texture/shader reference.
- UI: HUD panel, buttons (restart), end-screen panel.
- Font with Polish diacritics (ą ć ę ł ń ó ś ź ż) — Noto works as fallback.
- Music + SFX (board, disembark, rewind, event, arrival).
Until an asset arrives, use a labeled placeholder node and note it in the PR.

---

## 7. How to run / verify
```
godot --headless --path . --import                 # import assets/scripts
godot --headless --path . -s tests/run_all.gd      # full suite (exit 0 = pass)
godot --headless --path . -s tests/run_one.gd -- res://tests/test_x.gd
godot --path .                                     # play the preview
```
Rendered screenshot proof (headless GPU via Xvfb):
```
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3
```
(Use a SceneTree script that instances main.tscn, waits ~3 s, saves
`get_viewport().get_texture().get_image()` to PNG, quits. Delete the throwaway
script after.)

---

## 8. Git / PR workflow
- Branch per batch: `batch-N-<slug>` off `main`.
- Commit messages: what + why, reference DESIGN sections.
- Open PR with `gh pr create`, body = what changed, how verified (check counts,
  screenshots), design decisions, what's next. Wait for human approval.
- `.uid` sidecars are committed (Godot 4.4+ stable IDs); `.godot/` is ignored.
