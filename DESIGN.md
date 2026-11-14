# Game design (draft v1)

## Goal
You spawn in a random meme city nobody likes and must reach the gamejam city
by a deadline. Arriving late is not game over; it lowers your score.

- One level per run.
- Start and destination are random (details TBD).
- Route is free: any combination of lines/trains.
- In-game text: English.

## Score
Based on:
- how late you arrived
- how much rewind you used

## Time
- One in-game clock for everything.
- Starting ratio: 3 in-game hours = 5 real minutes (tune later).

## Map view
- Clean Mini Metro look, vector art.
- Trains follow a fixed timetable. All trains move at the same time and are
  visible on the map; a clock shows the current time.
- The player picks which train to board.
- While riding, click a later stop to mark "get off here"; you get off when the
  train reaches it.
- The player judges transfers on their own (no hints).

## Events
- Generated once per run (seeded). Rewinding replays the exact same events.
  Restarting the game generates new ones.
- Affect every train on the map, not only yours.
- Types: slow down, stop for X minutes, cancel, reroute.
- Ideas: maszynista zachlał, rogatki. More TBD.

## Time reversal
- Only available in map view.
- Continuous scrubbing backwards (like rewinding a tape), up to 3h back from
  the current moment.
- The player rewinds with the world (e.g. back on the train before getting off).
- One rewind meter for the whole run; rewinding further drains more of it.
- When the meter is empty you just keep going (and likely arrive late).
- Works from map view while waiting in a station too (not only on a train).
- No markers after a rewind; the player only has their own memory.

## Station view (top-down, WASD)
- Run starts in the start city's station; walk to your first train.
- Two layouts: small station and big station (jam scope).
- Walk to the correct platform; board by touching the train.
- Missed the train: wait in the station for the next one.
- While in a station you can switch between station view and map view.

## Not decided yet
- What is inside stations: obstacles, crowds, signs, stairs (check with team).
- Whether events can happen inside stations.
- Clock speed in station view: same as map for now, maybe slower.
- Size of the rewind meter (start with 3h, tune later).
- How start/destination cities and the deadline are picked.

## Team
2-day jam. 3 people (lots of AI help for code), 1 artist. Keep art needs small.

## Minimum shippable version
One route, one transfer, one station, working rewind.
