#include <sourcemod>
#include <dhooks>

#include <cstrike>
#include <sdkhooks>
#include <sdktools>

#include <movementapi>

#include <gokz/core>
#include <gokz/replays>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <gokz/global>
#include <gokz/localranks>
#include <gokz/hud>
#include <gokz/jumpstats>
#include <gokz/localdb>
#include <ripext>
#include <updater>

#pragma newdecls required
#pragma semicolon 1

#define DEBUG 0
//#define DEBUG2



public Plugin myinfo = 
{
	name = "GOKZ Replays", 
	author = "DanZay", 
	description = "Records runs to disk and allows playback using bots", 
	version = GOKZ_VERSION, 
	url = "https://bitbucket.org/kztimerglobalteam/gokz"
};

#define UPDATER_URL GOKZ_UPDATER_BASE_URL..."gokz-replays.txt"

bool gB_GOKZHUD;
bool gB_GOKZLocalDB;
char gC_CurrentMap[64];
int gI_CurrentMapFileSize;
bool gB_HideNameChange;
bool gB_NubRecordMissed[MAXPLAYERS + 1];
ArrayList gA_ReplayInfoCache;
ArrayList gA_PlaybackCache;
Address gA_BotDuckAddr;
int gI_BotDuckPatchRestore[40]; // Size of patched section in gamedata
int gI_BotDuckPatchLength;

DynamicDetour gH_DHooks_TeamFull;
DynamicDetour gH_MaintainBotQuota;

#include "gokz-replays/commands.sp"
#include "gokz-replays/nav.sp"
#include "gokz-replays/playback.sp"
#include "gokz-replays/recording.sp"
#include "gokz-replays/replay_cache.sp"
#include "gokz-replays/replay_menu.sp"
#include "gokz-replays/api.sp"
#include "gokz-replays/controls.sp"
#include "gokz-replays/global.sp"



// =====[ PLUGIN EVENTS ]=====

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNatives();
	RegPluginLibrary("gokz-replays");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("gokz-common.phrases");
	LoadTranslations("gokz-replays.phrases");
	
	CreateGlobalForwards();
	HookEvents();
	RegisterCommands();
}

public void OnAllPluginsLoaded()
{
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATER_URL);
	}
	gB_GOKZLocalDB = LibraryExists("gokz-localdb");
	gB_GOKZHUD = LibraryExists("gokz-hud");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATER_URL);
	}
	gB_GOKZLocalDB = gB_GOKZLocalDB || StrEqual(name, "gokz-localdb");
	gB_GOKZHUD = gB_GOKZHUD || StrEqual(name, "gokz-hud");
}

public void OnLibraryRemoved(const char[] name)
{
	gB_GOKZLocalDB = gB_GOKZLocalDB && !StrEqual(name, "gokz-localdb");
	gB_GOKZHUD = gB_GOKZHUD && !StrEqual(name, "gokz-hud");
}

public void OnPluginEnd()
{
	// Restore bot auto duck behavior.
	if (gA_BotDuckAddr == Address_Null)
	{
		return;
	}
	for (int i = 0; i < gI_BotDuckPatchLength; i++)
	{
		StoreToAddress(gA_BotDuckAddr + view_as<Address>(i), gI_BotDuckPatchRestore[i], NumberType_Int8);
	}
}

// =====[ OTHER EVENTS ]=====

public void OnMapStart()
{
	if (!UpdateCurrentMap()) // Dont do update if this forward been called more than 1 times
	{
		return;
	}

	OnMapStart_Nav();
	OnMapStart_Recording();
	OnMapStart_ReplayCache();
	OnMapStart_GlobalReplay();

	CreateTimer(5.0, Timer_CheckBots);
}

