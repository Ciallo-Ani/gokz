#include <sourcemod>
#include <ripext>

#include <gokz/core>
#include <gokz/global>

#pragma newdecls required
#pragma semicolon 1

enum struct gpb_t
{
	bool bTP;
	int client;
	int target;
	int mode;
	int tps;
	int course;
	int points;
	float time;
	char sSteamid[32];
	char sMode[16];
	char sName[MAX_NAME_LENGTH];
	char sMap[160];
	char sRecordTime[32];
}

public Plugin myinfo =
{
	name = "GOKZ GPB",
	description = "",
	author = "",
	version = "",
	url = ""
};

bool gB_Querying[MAXPLAYERS+1];
char gS_Map[160];


public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	RegisterCommands();
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, sizeof(gS_Map));
	GetMapDisplayName(gS_Map, gS_Map, sizeof(gS_Map));
}

void RegisterCommands()
{
	RegConsoleCmd("sm_pb", Command_GlobalPB, "sm_pb <target> <map>");
	RegConsoleCmd("sm_gpb", Command_GlobalPB, "sm_gpb <target> <map>");
	RegConsoleCmd("sm_globalpb", Command_GlobalPB, "sm_globalpb <target> <map>");
	RegConsoleCmd("sm_gbpb", Command_GlobalBonusPB, "sm_gbpb <num> <target> <map>");
	RegConsoleCmd("sm_globalbonuspb", Command_GlobalBonusPB, "sm_globalbonuspb <num> <target> <map>");
}

public Action Command_GlobalPB(int client, int args)
{
	char map[160];
	strcopy(map, sizeof(map), gS_Map);

	char playerName[MAX_NAME_LENGTH];
	int target = client;

	if (args > 0)
	{
		GetCmdArg(1, playerName, sizeof(playerName));
		if ((target = FindTarget(client, playerName, true, false)) == -1)
		{
			// throws ReplyToTargetError
			// GOKZ_PrintToChat(client, true, "{grey}找不到玩家 '{default}%s{grey}'.", playerName);
			return Plugin_Handled;
		}

		if (args >= 2)
		{
			GetCmdArg(2, map, sizeof(map));
			if (FindMap(map, map, sizeof(map)) == FindMap_NotFound)
			{
				GOKZ_PrintToChat(client, true, "{grey}找不到地图 '{default}%s{grey}'.", map);
				return Plugin_Handled;
			}
		}
	}

	StartRequestGlobalPB(client, target, map, 0);

	return Plugin_Handled;
}

public Action Command_GlobalBonusPB(int client, int args)
{
	char map[160];
	strcopy(map, sizeof(map), gS_Map);

	char playerName[MAX_NAME_LENGTH];
	int target = client;
	int course = 1;

	if (args > 0)
	{
		char sInfo[4];
		GetCmdArg(1, sInfo, sizeof(sInfo));
		if ((course = StringToInt(sInfo)) <= 0)
		{
			GOKZ_PrintToChat(client, true, "{grey}不合法的 '{default}奖励关 #%d{grey}'!", course);
			return Plugin_Handled;
		}

		if (args ==2)
		{
			GetCmdArg(2, playerName, sizeof(playerName));
			if ((target = FindTarget(client, playerName, true, false)) == -1)
			{
				// throws ReplyToTargetError
				// GOKZ_PrintToChat(client, true, "{grey}找不到玩家 '{default}%s{grey}'.", playerName);
				return Plugin_Handled;
			}
		}
		else if (args == 3)
		{
			GetCmdArg(3, map, sizeof(map));
			if (FindMap(map, map, sizeof(map)) == FindMap_NotFound)
			{
				GOKZ_PrintToChat(client, true, "{grey}找不到地图 '{default}%s{grey}'.", map);
				return Plugin_Handled;
			}
		}
	}

	StartRequestGlobalPB(client, target, map, course);

	return Plugin_Handled;
}

void StartRequestGlobalPB(int client, int target, const char[] map, int course)
{
	if (gB_Querying[client])
	{
		GOKZ_PrintToChat(client, true, "{grey}请等待上一次的请求完成.");
		return;
	}

	gpb_t cache;

	cache.client = GetClientSerial(client);
	cache.target = GetClientSerial(target);

	if (!GetClientAuthId(target, AuthId_Steam2, cache.sSteamid, sizeof(gpb_t::sSteamid)))
	{
		return;
	}

	cache.mode = GOKZ_GetCoreOption(target, Option_Mode);
	if (!GOKZ_GL_GetModeString(cache.mode, cache.sMode, sizeof(gpb_t::sMode)))
	{
		return;
	}

	strcopy(cache.sMap, sizeof(gpb_t::sMap), map);
	GetClientName(target, cache.sName, sizeof(gpb_t::sName));
	cache.course = course;

	gB_Querying[client] = true;

	ArrayList aCacheTP = new ArrayList(sizeof(gpb_t), 1);
	cache.bTP = true;
	aCacheTP.SetArray(0, cache, sizeof(cache));
	CreateTimer(0.1, Timer_GetGlobalPB, CloneHandle(aCacheTP));
	delete aCacheTP;

	ArrayList aCachePRO = new ArrayList(sizeof(gpb_t), 1);
	cache.bTP = false;
	aCachePRO.SetArray(0, cache, sizeof(cache));
	CreateTimer(1.5, Timer_GetGlobalPB, CloneHandle(aCachePRO));
	delete aCachePRO;
}

