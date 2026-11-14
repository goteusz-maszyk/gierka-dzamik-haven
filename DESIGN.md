# Game design (draft v3)

Working title: **Trains** (will be renamed).

## Goal
You spawn in a random meme city nobody likes and must reach Kraków (the
gamejam city) by a deadline. Arriving late is not game over; it only makes
your result worse.

- One level per run.
- Start city is random; destination is always Kraków.
- Route is free: any combination of lines/trains.
- All in-game text is English (station names keep their Polish spelling,
  e.g. Kraków, Łódź).
- Target run length: about **5 real minutes**. The game should be quick to
  play. Start cities and the deadline buffer must be picked so a normal run
  fits that (see "Time" for the numbers).

## Run flow
1. Game launches straight into a run (no main menu, no how-to-play screen
   for now).
2. Start city is picked, timetables and events are generated (seeded), deadline is calculated.
3. Player spawns at the entrance of the start city's station, in station view.
4. Player walks to a platform and boards a train.
5. On boarding, the game switches to map view, with the player's train
   highlighted and the camera following it.
6. While riding, the player watches for their stop.
7. At that stop the player is in station view again, standing on the
   arrival platform, and walks to the next platform. Repeat until Kraków.
8. The run ends the moment the player's train arrives in Kraków (no walking
   in Kraków station). End screen is shown.

## Deadline
- Deadline = fastest possible route from start to Kraków + a fixed buffer.
- Fastest route is calculated from the generated timetable, ignoring events.
- Start time is determined as 09:00 - deadline time

## Score
- Result is simply how many minutes late (or early) you arrived.
- Arrival time = the in-game time your train arrives in Kraków.
- Using rewind has no penalty and does not affect the result.

## End screen
- Shows: arrival time, deadline, minutes late/early, run seed.
- Seed is display-only (cannot be typed in).
- Restart button (new run, new start city, new timetables and events).
- No joke rating/text for now.

## Pause menu
- `Esc` opens the pause menu. Everything stops (clock, trains, player).

## HUD
- Same HUD in station view and map view, always visible.
- Clock: current in-game time, 24h `HH:MM`.
- Deadline and time remaining. After the deadline, time remaining does not
  go negative and does not change colour.
- Rewind meter: a bar only (no numbers).
- When riding: current train.

## Controls
| Action                         | Key          |
|--------------------------------|--------------|
| Walk (station view)            | WASD         |
| Rewind (hold, map view only)   | Space        |
| Switch station view / map view | Tab          |
| Read departure board           | E            |
| Pause                          | Esc          |
| Mark stop, zoom (map view)     | Mouse only   |

## Time
- One in-game clock for everything.
- Clock speed depends only on which view is on screen:
  - **Map view** (riding, or looking at the map while in a station):
    3 in-game hours = 5 real minutes, i.e. 0.6 in-game minutes per real
    second.
  - **Station view**: **4× slower**, i.e. 0.15 in-game minutes per real
    second.
- So switching to map view while waiting in a station is the way to make
  waiting go faster. There is no wait/skip button.
- Reference numbers (all tunable later):
  - 2-minute stop at a station = ~3.3 real s in map view, ~13 real s in
    station view.
  - 5 real minutes of riding = 3 in-game hours.

## Map view
- Real Polish rail network, drawn simplified in a clean Mini Metro style.
  Station view is drawn from osm data around station; Some specific textures
  are manually drawn like player or train models. the game mixes both styles.
- Each line has its own colour. Trains are drawn in their line's colour.
- Station names are hidden; a station's name appears when you hover it.
- Kraków is always highlighted.
- The player's train is highlighted.
- Camera follows the player (your train, or your station when you are in
  one). Zoom with the mouse; no free panning. Zooming out is the only way to
  see far-away parts of the map.
- All trains move at the same time and are visible on the map.
- Map view is for watching, planning and rewinding. You can never board a
  train from the map.

### Riding a train

- You must manually click the "Disembark" action while the train is stopped at a station to get off.
- You can only disembark while the train is standing at a station, not while it is moving.
- You must remember to disembark yourself when the train reaches your intended station.
- If you do not click "Disembark" before the train departs, you remain aboard and travel to the next stop.
- You can disembark at any station where the train actually stops, including Kraków.
- There are no automatic disembarkations, destination marks, or advance exit selections.
- If you miss your intended stop, you must continue riding until another station where you can manually disembark.
- The player judges transfers on their own (no hints, no route planner).

## Trains and timetables
- Lines run in both directions.
- Each train has its own maximum speed, acceleration and braking based on category.
- Trains accelerate when departing, cruise when possible, and brake before scheduled stops.
- Travel time depends on distance and train performance. On short distances, maximum speed may never be reached.
- Every train waits 2 in-game minutes at each scheduled stop (tune later).
- Line configuration determines route, stops, direction and frequency.
- Frequency is set per line (e.g. every 60 minutes in each direction).
- Timetables are generated per run (seeded) using lines, frequencies and train categories.
- Timetables repeat indefinitely; there is no last train.
- Each line uses a fixed platform per direction at each station.
- Trains ignore each other and can overlap on the same track
- Trains have numbers generated based on category and index (in generation)
- Missed the train: wait for the next one.