public void OnConfigsExecuted()
{
	FindConVar("mp_autoteambalance").BoolValue = false;
	FindConVar("mp_limitteams").IntValue = 0;
	// Stop the bots!
	FindConVar("bot_stop").BoolValue = true;
	FindConVar("bot_chatter").SetString("off");
	FindConVar("bot_zombie").BoolValue = true;
	FindConVar("bot_join_after_player").BoolValue = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Block trigger and door interaction for bots
	// Credit to shavit's simple bhop timer - https://github.com/shavitush/bhoptimer
	
	// trigger_once | trigger_multiple.. etc
	// func_door | func_door_rotating
	if (StrContains(classname, "trigger_") != -1 || StrContains(classname, "_door") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if (other >= 1 && other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
	// Name change supression
	// Credit to shavit's simple bhop timer - https://github.com/shavitush/bhoptimer
	if (!gB_HideNameChange)
	{
		return Plugin_Continue;
	}
	
	char msgName[24];
	Protobuf pbmsg = msg;
	pbmsg.ReadString("msg_name", msgName, sizeof(msgName));
	if (StrEqual(msgName, "#Cstrike_Name_Change"))
	{
		gB_HideNameChange = false;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public MRESReturn DHooks_OnTeamFull_Pre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	DHookSetReturn(hReturn, false);
	return MRES_Supercede;
}

// Stops bot_quota from doing anything.
public MRESReturn Detour_MaintainBotQuota(int pThis)
{
	return MRES_Supercede;
}

// =====[ CLIENT EVENTS ]=====

public void OnClientPutInServer(int client)
{
	OnClientPutInServer_Playback(client);
	OnClientPutInServer_Recording(client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	OnClientAuthorized_Recording(client);
}

public void OnClientDisconnect(int client)
{
	OnClientDisconnect_Playback(client);
	OnClientDisconnect_Recording(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsFakeClient(client))
	{
		return Plugin_Continue;
	}
	OnPlayerRunCmd_Playback(client, buttons);
	return Plugin_Changed;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	OnPlayerRunCmdPost_Recording(client, buttons, tickcount, vel, mouse);
	OnPlayerRunCmdPost_ReplayControls(client, cmdnum);
}

public Action GOKZ_OnTimerStart(int client, int course)
{
	Action action = GOKZ_OnTimerStart_Recording(client);
	if (action != Plugin_Continue)
	{
		return action;
	}
	
	return Plugin_Continue;
}

public void GOKZ_OnTimerStart_Post(int client, int course)
{
	gB_NubRecordMissed[client] = false;
	GOKZ_OnTimerStart_Post_Recording(client);
}

public void GOKZ_OnTimerEnd_Post(int client, int course, float time, int teleportsUsed)
{
	GOKZ_OnTimerEnd_Recording(client, course, time, teleportsUsed);
}

public void GOKZ_OnPause_Post(int client)
{
	GOKZ_OnPause_Recording(client);
}

public void GOKZ_OnResume_Post(int client)
{
	GOKZ_OnResume_Recording(client);
}

public void GOKZ_OnTimerStopped(int client)
{
	GOKZ_OnTimerStopped_Recording(client);
}

public void GOKZ_OnCountedTeleport_Post(int client)
{
	GOKZ_OnCountedTeleport_Recording(client);
}

public void GOKZ_LR_OnRecordMissed(int client, float recordTime, int course, int mode, int style, int recordType)
{
	if (recordType == RecordType_Nub)
	{
		gB_NubRecordMissed[client] = true;
	}
	GOKZ_LR_OnRecordMissed_Recording(client, recordType);
}

public void GOKZ_AC_OnPlayerSuspected(int client, ACReason reason)
{
	GOKZ_AC_OnPlayerSuspected_Recording(client, reason);
}

public void GOKZ_DB_OnJumpstatPB(int client, int jumptype, int mode, float distance, int block, int strafes, float sync, float pre, float max, int airtime)
{
	GOKZ_DB_OnJumpstatPB_Recording(client, jumptype, distance, block, strafes, sync, pre, max, airtime);
}

public void GOKZ_GL_OnNewTopTime(int client, int course, int mode, int timeType, int rank, int rankOverall, float runTime)
{
	GOKZ_GL_OnNewTopTime_Recording(course, mode, timeType, runTime);
}


// =====[ PRIVATE ]=====


static void HookEvents()
{
	HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);
	GameData gameData = new GameData("gokz-replays.games");

	gH_DHooks_TeamFull = DynamicDetour.FromConf(gameData, "CCSGameRules::TeamFull");
	if (gH_DHooks_TeamFull == INVALID_HANDLE)
	{
		SetFailState("Failed to find CCSGameRules::TeamFull function signature");
	}
	
	if (!gH_DHooks_TeamFull.Enable(Hook_Pre, DHooks_OnTeamFull_Pre))
	{
		SetFailState("Failed to enable detour on CCSGameRules::TeamFull");
	}


	// BotManager::MaintainBotQuota
	gH_MaintainBotQuota = DynamicDetour.FromConf(gameData, "BotManager::MaintainBotQuota");
	if (gH_MaintainBotQuota == INVALID_HANDLE)
	{
		SetFailState("Failed to find CCSGameRules::TeamFull function signature");
	}
	
	if (!gH_MaintainBotQuota.Enable(Hook_Pre, Detour_MaintainBotQuota))
	{
		SetFailState("Failed to enable detour on CCSGameRules::TeamFull");
	}


	// Remove bot auto duck behavior.
	gA_BotDuckAddr = gameData.GetAddress("BotDuck");
	gI_BotDuckPatchLength = gameData.GetOffset("BotDuckPatchLength");
	for (int i = 0; i < gI_BotDuckPatchLength; i++)
	{
		gI_BotDuckPatchRestore[i] = LoadFromAddress(gA_BotDuckAddr + view_as<Address>(i), NumberType_Int8);
		StoreToAddress(gA_BotDuckAddr + view_as<Address>(i), 0x90, NumberType_Int8);
	}
	delete gameData;
}

static bool UpdateCurrentMap()
{
	char sMap[64];
	GetCurrentMapDisplayName(sMap, sizeof(sMap));

	// if current map equals to `gC_CurrentMap`, dont update
	if (!strcmp(sMap, gC_CurrentMap))
	{
		return false;
	}

	strcopy(gC_CurrentMap, sizeof(gC_CurrentMap), sMap);
	gI_CurrentMapFileSize = GetCurrentMapFileSize();

	return true;
}



// =====[ PUBLIC ]=====

// NOTE: These serialisation functions were made because the internal data layout of enum structs can change.
void TickDataToArray(ReplayTickData tickData, any result[sizeof(ReplayTickData)])
{
	// NOTE: HAS to match ReplayTickData exactly!
	result[0]  = tickData.deltaFlags;
	result[1]  = tickData.deltaFlags2;
	result[2]  = tickData.vel[0];
	result[3]  = tickData.vel[1];
	result[4]  = tickData.vel[2];
	result[5]  = tickData.mouse[0];
	result[6]  = tickData.mouse[1];
	result[7]  = tickData.origin[0];
	result[8]  = tickData.origin[1];
	result[9]  = tickData.origin[2];
	result[10] = tickData.angles[0];
	result[11] = tickData.angles[1];
	result[12] = tickData.angles[2];
	result[13] = tickData.velocity[0];
	result[14] = tickData.velocity[1];
	result[15] = tickData.velocity[2];
	result[16] = tickData.flags;
	result[17] = tickData.packetsPerSecond;
	result[18] = tickData.laggedMovementValue;
	result[19] = tickData.buttonsForced;
}

void TickDataFromArray(any array[sizeof(ReplayTickData)], ReplayTickData result)
{
	// NOTE: HAS to match ReplayTickData exactly!
	result.deltaFlags          = array[0];
	result.deltaFlags2         = array[1];
	result.vel[0]              = array[2];
	result.vel[1]              = array[3];
	result.vel[2]              = array[4];
	result.mouse[0]            = array[5];
	result.mouse[1]            = array[6];
	result.origin[0]           = array[7];
	result.origin[1]           = array[8];
	result.origin[2]           = array[9];
	result.angles[0]           = array[10];
	result.angles[1]           = array[11];
	result.angles[2]           = array[12];
	result.velocity[0]         = array[13];
	result.velocity[1]         = array[14];
	result.velocity[2]         = array[15];
	result.flags               = array[16];
	result.packetsPerSecond    = array[17];
	result.laggedMovementValue = array[18];
	result.buttonsForced       = array[19];
}

static Action Timer_CheckBots(Handle timer)
{
	CheckPlayBackBots();

	return Plugin_Stop;
}