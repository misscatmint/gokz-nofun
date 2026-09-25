#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define SF_BREAK_TRIGGER_ONLY             (1 << 0)
#define SF_BREAK_TOUCH                    (1 << 1)
#define SF_BREAK_PRESSURE                 (1 << 2)
#define SF_BREAK_PHYSICS                  (1 << 9)
#define SF_BREAK_DONT_TAKE_PHYSICS_DAMAGE (1 << 10)
#define SF_BREAK_NO_BULLET_PENETRATION    (1 << 11)

#define MATERIAL_UNBREAKABLE_GLASS 7

#define MAX_TOUCH_SPEED        3500 // highest sv_maxvelocity value in GOKZ
#define TOUCH_SPEED_PER_HEALTH 100

static const char g_HealingInputs[5][16] = {
    "AddHealth",
    "AddOutput",
    "Script",
    "SetDamageFilter",
    "SetHealth"
};

StringMap g_HealingBreakables = null;

public Plugin myinfo =
{
    name        = "gokz-nofun",
    author      = "jvnipers, catmint",
    description = "Breaks all func_breakable entities on command",
    version     = "1.0.4",
    url         = "https://github.com/misscatmint/gokz-nofun"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_nofun", Cmd_BreakAll, "Break all breakables");
    RegConsoleCmd("sm_breakall", Cmd_BreakAll, "Break all breakables");
    RegConsoleCmd("sm_checkfun", Cmd_BreakAllDebug, "List all breakables");
    RegConsoleCmd("sm_checknofun", Cmd_BreakAllDebug, "List all breakables");
    RegConsoleCmd("sm_checkbreakall", Cmd_BreakAllDebug, "List all breakables");
}

public void OnMapStart()
{
    if (g_HealingBreakables != null)
    {
        return;
    }

    g_HealingBreakables = new StringMap();
    int totalEntries = EntityLump.Length();
    char keyName[64];
    char value[64];
    char hammerId[16];
    int totalKeys = 0;
    bool mightHeal = false;
    for (int i = 0; i < totalEntries; i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        if (entry.GetNextKey("classname", value, sizeof(value)) == -1 ||
            !StrEqual(value, "func_breakable") ||
            entry.GetNextKey("hammerid", hammerId, sizeof(hammerId)) == -1)
        {
            delete entry;
            continue;
        }

        mightHeal = false;
        totalKeys = entry.Length;
        for (int j = 0; j < totalKeys; j++)
        {
            entry.Get(j, keyName, sizeof(keyName), value, sizeof(value));
            if (StrContains(keyName, "On", false) != 0)
            {
                continue;
            }

            for (int k = 0; k < sizeof(g_HealingInputs); k++)
            {
                if (StrContains(value, g_HealingInputs[k], false) != -1)
                {
                    mightHeal = true;
                    break;
                }
            }
            if (mightHeal)
            {
                g_HealingBreakables.SetValue(hammerId, true);
                break;
            }
        }

        delete entry;
    }
}

public void OnMapEnd()
{
    if (g_HealingBreakables != null)
    {
        delete g_HealingBreakables;
        g_HealingBreakables = null;
    }
}

static bool PlayerCanBreak(int entity)
{
    int spawnFlags = GetEntProp(entity, Prop_Data, "m_spawnflags");
    if (spawnFlags & SF_BREAK_TRIGGER_ONLY != 0)
    {
        return false;
    }
    if (spawnFlags & SF_BREAK_PRESSURE != 0)
    {
        return true;
    }

    if (GetEntProp(entity, Prop_Data, "m_Material") == MATERIAL_UNBREAKABLE_GLASS)
    {
        return false;
    }

    int health = GetEntProp(entity, Prop_Data, "m_iHealth");
    if (health < 1)
    {
        return false;
    }

    if (spawnFlags & SF_BREAK_TOUCH != 0)
    {
        return health * TOUCH_SPEED_PER_HEALTH <= MAX_TOUCH_SPEED;
    }

    char hammerId[16];
    IntToString(GetEntProp(entity, Prop_Data, "m_iHammerID"), hammerId, sizeof(hammerId));
    return !g_HealingBreakables.ContainsKey(hammerId);
}

Action Cmd_BreakAll(int client, int args)
{
    int count = 0;
    int entity = -1;

    while ((entity = FindEntityByClassname(entity, "func_breakable")) != -1)
    {
        if (PlayerCanBreak(entity))
        {
            AcceptEntityInput(entity, "Break");
            count++;
        }
    }

    if (count == 0)
    {
        ReplyToCommand(client, "The fun's already over. There's nothing to break :(", count);
    }
    else
    {
        ReplyToCommand(client, "No more fun. Broke %d breakable%s >:(", count, count > 1 ? "s" : "");
    }
    return Plugin_Handled;
}

Action Cmd_BreakAllDebug(int client, int args)
{
    int count = 0;
    int entity = -1;
    float origin[3];
    char targetname[128];
    int health = 0;

    while ((entity = FindEntityByClassname(entity, "func_breakable")) != -1)
    {
        if (!PlayerCanBreak(entity))
        {
            continue;
        }

        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
        GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
        health = GetEntProp(entity, Prop_Data, "m_iHealth");

        if (targetname[0] == '\0')
        {
            strcopy(targetname, sizeof(targetname), "<unnamed>");
        }

        count++;

        PrintToConsole(client, "#%d | Entity %d | Name: %s | HP: %d | Pos: %.1f, %.1f, %.1f",
            count, entity, targetname, health, origin[0], origin[1], origin[2]);
    }

    if (count == 0)
    {
        ReplyToCommand(client, "The fun's already over. There's nothing to break :(", count);
    }
    else if (GetCmdReplySource() != SM_REPLY_TO_CONSOLE)
    {
        ReplyToCommand(client, "%d breakable%s >:/ (see console)", count, count > 1 ? "s" : "");
    }
    return Plugin_Handled;
}
