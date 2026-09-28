#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define SF_BREAK_TRIGGER_ONLY (1 << 0)
#define SF_BREAK_TOUCH        (1 << 1)
#define SF_BREAK_PRESSURE     (1 << 2)

#define MATERIAL_UNBREAKABLE_GLASS 7

#define FSOLID_NOT_SOLID (1 << 2)

#define DAMAGE_NO          0
#define DAMAGE_EVENTS_ONLY 1

// Touch damage is GetSmoothedVelocity().Length() * 0.01, applied as DMG_CRUSH
// (which breakables don't scale). The damage is truncated to an integer before
// it's taken from health, so at least 1 damage (100 u/s) is needed to break
// anything.
#define MAX_TOUCH_SPEED        3500 // highest sv_maxvelocity value in GOKZ
#define TOUCH_SPEED_PER_DAMAGE 100

// Highest single hit a player can deal before breakable damage modifiers are
// applied (the R8 Revolver's base damage; a knife stab is 65). minhealthdmg is
// compared against this raw value.
#define MAX_PLAYER_HIT_DAMAGE 86

#define MAX_TARGET_NAME 128

// Breaking everything in one tick sends every break effect in the same network
// update, which can hitch clients or overflow the engine's temp entity buffer.
#define BREAKS_PER_TICK 4

enum BreakMethod {
    Break_None = 0,
    Break_Pressure,
    Break_Touch,
    Break_Damage
};

static const char g_BreakMethodNames[][] = {
    "none",
    "pressure",
    "touch",
    "damage"
};

// Strings that suggest an output can heal a breakable or change how it takes
// damage. Outputs are searched for these anywhere, ignoring case.
static const char g_ProblemStrings[][] = {
    "AddHealth",
    "AddOutput",
    "Script",
    "SetDamageFilter",
    "SetHealth"
};

enum struct LumpEntity {
    char hammerid[16];
    char targetname[MAX_TARGET_NAME];
}

StringMap g_MapControlledBreakables = null;
// Breakables with an OnBreak output aimed at !activator. The plugin breaks
// without an activator, so the output does nothing, and once the breakable is
// gone no player can trigger it either.
StringMap g_ActivatorBreakables = null;
// Entity references still to be broken. Non-null while a break is running.
ArrayList g_BreakQueue = null;

public Plugin myinfo = {
    name        = "gokz-nofun",
    author      = "jvnipers, catmint",
    description = "Breaks all func_breakable entities on command",
    version     = "1.1.0",
    url         = "https://github.com/misscatmint/gokz-nofun/"
};

public void OnPluginStart() {
    RegConsoleCmd("sm_nofun", Cmd_BreakAll, "Break all breakables");
    RegConsoleCmd("sm_breakall", Cmd_BreakAll, "Break all breakables");
    RegConsoleCmd("sm_checkfun", Cmd_BreakAllDebug, "List all breakables");
    RegConsoleCmd("sm_checknofun", Cmd_BreakAllDebug, "List all breakables");
    RegConsoleCmd("sm_checkbreakall", Cmd_BreakAllDebug, "List all breakables");
}

public void OnMapStart() {
    delete g_MapControlledBreakables;
    delete g_ActivatorBreakables;
    g_MapControlledBreakables = new StringMap();
    g_ActivatorBreakables = new StringMap();

    // Targets of outputs (from any entity) that contain a problem string.
    ArrayList healedTargets = new ArrayList(ByteCountToCells(MAX_TARGET_NAME));
    ArrayList breakables = new ArrayList(sizeof(LumpEntity));

    char keyName[64];
    char value[1024];
    char classname[64];
    char target[MAX_TARGET_NAME];
    LumpEntity lumpEntity;
    bool controlsSelf = false;
    bool needsActivator = false;

    int totalEntries = EntityLump.Length();
    for (int i = 0; i < totalEntries; ++i) {
        EntityLumpEntry entry = EntityLump.Get(i);

        classname[0] = '\0';
        lumpEntity.hammerid[0] = '\0';
        lumpEntity.targetname[0] = '\0';
        controlsSelf = false;
        needsActivator = false;

        // Read the entity's keyvalues and outputs in a single pass. Whether
        // this is a breakable isn't known until classname has been seen, so
        // anything that would flag it is remembered in controlsSelf and
        // needsActivator.
        int totalKeys = entry.Length;
        for (int j = 0; j < totalKeys; ++j) {
            entry.Get(j, keyName, sizeof(keyName), value, sizeof(value));
            if (!IsOutputKey(keyName)) {
                if (StrEqual(keyName, "classname", false))
                    strcopy(classname, sizeof(classname), value);
                else if (StrEqual(keyName, "hammerid", false))
                    strcopy(lumpEntity.hammerid, sizeof(lumpEntity.hammerid), value);
                else if (StrEqual(keyName, "targetname", false))
                    strcopy(lumpEntity.targetname, sizeof(lumpEntity.targetname), value);
                continue;
            }

            // A breakable that reacts to damage (boost pads, hit counters,
            // etc.) is gameplay: the Break input skips health changes, so these
            // reactions would never happen if the plugin broke it. A breakable
            // with a problem string anywhere in its own outputs is assumed to
            // be healing itself (e.g. via !self).
            if (StrEqual(keyName, "OnHealthChanged", false) ||
                    ContainsProblemString(value))
                controlsSelf = true;

            int restStart = GetOutputTarget(value, target, sizeof(target));
            if (restStart != -1 && StrEqual(keyName, "OnBreak", false) &&
                    StrEqual(target, "!activator", false))
                needsActivator = true;

            // An output aimed at another entity (e.g. a logic_timer firing
            // SetHealth at a breakable) marks its target. !self, !activator,
            // !caller etc. are resolved at runtime, not by name, so they're
            // skipped.
            if (restStart != -1 && target[0] != '\0' && target[0] != '!' &&
                    ContainsProblemString(value[restStart]))
                healedTargets.PushString(target);
        }

        if (lumpEntity.hammerid[0] != '\0' &&
                StrEqual(classname, "func_breakable", false)) {
            breakables.PushArray(lumpEntity);
            if (controlsSelf)
                g_MapControlledBreakables.SetValue(lumpEntity.hammerid, true);
            if (needsActivator)
                g_ActivatorBreakables.SetValue(lumpEntity.hammerid, true);
        }

        delete entry;
    }

    // Flag every breakable whose targetname a recorded target matches.
    int totalBreakables = breakables.Length;
    int totalTargets = healedTargets.Length;
    for (int i = 0; i < totalBreakables; ++i) {
        breakables.GetArray(i, lumpEntity);
        for (int j = 0; j < totalTargets; ++j) {
            healedTargets.GetString(j, target, sizeof(target));
            if (NameMatches(target, lumpEntity.targetname)) {
                g_MapControlledBreakables.SetValue(lumpEntity.hammerid, true);
                break;
            }
        }
    }

    delete healedTargets;
    delete breakables;
}

