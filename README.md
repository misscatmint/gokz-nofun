# gokz-nofun

Breaks all breakables in the map on command.

This plugin will only break breakables it's reasonably sure players can
actually break. It does this to ensure gameplay elements on a map aren't
broken and the map can still be completed.

## Commands

- `sm_nofun` / `sm_breakall` - break all player-breakable breakables.
- `sm_checkfun` / `sm_checknofun` / `sm_checkbreakall` - list
  player-breakable breakables, and how each one can be broken (by pressure,
  touch, or damage).

## Requirements

- SourceMod 1.12 or newer.

## What breakables the plugin will break

*This section and the notes below are mainly for mappers and server admins.*

A `func_breakable` is broken only if a player could break it themselves. It's
always skipped if it has the `Only Break on Trigger` flag, the `Unbreakable
Glass` material type, or an `OnBreak` output that targets `!activator`.

The plugin breaks breakables by sending them the `Break` input with no
activator, so breakables that target `!activator` are skipped to avoid
situations where the map may rely them, for example to give the player a name
a filter checks later.

Otherwise, it's broken if a player could break it in one of these ways:

- **Standing on it** - it has the `Break on Pressure` flag.
- **Colliding with it** - it has the `Break on Touch` flag, and its health and
  `minhealthdmg` are both 35 or less. Colliding with a breakable deals 1
  damage for every 100 u/s of speed, and players can reach up to 3500 u/s, so
  the most damage a player can deal this way is 35. (This works even if it has
  0 health.)
- **Shooting or knifing it** - it can take damage (the engine turns this off
  for breakables with 0 health, and damage doesn't lower health if the map has
  set its `takedamage` to `events only`), and its `minhealthdmg` is at most
  86, the most damage a player can deal in one hit (with an R8).

Colliding with it and shooting it don't count if it has a damage filter, since
the plugin can't tell ahead of time whether players pass it. They also don't
count if the map controls the breakable in a way that could heal it, which the
plugin considers true in any of these cases:

- It has an `OnHealthChanged` output. The plugin breaks breakables without
  damaging them, so these reactions would never happen.
- One of its own outputs mentions `AddHealth`, `AddOutput`, `Script`,
  `SetDamageFilter`, or `SetHealth`.
- Another entity's output targets it by name and mentions one of those words,
  like a `logic_timer` firing `SetHealth` at it.

Spawn flags, material types, `minhealthdmg`, `takedamage`, and damage filters
are read from live entity data. Outputs are read from map data when the map
loads.

### Caveats

- The plugin could break a breakable the map tries to protect with:
  - outputs created while the map is running, including ones added with
    `AddOutput`;
  - outputs that target it by classname, or with a `*` anywhere but the end of
    its name;
  - outputs that target `!activator`, `!caller`, or other `!` names; or
  - VScript, such as a `logic_script` that heals it or reacts to its health
    changing.
- The map may bring back breakables the plugin broke, for example with a
  `point_template` entity.
