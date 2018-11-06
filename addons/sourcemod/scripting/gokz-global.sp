#include <sourcemod>

#include <sdktools>

#include <gokz>

#include <GlobalAPI-Core>
#include <gokz/core>
#include <gokz/anticheat>
#include <gokz/replays>
#include <gokz/global>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <gokz/localdb>
#include <gokz/localranks>

#include <gokz/kzplayer>

#pragma newdecls required
#pragma semicolon 1



public Plugin myinfo = 
{
	name = "GOKZ Global", 
	author = "DanZay", 
	description = "Provides centralised records and bans via GlobalAPI", 
	version = GOKZ_VERSION, 
	url = "https://bitbucket.org/kztimerglobalteam/gokz"
};

#define UPDATE_URL "http://updater.gokz.org/gokz-global.txt"

bool gB_GOKZLocalDB;

bool gB_APIKeyCheck;
bool gB_ModeCheck[MODE_COUNT];
char gC_CurrentMap[64];
char gC_CurrentMapPath[PLATFORM_MAX_PATH];
bool gB_InValidRun[MAXPLAYERS + 1];
bool gB_GloballyVerified[MAXPLAYERS + 1];

ConVar gCV_gokz_settings_enforcer;
ConVar gCV_EnforcedCVar[ENFORCEDCVAR_COUNT];

#include "gokz-global/api.sp"
#include "gokz-global/ban_player.sp"
#include "gokz-global/commands.sp"
#include "gokz-global/maptop_menu.sp"
#include "gokz-global/print_records.sp"
#include "gokz-global/send_time.sp"



// =====[ PLUGIN EVENTS ]=====

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNatives();
	RegPluginLibrary("gokz-global");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("gokz-common.phrases");
	LoadTranslations("gokz-global.phrases");
	
	CreateConVars();
	CreateGlobalForwards();
	RegisterCommands();
}

public void OnAllPluginsLoaded()
{
	gB_GOKZLocalDB = LibraryExists("gokz-localdb");
	
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
	gB_GOKZLocalDB = gB_GOKZLocalDB || StrEqual(name, "gokz-localdb");
}

public void OnLibraryRemoved(const char[] name)
{
	gB_GOKZLocalDB = gB_GOKZLocalDB && !StrEqual(name, "gokz-localdb");
}



// =====[ CLIENT EVENTS ]=====

public void OnClientPutInServer(int client)
{
	OnClientPutInServer_PrintRecords(client);
}

public void GlobalAPI_OnPlayer_Joined(int client, bool banned)
{
	gB_GloballyVerified[client] = !banned;
	
	if (banned && gB_GOKZLocalDB)
	{
		GOKZ_DB_SetCheater(client, true);
	}
}

public void GOKZ_OnTimerStart_Post(int client, int course)
{
	KZPlayer player = KZPlayer(client);
	int mode = player.mode;
	gB_InValidRun[client] = GlobalsEnabled(mode);
}

public void GOKZ_OnTimerEnd_Post(int client, int course, float time, int teleportsUsed)
{
	if (gB_GloballyVerified[client] && gB_InValidRun[client])
	{
		SendTime(client, course, time, teleportsUsed);
	}
}

public void GOKZ_GL_OnNewTopTime(int client, int course, int mode, int timeType, int rank, int rankOverall)
{
	AnnounceNewTopTime(client, course, mode, timeType, rank, rankOverall);
}

public void GOKZ_AC_OnPlayerSuspected(int client, ACReason reason, const char[] notes, const char[] stats)
{
	if (!gB_GloballyVerified[client])
	{
		return;
	}
	
	GlobalBanPlayer(client, reason, notes, stats);
	gB_GloballyVerified[client] = false;
}



// =====[ OTHER EVENTS ]=====

public void OnMapStart()
{
	LoadSounds();
}

public void OnConfigsExecuted()
{
	SetupAPI();
}

public void GlobalAPI_OnAPIKeyReloaded()
{
	GlobalAPI API;
	API.GetAuthStatus(OnAuthStatusCallback);
}

