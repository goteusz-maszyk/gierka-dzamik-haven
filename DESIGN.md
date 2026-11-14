# Game design (draft v2)

## Goal
You spawn in a random meme city nobody likes and must reach Kraków (the
gamejam city) by a deadline. Arriving late is not game over; it only makes
your result worse.

- One level per run.
- Start city is random; destination is always Kraków.
- Route is free: any combination of lines/trains.
- In-game text: English.

## Run flow
1. Run starts: start city is picked, timetables and events are generated
   (seeded), deadline is calculated.
2. Player spawns at the entrance of the start city's station, in station view.
3. Player walks to a platform and boards a train.
4. While riding (map view), player marks the stop to get off at.
5. At that stop the player is in station view again and walks to the next
   platform. Repeat until Kraków.
6. Arriving in Kraków ends the run and shows the end screen.

## Deadline
- Deadline = fastest possible route from start to Kraków + a fixed buffer.
- Fastest route is calculated from the generated timetable, ignoring events.

## Score
- Result is simply how many minutes late (or early) you arrived.
- Using rewind does not affect the result.

## End screen
- Shows: arrival time, deadline, minutes late/early.
- Restart button (new run, new start city, new timetables and events).

## HUD (always visible)
- Clock (current in-game time).
- Deadline / time remaining.
- Rewind meter (bar).
- Current train and your marked stop (when riding).

## Time
- One in-game clock for everything.
- Map view: 3 in-game hours = 5 real minutes (tune later).
- Station view: clock runs slower than in map view so walking feels fair.

## Map view
- Real Polish rail network, drawn simplified in a clean Mini Metro style
  (vector art).
- Camera follows the player (your train, or your station when you are in
  one). Zoom only, no free panning.
- All trains move at the same time and are visible on the map.
- Map view is for watching, planning and rewinding. You can never board a
  train from the map.

### Riding a train
- Click a later stop on your train's route to mark "get off here".
- You can only mark stops where the train actually stops (not stations it
  passes through).
- You can move the mark to another valid stop or cancel it any time before
  arriving.
- When the train reaches the marked stop you get off and enter station view.
- No mark: you get off at the line's last stop.
- If your train is cancelled or rerouted and your marked stop is no longer on
  its route, you are dropped at the next stop it still serves.
- The player judges transfers on their own (no hints, no route planner).

## Trains and timetables
- Timetables are generated per run (seeded), from the lines and a frequency.
- Every train waits a fixed short time at each stop (e.g. 2 in-game minutes,
  tune later).
- Missed the train: wait in the station for the next one.

## Events
- Generated once per run (seeded). Rewinding replays the exact same events.
  Restarting generates new ones.
- Many per run (15+). They affect every train on the map, not only yours.
- Events only affect trains, never stations.
- When an event happens: a short text popup and an icon on the affected
  train/track.

| Event              | Effect                                                    |
|--------------------|-----------------------------------------------------------|
| Maszynista zachlał | Long stop (e.g. 30–60 min) until a new driver arrives.    |
| Rogatki            | Short stop (e.g. 5–15 min).                               |
| Slow down          | Train moves slower on a section.                          |
| Cancel             | Train is cancelled; passengers dropped at the next stop.  |
| Reroute            | Train takes a different path and skips some stops.        |

More events TBD.

## Time reversal (rewind)
- Only available in map view (also while waiting in a station: switch to map
  view first).
- Hold a key to scrub backwards, like rewinding a tape. Release to continue
  from that moment.
- Speed: holding for 5 real seconds rewinds 1 in-game hour.
- One rewind meter for the whole run: 3 in-game hours. Never refills.
- Cost is 1:1: rewinding 10 in-game minutes uses 10 minutes of meter.
- When the meter is empty you just keep going.
- Cannot rewind past the start of the run.
- The player rewinds with the world:
  - If you were on a train at that moment, you are back on that train.
  - If you were in a station at that moment, you are put at the station
    entrance.
- No markers or ghosts after a rewind; the player only has their own memory.

## Station view (top-down, WASD)
- Every time you get off a train you are in station view and walk to your
  next platform. Same rules for every station (no small/big distinction).
- Station layouts are reconstructed from the real station's paths in
  OpenStreetMap.
- Inside: walkable paths and platforms only (no crowds or obstacles for the
  jam).
- Finding your train:
  - A departure board in the station lists trains, times and platforms.
  - Each platform has a sign showing its next train.
- Board by touching the train.
- While in a station you can switch between station view and map view.

## Not decided yet
- List of start cities.
- Size of the deadline buffer.
- How much slower the station clock runs.
- Key bindings (rewind key, switch station/map view).
- Exact stop lengths for events and how reroutes pick their new path.
- Which lines/cities are on the map.

## Team
2-day jam. 3 people (lots of AI help for code), 1 artist. Keep art needs small.

## Minimum shippable version
One route, one transfer, one station, working rewind.