public void OnMapEnd() {
    delete g_MapControlledBreakables;
    delete g_ActivatorBreakables;
    delete g_BreakQueue;
}

static bool IsOutputKey(const char[] key) {
    return (key[0] == 'O' || key[0] == 'o') && (key[1] == 'n' || key[1] == 'N');
}

static bool ContainsProblemString(const char[] str) {
    for (int i = 0; i < sizeof(g_ProblemStrings); ++i) {
        if (StrContains(str, g_ProblemStrings[i], false) != -1)
            return true;
    }
    return false;
}

// Copies an output's target (everything before the first separator: ESC in
// newer map versions, a comma in older ones) and returns the index where the
// rest of the output starts, or -1 if there's no separator.
static int GetOutputTarget(const char[] value, char[] target, int targetLen) {
    int separator = (FindCharInString(value, '\x1b') != -1) ? '\x1b' : ',';
    int end = FindCharInString(value, separator);
    if (end == -1)
        return -1;

    strcopy(target, end + 1 < targetLen ? end + 1 : targetLen, value);
    return end + 1;
}

// Case-insensitive name match supporting a trailing * wildcard.
static bool NameMatches(const char[] pattern, const char[] name) {
    int len = strlen(pattern);
    if (len > 0 && pattern[len - 1] == '*')
        return len == 1 || strncmp(name, pattern, len - 1, false) == 0;
    return StrEqual(name, pattern, false);
}

static bool IsInHammerIdSet(StringMap set, int entity) {
    char hammerid[16];
    IntToString(GetEntProp(entity, Prop_Data, "m_iHammerID"), hammerid,
                           sizeof(hammerid));
    return set != null && set.ContainsKey(hammerid);
}

