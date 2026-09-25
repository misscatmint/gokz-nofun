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

methodmap IntStringMap < StringMap
{
    public IntStringMap()
    {
        return view_as<IntStringMap>(new StringMap());
    }

    public void SetIntKey(int key, any value)
    {
        char keyStr[16];
        IntToString(key, keyStr, sizeof(keyStr));
        this.SetValue(keyStr, value);
    }

    public bool GetIntKey(int key, any &value)
    {
        char keyStr[16];
        IntToString(key, keyStr, sizeof(keyStr));
        return this.GetValue(keyStr, value);
    }

    public bool ContainsIntKey(int key)
    {
        char keyStr[16];
        IntToString(key, keyStr, sizeof(keyStr));
        return this.ContainsKey(keyStr);
    }
}

IntStringMap g_Breakables = null;

public Plugin myinfo =
{
    name        = "gokz-nofun",
    author      = "jvnipers, catmint",
    description = "Breaks all func_breakable entities on command",
    version     = "1.0.1",
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
    if (g_Breakables != null)
    {
        return;
    }

    g_Breakables = new IntStringMap();
    int totalEntries = EntityLump.Length();
    int key = -1;
    char keyName[64];
    char value[64];
    int hammerId = -1;
    int spawnFlags = 0;
    int totalOutputs = -1;
    int health = 0;
    bool mightHeal = false;
    for (int i = 0; i < totalEntries; i++)
    {
        // Checks (in order) for determining what func_beakables we think
        // players can break:
        //
        // 1. It MUST NOT have the SF_BREAK_TRIGGER_ONLY spawn flag.
        // 2. If it has the SF_BREAK_PRESSURE flag, we assume it can
        //    always be broken by players (and the other conditions below
        //    are not checked).
        // 3. It MUST NOT have a material type property of
        //    MATERIAL_UNBREAKABLE_GLASS.
        // 4. If it has the SF_BREAK_TOUCH spawn flag, its health MUST be
        //    low enough to be broken by a player colliding at 3500 units
        //    of velocity or lower.
        // 5. If all other conditions are satisfied, then it also MUST NOT
        //    have OnHealthChanged or OnTakeDamage outputs.
        //
        // Notes:
        // - This makes no effort to see what an entity with
        //   OnHealthChanged/OnTakeDamage outputs does in them. These are
        //   often used to make self-healing entities, which we do not want to
        //   break. But this has the limitation that the plugin will not break
        //   entities that use them but do not self-heal (which are
        //   breakables that players could still break).
        // - Other entities that can respawn breakables (like point_template
        //   entities) are not considered. It is possible for the map to
        //   respawn breakables the plugin broke.
        EntityLumpEntry entry = EntityLump.Get(i);
        key = entry.FindKey("classname");
        if (key == -1)
        {
            delete entry;
            continue;
        }
        entry.Get(key, _, _, value, sizeof(value));
        if (!StrEqual(value, "func_breakable"))
        {
            delete entry;
            continue;
        }

        key = entry.FindKey("hammerid");
        if (key == -1)
        {
            delete entry;
            continue;
        }
        entry.Get(key, _, _, value, sizeof(value));
        hammerId = StringToInt(value);

        spawnFlags = 0;
        key = entry.FindKey("spawnflags");
        if (key != -1)
        {
            entry.Get(key, _, _, value, sizeof(value));
            spawnFlags = StringToInt(value);
        }
        if (spawnFlags & SF_BREAK_TRIGGER_ONLY != 0)
        {
            delete entry;
            continue;
        }
        if (spawnFlags & SF_BREAK_PRESSURE != 0)
        {
            g_Breakables.SetIntKey(hammerId, true);
            delete entry;
            continue;
        }

        key = entry.FindKey("material");
        if (key != -1)
        {
            entry.Get(key, _, _, value, sizeof(value));
            if (StringToInt(value) == MATERIAL_UNBREAKABLE_GLASS)
            {
                delete entry;
                continue;
            }
        }

        health = 0;
        key = entry.FindKey("health");
        if (key != -1)
        {
            entry.Get(key, _, _, value, sizeof(value));
            health = StringToInt(value);
        }
        if (spawnFlags & SF_BREAK_TOUCH != 0)
        {
            if (health * TOUCH_SPEED_PER_HEALTH <= MAX_TOUCH_SPEED)
            {
                g_Breakables.SetIntKey(hammerId, true);
            }
            delete entry;
            continue;
        }

        mightHeal = false;
        totalOutputs = entry.Length;
        for (int j = 0; j < totalOutputs; j++)
        {
            entry.Get(j, keyName, sizeof(keyName), _, _);
            if (StrEqual(keyName, "onhealthchanged", false) || StrEqual(keyName, "ontakedamage", false))
            {
                mightHeal = true;
                break;
            }
        }

        if (mightHeal)
        {
            delete entry;
            continue;
        }

        g_Breakables.SetIntKey(hammerId, true);
        delete entry;
    }
}

public void OnMapEnd()
{
    if (g_Breakables != null)
    {
        delete g_Breakables;
        g_Breakables = null;
    }
}

static bool PlayerCanBreak(int entity)
{
    if (!HasEntProp(entity, Prop_Data, "m_iHammerID"))
    {
        return false;
    }
    return g_Breakables.ContainsIntKey(GetEntProp(entity, Prop_Data, "m_iHammerID"));
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
