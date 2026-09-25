# gokz-nofun

Plugin breaks all `func_breakable` entities on command.

This plugin will only break entities it's reasonably sure players can break.
It does this to ensure gameplay elements on a map aren't broken and the map
can still be completed.

## Commands

- `sm_nofun` / `sm_breakall` - break all player-breakable entities.
- `sm_checkfun` / `sm_checknofun` / `sm_checkbreakall` - list
  player-breakable entities.

## What entities the plugin will break

Checks (in order) for determining what `func_beakable` entities we think
players can break:

1. It MUST NOT have the `Only Break on Trigger` spawn flag.
2. If it has the `Break on Pressure` flag, we assume it can always be broken
   by players (and the other conditions below are not checked).
3. It MUST NOT have a material type property of `Unbreakable Glass`.
4. Its health MUST be greater than 0.
5. If it has the `Break on Touch` spawn flag, its health MUST be low enough to
   be broken by a player colliding at 3500 units of velocity or lower. If it
   can be broken by player collision, the conditions below are not checked.
6. If all other conditions are satisfied, then it also MUST NOT have outputs
   that use `AddHealth`, `AddOutput`, `SetDamageFilter`, or `SetHealth` inputs
   (or any other input with `Script` in the name).

Notes:

- An entity could have a `minhealthdmg` value that makes it unbreakable
  through knife or weapon damage. However, the map itself could inflict high
  enough damage on the breakable to break it (through explosions, physics,
  crushing, etc.). The plugin ignores this value and will break these entities
  even if the map provides no way to break them.
- The plugin makes no effort to check for `logic_script` entities that use
  VScript to heal breakables.
- Other entities that can respawn breakables (like `point_template` entities)
  are not considered. It is possible for the map to respawn breakables the
  plugin broke.