public void GOKZ_OnModeUnloaded(int mode)
{
	gB_ModeCheck[mode] = false;
}

public Action GOKZ_OnTimerNativeCalledExternally(Handle plugin)
{
	char pluginName[64];
	GetPluginInfo(plugin, PlInfo_Name, pluginName, sizeof(pluginName));
	LogMessage("gokz-core native called by \"%s\" was blocked.", pluginName);
	return Plugin_Stop;
}



// =====[ PUBLIC ]=====

bool GlobalsEnabled(int mode)
{
	return gB_APIKeyCheck && gCV_gokz_settings_enforcer.BoolValue && MapCheck() && gB_ModeCheck[mode];
}

bool MapCheck()
{
	return GlobalAPI_GetMapGlobalStatus()
	 && GlobalAPI_GetMapID() > 0
	 && GlobalAPI_GetMapFilesize() == FileSize(gC_CurrentMapPath);
}

void PrintGlobalCheckToChat(int client)
{
	GOKZ_PrintToChat(client, true, "%t", "Global Check Header");
	GOKZ_PrintToChat(client, false, "%t", "Global Check", 
		gB_APIKeyCheck ? "{green}✓" : "{darkred}X", 
		gCV_gokz_settings_enforcer.BoolValue ? "{green}✓" : "{darkred}X", 
		MapCheck() ? "{green}✓" : "{darkred}X", 
		gB_GloballyVerified[client] ? "{green}✓" : "{darkred}X");
	
	char modeCheck[256];
	FormatEx(modeCheck, sizeof(modeCheck), "{purple}%s %s", gC_ModeNames[0], gB_ModeCheck[0] ? "{green}✓" : "{darkred}X");
	for (int i = 1; i < MODE_COUNT; i++)
	{
		FormatEx(modeCheck, sizeof(modeCheck), "%s {grey}| {purple}%s %s", modeCheck, gC_ModeNames[i], gB_ModeCheck[i] ? "{green}✓" : "{darkred}X");
	}
	GOKZ_PrintToChat(client, false, "%s", modeCheck);
}

void InvalidateRun(int client)
{
	gB_InValidRun[client] = false;
}

void AnnounceNewTopTime(int client, int course, int mode, int timeType, int rank, int rankOverall)
{
	bool newRecord = false;
	
	if (timeType == TimeType_Nub && rankOverall != 0)
	{
		if (rankOverall == 1)
		{
			if (course == 0)
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Record (NUB)", client, gC_ModeNamesShort[mode]);
			}
			else
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Bonus Record (NUB)", client, course, gC_ModeNamesShort[mode]);
			}
			newRecord = true;
		}
		else
		{
			if (course == 0)
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Top Time (NUB)", client, rankOverall, gC_ModeNamesShort[mode]);
			}
			else
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Top Bonus Time (NUB)", client, rankOverall, course, gC_ModeNamesShort[mode]);
			}
		}
	}
	else if (timeType == TimeType_Pro)
	{
		if (rankOverall != 0)
		{
			if (rankOverall == 1)
			{
				if (course == 0)
				{
					GOKZ_PrintToChatAll(true, "%t", "New Global Record (NUB)", client, gC_ModeNamesShort[mode]);
				}
				else
				{
					GOKZ_PrintToChatAll(true, "%t", "New Global Bonus Record (NUB)", client, course, gC_ModeNamesShort[mode]);
				}
				newRecord = true;
			}
			else
			{
				if (course == 0)
				{
					GOKZ_PrintToChatAll(true, "%t", "New Global Top Time (NUB)", client, rankOverall, gC_ModeNamesShort[mode]);
				}
				else
				{
					GOKZ_PrintToChatAll(true, "%t", "New Global Top Bonus Time (NUB)", client, rankOverall, course, gC_ModeNamesShort[mode]);
				}
			}
		}
		
		if (rank == 1)
		{
			if (course == 0)
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Record (PRO)", client, gC_ModeNamesShort[mode]);
			}
			else
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Bonus Record (PRO)", client, course, gC_ModeNamesShort[mode]);
			}
			newRecord = true;
		}
		else
		{
			if (course == 0)
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Top Time (PRO)", client, rank, gC_ModeNamesShort[mode]);
			}
			else
			{
				GOKZ_PrintToChatAll(true, "%t", "New Global Top Bonus Time (PRO)", client, rank, course, gC_ModeNamesShort[mode]);
			}
		}
	}
	
	if (newRecord)
	{
		PlayBeatRecordSound();
	}
}