// Mirrors CBreakable::BreakTouch and CBreakable::OnTakeDamage from the Source
// SDK to decide how (if at all) a player could break this entity.
static BreakMethod GetPlayerBreakMethod(int entity) {
    int spawnFlags = GetEntProp(entity, Prop_Data, "m_spawnflags");

    // Touch is disabled entirely, and damage is disabled at spawn.
    if ((spawnFlags & SF_BREAK_TRIGGER_ONLY) != 0)
        return Break_None;

    // BreakTouch returns before the touch and pressure checks, and the Break
    // input does nothing, when IsBreakable() is false.
    if (GetEntProp(entity, Prop_Data, "m_Material") == MATERIAL_UNBREAKABLE_GLASS)
        return Break_None;

    // Players can't touch, stand on or shoot a non-solid breakable. Die() also
    // sets this before firing OnBreak, so it catches breakables that already
    // broke but haven't been removed yet (removal waits 0.1s).
    if ((GetEntProp(entity, Prop_Data, "m_usSolidFlags") & FSOLID_NOT_SOLID) != 0)
        return Break_None;

    // Every way a player breaks it passes them as the activator, including
    // pressure, so this has to be checked before the pressure flag.
    if (IsInHammerIdSet(g_ActivatorBreakables, entity))
        return Break_None;

    // Pressure breaking schedules Die() directly, ignoring health, takedamage
    // and minhealthdmg, so nothing the map does to its health matters.
    if ((spawnFlags & SF_BREAK_PRESSURE) != 0)
        return Break_Pressure;

    // Touch and damage both go through CBreakable::OnTakeDamage, which rejects
    // anything the damage filter doesn't pass. Whether players pass can't be
    // known ahead of time, so any filter is treated as blocking them.
    if (IsInHammerIdSet(g_MapControlledBreakables, entity) ||
            GetEntPropEnt(entity, Prop_Data, "m_hDamageFilter") != -1)
        return Break_None;

    int minHealthDmg = GetEntProp(entity, Prop_Data, "m_iMinHealthDmg");

    // Touch breaking forces takedamage on, so it works even at health 0. The
    // damage must still reach health, minhealthdmg and 1 (see above).
    if ((spawnFlags & SF_BREAK_TOUCH) != 0) {
        int health = GetEntProp(entity, Prop_Data, "m_iHealth");
        int required = health > 1 ? health : 1;
        if (minHealthDmg > required)
            required = minHealthDmg;
        if (required <= MAX_TOUCH_SPEED / TOUCH_SPEED_PER_DAMAGE)
            return Break_Touch;
        // Too strong to break by touch, but it may still take weapon damage.
    }

    // Health 0 and Only Break on Trigger both set takedamage to DAMAGE_NO. The
    // health used is the one after propdata is applied at spawn (e.g.
    // Metal.Medium sets it to 0), which is why this reads the live entity.
    // Checking takedamage rather than health also catches health-0 glass,
    // which the engine gives 1 health so bullets can pass through it.
    // DAMAGE_EVENTS_ONLY (only settable at runtime) never lowers health, so it
    // can't be broken this way either. A player must also be able to deal
    // minhealthdmg in a single hit.
    int takeDamage = GetEntProp(entity, Prop_Data, "m_takedamage");
    if (takeDamage == DAMAGE_NO || takeDamage == DAMAGE_EVENTS_ONLY ||
            minHealthDmg > MAX_PLAYER_HIT_DAMAGE)
        return Break_None;
    return Break_Damage;
}

Action Cmd_BreakAll(int client, int args) {
    return RunNoFun(client, true);
}

Action Cmd_BreakAllDebug(int client, int args) {
    return RunNoFun(client, false);
}

// Breaks every breakable a player could break, or (if breakThem is false)
// lists them in the client's console.
static Action RunNoFun(int client, bool breakThem) {
    float origin[3];
    char targetname[MAX_TARGET_NAME];

    if (breakThem) {
        if (g_BreakQueue != null) {
            ReplyToCommand(client,
                "Hold your horses! I'm still breaking things! >:O");
            return Plugin_Handled;
        }
        g_BreakQueue = new ArrayList();
    }

    int count = 0;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_breakable")) != -1) {
        BreakMethod method = GetPlayerBreakMethod(entity);
        if (method == Break_None)
            continue;

        ++count;
        if (breakThem) {
            g_BreakQueue.Push(EntIndexToEntRef(entity));
            continue;
        }

        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
        GetEntPropString(entity, Prop_Data, "m_iName", targetname,
                         sizeof(targetname));
        if (targetname[0] == '\0')
            strcopy(targetname, sizeof(targetname), "<unnamed>");

        PrintToConsole(client,
            "#%d | Entity %d | Name: %s | HP: %d | Via: %s | Pos: %.1f, %.1f, %.1f",
            count, entity, targetname, GetEntProp(entity, Prop_Data, "m_iHealth"),
            g_BreakMethodNames[method], origin[0], origin[1], origin[2]);
    }

    if (breakThem) {
        if (count > 0)
            RequestFrame(Frame_BreakBatch, g_BreakQueue);
        else
            delete g_BreakQueue;
    }

    if (count == 0)
        ReplyToCommand(client,
            "The fun's already over. There's nothing to break :(");
    else if (breakThem)
        ReplyToCommand(client,
            "No more fun. Breaking %d breakable%s >:(", count, count > 1 ? "s" : "");
    else if (GetCmdReplySource() != SM_REPLY_TO_CONSOLE)
        ReplyToCommand(client,
            "%d breakable%s >:/ (see console)", count, count > 1 ? "s" : "");
    return Plugin_Handled;
}

// Breaks up to BREAKS_PER_TICK queued breakables, then schedules itself for the
// next frame until the queue is empty.
void Frame_BreakBatch(ArrayList queue) {
    // The queue was deleted by a map change after this frame was requested.
    if (queue != g_BreakQueue)
        return;

    int broken = 0;
    while (broken < BREAKS_PER_TICK && queue.Length > 0) {
        int last = queue.Length - 1;
        int entity = EntRefToEntIndex(queue.Get(last));
        queue.Erase(last);

        // Skip breakables removed or changed since the command ran, including
        // ones already broken by a player, the map or an explosion.
        if (entity != INVALID_ENT_REFERENCE &&
                GetPlayerBreakMethod(entity) != Break_None) {
            AcceptEntityInput(entity, "Break");
            ++broken;
        }
    }

    if (queue.Length > 0)
        RequestFrame(Frame_BreakBatch, queue);
    else
        delete g_BreakQueue;
}