static Action Timer_GetGlobalPB(Handle timer, ArrayList aCache)
{
	GetGlobalPB(aCache);

	return Plugin_Stop;
}

void GetGlobalPB(ArrayList aCache)
{
	gpb_t cache;
	aCache.GetArray(0, cache, sizeof(cache));

	static char url[] = "https://kztimerglobal.com/api/v2.0/records/top";

	HTTPRequest gpb = new HTTPRequest(url);
	gpb.AppendQueryParam("steam_id", cache.sSteamid);
	gpb.AppendQueryParam("map_name", cache.sMap);
	gpb.AppendQueryParam("stage", "%d", cache.course);
	gpb.AppendQueryParam("modes_list_string", cache.sMode);
	gpb.AppendQueryParam("limit", "1");
	gpb.AppendQueryParam("tickrate", "128");
	gpb.AppendQueryParam("has_teleports", cache.bTP ? "true" : "false");

	gpb.Get(OnGlobalPBRequest_Callback, aCache);
}

public void OnGlobalPBRequest_Callback(HTTPResponse response, ArrayList aCache, const char[] error)
{
	gpb_t cache;
	aCache.GetArray(0, cache, sizeof(cache));

	cache.client = GetClientFromSerial(cache.client);
	cache.target = GetClientFromSerial(cache.target);

	if (cache.client == 0)
	{
		delete aCache;
		return;
	}

	gB_Querying[cache.client] = false;

	if (response.Status != HTTPStatus_OK)
	{
		LogMessage("gokz-gpb::OnGlobalPBRequest_Callback 请求失败! 错误代码: %d, 错误信息: %s", response.Status, error);
		CreateTimer(1.5, Timer_GetGlobalPB, aCache);

		return;
	}

	delete aCache;

	JSONArray arr = view_as<JSONArray>(response.Data);

	if (arr.Length == 0)
	{
		cache.time = 0.0;
	}
	else
	{
		JSONObject gpb = view_as<JSONObject>(arr.Get(0));

		cache.tps = gpb.GetInt("teleports");
		cache.points = gpb.GetInt("points");
		cache.time = gpb.GetFloat("time");

		// 如果这个B突然离开了游戏
		if (cache.target == 0)
		{
			gpb.GetString("player_name", cache.sName, sizeof(gpb_t::sName));
		}

		gpb.GetString("updated_on", cache.sRecordTime, sizeof(gpb_t::sRecordTime));
		cache.sRecordTime[FindCharInString(cache.sRecordTime, 'T')] = ' '; // 去掉'T'

		delete gpb;
	}

	GPB_PrintToChat(cache);

	delete arr;
}

void GPB_PrintToChat(gpb_t cache)
{
	char sMessage[1024];

	if (cache.course == 0)
	{
		FormatEx(sMessage, sizeof(sMessage), "{green}%s | {gold}主线 >>", gC_ModeNamesShort[cache.mode]);
	}
	else
	{
		FormatEx(sMessage, sizeof(sMessage), "{green}%s | {blue}Bonus %d >>", gC_ModeNamesShort[cache.mode], cache.course);
	}

	// 裸跳
	if (!cache.bTP)
	{
		if (cache.time > 0.0)
		{
			Format(sMessage, sizeof(sMessage), "%s \x03个人全球裸跳记录: \x01%s | \x03%d分 \x01| {grey}%s", sMessage, 
				GOKZ_FormatTime(cache.time), cache.points, cache.sRecordTime);
		}
		else
		{
			Format(sMessage, sizeof(sMessage), "%s \x03个人全球裸跳记录: \x01尚无", sMessage);
		}
	}
	else
	{
		if (cache.time > 0.0)
		{
			Format(sMessage, sizeof(sMessage), "%s \x06个人全球读点记录: \x01%s (TP\x06%d次\x01) | \x06%d分 \x01| {grey}%s", sMessage, 
				GOKZ_FormatTime(cache.time), cache.tps, cache.points, cache.sRecordTime);
		}
		else
		{
			Format(sMessage, sizeof(sMessage), "%s \x06个人全球读点记录: \x01尚无", sMessage);
		}
	}

	if (cache.target != cache.client)
	{
		char sOther[256];
		FormatEx(sOther, sizeof(sOther), "%s的个人", cache.sName);
		ReplaceString(sMessage, sizeof(sMessage), "个人", sOther);
	}

	GOKZ_PrintToChat(cache.client, false, sMessage);
}