void PlayBeatRecordSound()
{
	EmitSoundToAll(GL_SOUND_NEW_RECORD);
}



// =====[ PRIVATE ]=====

static void CreateConVars()
{
	gCV_gokz_settings_enforcer = CreateConVar("gokz_settings_enforcer", "1", "Whether GOKZ enforces convars required for global records.", _, true, 0.0, true, 1.0);
	gCV_gokz_settings_enforcer.AddChangeHook(OnConVarChanged);
	
	for (int i = 0; i < ENFORCEDCVAR_COUNT; i++)
	{
		gCV_EnforcedCVar[i] = FindConVar(gC_EnforcedCVars[i]);
		gCV_EnforcedCVar[i].FloatValue = gF_EnforcedCVarValues[i];
		gCV_EnforcedCVar[i].AddChangeHook(OnEnforcedConVarChanged);
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == gCV_gokz_settings_enforcer && !gCV_gokz_settings_enforcer.BoolValue)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			InvalidateRun(i);
		}
	}
}

public void OnEnforcedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (gCV_gokz_settings_enforcer.BoolValue)
	{
		for (int i = 0; i < ENFORCEDCVAR_COUNT; i++)
		{
			if (convar == gCV_EnforcedCVar[i])
			{
				gCV_EnforcedCVar[i].FloatValue = gF_EnforcedCVarValues[i];
				return;
			}
		}
	}
}

static void SetupAPI()
{
	GlobalAPI API;
	API.GetMapName(gC_CurrentMap, sizeof(gC_CurrentMap));
	API.GetMapPath(gC_CurrentMapPath, sizeof(gC_CurrentMapPath));
	API.GetAuthStatus(OnAuthStatusCallback);
	API.GetModeInfo(GOKZ_GL_GetGlobalMode(Mode_Vanilla), OnModeInfoCallback, Mode_Vanilla);
	API.GetModeInfo(GOKZ_GL_GetGlobalMode(Mode_SimpleKZ), OnModeInfoCallback, Mode_SimpleKZ);
	API.GetModeInfo(GOKZ_GL_GetGlobalMode(Mode_KZTimer), OnModeInfoCallback, Mode_KZTimer);
}

public int OnAuthStatusCallback(bool failure, bool authenticated)
{
	if (failure)
	{
		LogError("Failed to check API key with Global API.");
		gB_APIKeyCheck = false;
	}
	else
	{
		if (!authenticated)
		{
			LogError("Global API key was found to be missing or invalid.");
		}
		gB_APIKeyCheck = authenticated;
	}
}

public int OnModeInfoCallback(bool failure, const char[] name, int latest_version, const char[] latest_version_description, int mode)
{
	if (failure)
	{
		LogError("Failed to check a mode version with Global API.");
	}
	else if (latest_version <= GOKZ_GetModeVersion(mode))
	{
		gB_ModeCheck[mode] = true;
	}
	else
	{
		gB_ModeCheck[mode] = false;
		LogError("Global API requires %s mode version %d (%s). You have version %d (%s).", 
			gC_ModeNames[mode], latest_version, latest_version_description, GOKZ_GetModeVersion(mode), GOKZ_VERSION);
	}
}

static void LoadSounds()
{
	char downloadPath[PLATFORM_MAX_PATH];
	FormatEx(downloadPath, sizeof(downloadPath), "sound/%s", GL_SOUND_NEW_RECORD);
	AddFileToDownloadsTable(downloadPath);
	PrecacheSound(GL_SOUND_NEW_RECORD, true);
} 