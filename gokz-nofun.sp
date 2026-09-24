#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name        = "gokz-nofun",
    author      = "jvnipers",
    description = "Breaks all func_breakable entities on command",
    version     = "0.0.1",
    url         = "https://github.com/misscatmint/gokz-nofun"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_nofun", Cmd_BreakAll, "Break all func_breakable entities");
    RegConsoleCmd("sm_nofun_debug", Cmd_BreakAllDebug, "Break all func_breakable entities with debug info");
    RegConsoleCmd("sm_breakall", Cmd_BreakAll, "Break all func_breakable entities");
    RegConsoleCmd("sm_breakall_debug", Cmd_BreakAllDebug, "Break all func_breakable entities with debug info");
}

Action Cmd_BreakAll(int client, int args)
{
    int count = 0;
    int entity = -1;

    while ((entity = FindEntityByClassname(entity, "func_breakable")) != -1)
    {
        AcceptEntityInput(entity, "Break");
        count++;
    }

    ReplyToCommand(client, "No more fun. Broke %d func_breakable entities.", count);
    return Plugin_Handled;
}

Action Cmd_BreakAllDebug(int client, int args)
{
    int count = 0;
    int entity = -1;
    float origin[3];
    char targetname[128];
    int health;

    ReplyToCommand(client, "No more fun. View console for details...");

    while ((entity = FindEntityByClassname(entity, "func_breakable")) != -1)
    {
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

        AcceptEntityInput(entity, "Break");
    }

    ReplyToCommand(client, "Broke %d func_breakable entities", count);
    return Plugin_Handled;
}
