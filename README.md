# Insight Tooltips

Adds the numbers the vanilla tooltips leave out. Hover an entity and the extra lines appear in its tooltip, next to what
Factorio already shows.

| Entity | Extra lines |
|---|---|
| Mining drill | **Output** including speed and productivity bonuses, and **Depletes in**: when the resources under the drill run out if it mines them alone |
| Inserter | **Throughput** chest to chest, using the inserter's real hand size |
| Chest, logistic chest, cargo wagon | **Items stored** and **Flow**: the fill or empty rate measured while you hover, with "full in" or "empty in" |
| Electric pole | **Accumulators**: when the network's accumulators are full or empty |
| Assembler, furnace, rocket silo | **Productivity bonus progress**, when the machine has productivity |

## How accurate is it?

The numbers were checked against the running game in automated tests:

- Inserter throughput matches the measured chest-to-chest rate exactly for burner, normal, long-handed, fast, bulk and
  stack inserters (a swing takes `ceil(angle / rotation speed) - 1` ticks in 2.1).
- Drill output matches the measured output within 1 %, including mining productivity research.
- Accumulator times match the energy flow of the network within a second.

Belts are slower to pick up from than chests, so an inserter taking items from a belt moves fewer items than shown.

## Performance

Lines are only computed for entities somebody is hovering (and refreshed every 30 ticks while hovered), and removed
when the hover ends. The rest of the map costs nothing.

## Settings (map settings)

Each entity group can be turned off, and the refresh interval can be changed.

## Remote interface

```lua
remote.call("insight-tooltips", "collect", entity)              -- { { key, name, value, raw }, ... }
remote.call("insight-tooltips", "watch", entity)                -- keep the lines on an entity without hovering
remote.call("insight-tooltips", "unwatch", entity)
remote.call("insight-tooltips", "inserter_throughput", entity)  -- items per second, hand size
```

`raw` is the number behind a line (items per second, seconds, items, ...).

Requires Factorio 2.1 (runtime tooltip fields). MIT license.
