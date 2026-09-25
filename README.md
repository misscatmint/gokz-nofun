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
4. If it has the `Break on Touch` spawn flag, its health MUST be low enough to
   be broken by a player colliding at 3500 units of velocity or lower.
5. If all other conditions are satisfied, then it also MUST NOT have
   `OnHealthChanged` or `OnTakeDamage` outputs.

Notes:

- The plugin makes no effort to see what an entity with
  `OnHealthChanged`/`OnTakeDamage` outputs does in them. These are often used
  to make self-healing entities, which we do not want to break. But this has
  the limitation that the plugin will not break entities that use them but do
  not self-heal (which are breakables that players could still break).
- Other entities that can respawn breakables (like `point_template` entities)
  are not considered. It is possible for the map to respawn breakables the
  plugin broke.
