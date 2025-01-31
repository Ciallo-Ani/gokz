#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

ConVar mp_flashlight;

public Plugin myinfo =
{
	name = "[CS:GO] Flash Light",
	author = "PŠΣ™ SHUFEN, Ciallo",
	description = "",
	version = "1.0",
	url = ""
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_flashlight", Command_FlashLight);
	HookEvent("player_team", Event_OnPlayer_Team_Pre, EventHookMode_Pre);

	mp_flashlight = FindConVar("mp_flashlight");
	if (mp_flashlight != null)
	{
		mp_flashlight.Flags &= ~FCVAR_DEVELOPMENTONLY;
		mp_flashlight.IntValue = 1;
		mp_flashlight.AddChangeHook(ConVarChange_FlashLight);
	}

	AddCommandListener(Command_LookAtWeapon, "+lookatweapon");
}

public Action Event_OnPlayer_Team_Pre(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsValidClient(client, true))
	{
		return Plugin_Continue;
	}

	SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") & ~4);

	return Plugin_Continue;
}

public void OnPluginEnd()
{
	if (mp_flashlight != null)
	{
		mp_flashlight.Flags |= FCVAR_DEVELOPMENTONLY;
	}
}

public void OnMapStart()
{
	PrecacheSound("items/flashlight1.wav");
}

public void ConVarChange_FlashLight(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (view_as<bool>(StringToInt(oldValue)) && !view_as<bool>(convar.IntValue))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				SetEntProp(i, Prop_Send, "m_fEffects", GetEntProp(i, Prop_Send, "m_fEffects") & ~4);
			}
		}
	}
}

public Action Command_LookAtWeapon(int client, const char[] command, int argc)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	if (mp_flashlight != null && mp_flashlight.IntValue)
	{
		ToggleFlashlight(client);
	}

	return Plugin_Continue;
}

public Action Command_FlashLight(int client, int args)
{
	if (mp_flashlight == null || !mp_flashlight.IntValue)
	{
		return Plugin_Handled;
	}

	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		ToggleFlashlight(client);
	}

	return Plugin_Handled;
}

void ToggleFlashlight(int client)
{
	SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") ^ 4);
	ClientCommand(client, "play items/flashlight1.wav");
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}