| Category | Max speed | Acceleration | Braking |
| --------- | -------- | --------- | ---------  |
| Local     | 80 km/h  | 0.7 m/s² | 0.45 m/s²  |
| Regional  | 120 km/h | 0.5 m/s² | 0.55 m/s²  |
| Express   | 160 km/h | 0.4 m/s² | 0.65 m/s²  |
| Intercity | 200 km/h | 0.3 m/s² | 0.75 m/s²  |

## Events
- Generated once per run (seeded). Rewinding replays the exact same events.
  Restarting generates new ones.
- Each event targets **one specific train**.
- A train gets at most one event (no stacking).
- Events are spread randomly over all trains and over time. There must be
  enough of them (15+) that the player definitely runs into them.
- Events only affect trains, never stations.
- When an event happens:
  - an icon is shown on the affected train on the map (every affected
	train, not only yours) for as long as the event is active;
  - a short text popup is shown **only if it is your train**, and only in
	map view (no popups in station view);
  - departure boards and platform signs show the resulting delay, or
	"Cancelled".

| Event          | Effect                                                     |
|----------------|------------------------------------------------------------|
| Drunk driver   | Long stop, random duration (e.g. 30–60 min) until a new driver arrives.     ||
| Slow down      | Train moves at 50% speed on a section.                     |
| Cancel         | Train is cancelled; happens only right before its timetable start |

- A cancelled train that has not departed yet shows "Cancelled" on the
  board and never arrives.
- Codebase should be adjusted so that more events can be added without much effort

## Time reversal (rewind)
- Only available in map view. To rewind while in a station, switch to map
  view first.
- Hold `Space` to scrub backwards, like rewinding a tape. Release to
  continue from that moment.
- While rewinding: the clock runs backwards, trains visibly move backwards,
  and there is a tape/VHS-style screen effect.
- Speed: holding for 5 real seconds rewinds 1 in-game hour (12 in-game
  minutes per real second).
- One rewind meter for the whole run: 3 in-game hours (= 15 real seconds of
  holding). Never refills.
- Cost is 1:1: rewinding 10 in-game minutes uses 10 minutes of meter. The
  meter only drains while time is actually going backwards.
- When the meter is empty you just keep going.
- Cannot rewind past the start of the run (the generated start time). The
  meter does not drain while blocked there.
- The player rewinds with the world. After releasing:
  - If you were on a train at that moment, you are back on that train, in
	map view.
  - If you were in a station at that moment, you are put at that station's
    entrance, in station view. This is also true if you were mid-walk in a
    station you have since left.
- No markers or ghosts after a rewind; the player only has their own memory.

## Station view (top-down, WASD)
- Every time you get off a train you are in station view and walk to your
  next platform. Same rules for every station.
- Camera follows the player.
- Each station has one fixed entrance point (spawn point after a rewind and
  at run start).
- Inside: walkable paths from OSM data and platforms only (no crowds or obstacles). Movement based on path graph from an osm export.
- Trains that stop at the station are visible at their platforms: arriving,
  waiting, leaving. Trains passing through without stopping are not shown.
- Finding your train:
  - The departure board is at the station entrance. Walk up to it and press
    `E` to open a full-screen overlay listing upcoming trains: time,
    destination, platform, delay/"Cancelled". The number of rows is up to
    the implementer.
  - Each platform has a sign showing its next train: time, destination,
    delay.
- Board by touching any train standing at a platform, with no confirmation.
  Boarding the wrong train is the player's own fault.
- While in a station you can switch between station view and map view
  (`Tab`).

## Implementation notes
- The world never reacts to the player. So the whole world state (train
  positions, delays, cancellations) should be computed directly from the
  clock time: `state = f(timetable, events, time)`.
- That makes rewind simple: just move the clock back. No world snapshots.
- Only the player's own history needs to be recorded over time: which train
  they were on or which station they were in. Rewind looks
  up that history at the new time.
- Fonts must render Polish characters (ą, ć, ę, ł, ń, ó, ś, ź, ż) for
  station names.
- Rendering resolution: standard 1920x1080 with pixelart-compatible texture scaling

## Not decided yet
- Which lines/cities are on the map (real network size for the jam).
- List of start cities (must fit the ~5-minute run target).
- Map data source and file format.
- Size of the deadline buffer - make it a config constant
- Zoom levels (min/max).
- Exact stop lengths for events, slow-down section length.
- Assets list for the artist, music and sound.

## Future (not for the jam)
- Collisions in station view.
- Single-track bottlenecks (trains blocking each other).
- Reroute event (train takes a different path, skips some stops, still ends
  at its original terminus).
- Joke rating on the end screen.

## Team
2-day jam. 3 people (lots of AI help for code), 1 artist. Keep art needs small.

## Minimum shippable version
One route, one transfer, one station, working rewind.

Cut order if time runs short (first cut first):
1. OSM-based station layouts
2. Reroute (already moved to Future)
3. Slow down event
4. Multiple start cities
5. Events entirely

Rewind and the station ↔ map loop are never cut.
