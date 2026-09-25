# gokz-nofun

Plugin breaks all func_breakable entities on command, lists details on broken
entities when ran as debug.

This plugin will only break entities it's reasonably sure players can break.

Commands:

- `sm_nofun` / `sm_breakall` - break all reasonably-breakable entities.
- `sm_checkfun` / `sm_checknofun` / `sm_checkbreakall` - list
  reasonably-breakable entities.

## What the plugin will break

Checks for determining what `func_beakable` entities we think players can
break:

1. It MUST NOT have the `Only Break on Trigger` spawn flag.
2. Otherwise, if it has the `Break on Pressure` flag, we assume it can always
   be broken by players (the other conditions below are ignored in this case).
3. It MUST NOT have a material type property of `Unbreakable Glass`.
4. Otherwise, if it has the `Break on Touch` spawn flag and its health is low
   enough to be broken by a player colliding at 3500 units of velocity or
   lower, we assume it can always be broken by players (and any remaining
   conditions below are ignored).
5. If it does not have the `Only Beak on Trigger` or `Break on Pressure` spawn
   flags, it does not have a material type property if `Unbreakable Glass`,
   and it either does not have the `Break on Touch` spawn flag or it can be
   broken through realistic player collisions, then it also MUST NOT have
   `OnHealthChanged` or `OnTakeDamage` outputs.

Note that these checks are run in order, so if condition #2 is satisfied,
further conditions are not checked enforced. This also applies to condition
#4.
