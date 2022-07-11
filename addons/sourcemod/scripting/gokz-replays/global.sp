static char sGlobalModes[][] = 
{
	"kz_vanilla",
	"kz_simple",
	"kz_timer"
};

static bool bDownloadingModes[3];



// ======[ PUBLIC ]======

void OnMapStart_GlobalReplay()
{
	// 等其他请求发送完再去下载回放，不然可能会触发429(send too many request)错误
	CreateTimer(5.0, Timer_StartDownloadGlobalReplay);
}

static Action Timer_StartDownloadGlobalReplay(Handle timer)
{
	/* bool asd[3];
	bDownloadingModes = asd; */

	// 和👆等效
	for (int i = 0; i < sizeof(bDownloadingModes); i++)
	{
		bDownloadingModes[i] = false;
	}

	// 不能用modelist列表获取, 因为response长度太短
	for (int i = 0; i < sizeof(sGlobalModes); i++)
	{
		// 主动加延时, 不然可能会触发429(send too many request)错误
		CreateTimer(i * 1.5, Timer_GetRecordsTop_Nub, i);
		CreateTimer(i * 3.0, Timer_GetRecordsTop_Pro, i);
	}

	return Plugin_Handled;
}

static Action Timer_GetRecordsTop_Nub(Handle timer, int mode)
{
	// get NUB record
	GetGlobalRecordsTop(gC_CurrentMap, mode, 0);

	return Plugin_Handled;
}

static Action Timer_GetRecordsTop_Pro(Handle timer, int mode)
{
	// get PRO record
	GetGlobalRecordsTop(gC_CurrentMap, mode, 1);

	return Plugin_Handled;
}

void GOKZ_GL_OnNewTopTime_Recording(int course, int mode, int timeType, float runTime)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath),
	 		"%s/%s/%d_%s_NRM_%s_GB.%s",
	 		RP_DIRECTORY_RUNS, gC_CurrentMap, course, gC_ModeNamesShort[mode], gC_TimeTypeNames[timeType], RP_FILE_EXTENSION);

	if (!FileExists(sPath))
	{
		return;
	}

	float replayTime = GetReplayTimeByHeader(sPath);

	if (replayTime != -1.0 && runTime < replayTime)
	{
		char sOldPath[PLATFORM_MAX_PATH];
		strcopy(sOldPath, sizeof(sOldPath), sPath);
		ReplaceString(sOldPath, sizeof(sOldPath), "_GB", "");

		// copy file
		DeleteFile(sPath);
		File_Copy(sOldPath, sPath);
	}
}

bool IsDownloadingGlobalReplay(int mode)
{
	return bDownloadingModes[mode];
}



// ======[ PRIVATE ]======

static void GetGlobalRecordsTop(const char[] map, int mode, int type)
{
	static char sRecordsAPI[] = "https://kztimerglobal.com/api/v2.0/records/top";

	HTTPRequest records = new HTTPRequest(sRecordsAPI);
	records.AppendQueryParam("map_name", map);
	records.AppendQueryParam("modes_list_string", sGlobalModes[mode]);
	records.AppendQueryParam("has_teleports", "%s", (type == 0) ? "true" : "false");

	DataPack dp = new DataPack();
	dp.WriteCell(mode);
	dp.WriteCell(type);
	records.Get(GetGlobalRecordsTop_Callback, dp);
}

public void GetGlobalRecordsTop_Callback(HTTPResponse response, DataPack dp, const char[] error)
{
	if (response.Status != HTTPStatus_OK)
	{
		delete dp;
		LogError("GetRecordsTop failed! error: %s, status: %d", error, response.Status);
		return;
	}

	dp.Reset();

	int mode = dp.ReadCell();
	int type = dp.ReadCell();

	delete dp;

	JSONArray top = view_as<JSONArray>(response.Data);

	int replayID = 0;
	bool haveReplay[GOKZ_MAX_COURSES];

	for (int i = 0; i < top.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(top.Get(i));

		int course = record.GetInt("stage");

		if (haveReplay[course])
		{
			continue;
		}
		else if ((replayID = record.GetInt("replay_id")) != 0)
		{
			haveReplay[course] = true;

			DataPack cache = new DataPack();
			cache.WriteCell(replayID);
			cache.WriteCell(course);
			cache.WriteCell(mode);
			cache.WriteCell(type);

			CreateTimer(i * 1.0, Timer_GetGlobalReplayByReplayID, cache);
		}

		delete record;
	}

	delete top;
}

static Action Timer_GetGlobalReplayByReplayID(Handle timer, DataPack dp)
{
	dp.Reset();
	int replayID = dp.ReadCell();
	int course = dp.ReadCell();
	int mode = dp.ReadCell();
	int type = dp.ReadCell();

	delete dp;

	GetGlobalReplayByReplayID(replayID, course, mode, type);

	char sTrack[16];
	if (course == 0)
	{
		FormatEx(sTrack, sizeof(sTrack), "主线");
	}
	else
	{
		FormatEx(sTrack, sizeof(sTrack), "奖励 %d", course);
	}

	GOKZ_PrintToChatAll(true, "{default}正在下载录像中: 赛道: %s | 模式: %s | 类型: %s", 
		sTrack,
		gC_ModeNamesShort[mode],
		type == 0 ? "存点" : "裸跳");

	return Plugin_Handled;
}

static void GetGlobalReplayByReplayID(int replayID, int course, int mode, int type)
{
	bDownloadingModes[mode] = true;

	char sReplayAPI[256];
	FormatEx(sReplayAPI, sizeof(sReplayAPI), "%s/%d", 
		"https://kztimerglobal.com/api/v2.0/records/replay", replayID);
	HTTPRequest replay = new HTTPRequest(sReplayAPI);

	DataPack dp = new DataPack();
	dp.WriteCell(course);
	dp.WriteCell(mode);
	dp.WriteCell(type);

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath),
	 		"%s/%s/%d_%s_NRM_%s_GB.%s",
	 		RP_DIRECTORY_RUNS, gC_CurrentMap, course, gC_ModeNamesShort[mode], gC_TimeTypeNames[type], RP_FILE_EXTENSION);

	replay.Timeout = 3600; // 1 hours for download, because too slow...
	replay.DownloadFile(sPath, DownloadGlobalReplay_Callback, dp);
}

public void DownloadGlobalReplay_Callback(HTTPStatus status, DataPack dp, const char[] error)
{
	if (status != HTTPStatus_OK)
	{
		delete dp;
		LogError("download replay failed! error: %s, status: %d", error, status);
		return;
	}

	dp.Reset();

	int course = dp.ReadCell();
	int mode = dp.ReadCell();
	int type = dp.ReadCell();

	delete dp;

	AddToReplayInfoCache(course, mode, 0, type, 1);

	bDownloadingModes[mode] = false;

	char sTrack[16];
	if (course == 0)
	{
		FormatEx(sTrack, sizeof(sTrack), "主线");
	}
	else
	{
		FormatEx(sTrack, sizeof(sTrack), "奖励 %d", course);
	}

	GOKZ_PrintToChatAll(true, "{green}全球录像已下载成功 >> 赛道: %s | 模式: %s | 类型: %s", 
		sTrack,
		gC_ModeNamesShort[mode],
		type == 0 ? "存点" : "裸跳");
}

static float GetReplayTimeByHeader(const char[] path)
{
	static float invalid = -1.0;

	File file = OpenFile(path, "rb");
	if (file == null)
	{
		return invalid;
	}

	// Check magic number in header
	int magicNumber;
	file.ReadInt32(magicNumber);
	if (magicNumber != RP_MAGIC_NUMBER)
	{
		delete file;
		return invalid;
	}

	// Check replay format version
	int formatVersion;
	file.ReadInt8(formatVersion);

	int length;

	// Replay type
	int replayType;
	file.ReadInt8(replayType);

	// GOKZ version
	file.ReadInt8(length);
	char[] gokzVersion = new char[length + 1];
	file.ReadString(gokzVersion, length, length);
	gokzVersion[length] = '\0';
	
	// Map name 
	file.ReadInt8(length);
	char[] mapName = new char[length + 1];
	file.ReadString(mapName, length, length);
	mapName[length] = '\0';
	if (!StrEqual(mapName, gC_CurrentMap))
	{
		delete file;
		return invalid;
	}

	// Map filesize
	int mapFileSize;
	file.ReadInt32(mapFileSize);

	// Server IP
	int serverIP;
	file.ReadInt32(serverIP);

	// Timestamp
	int timestamp;
	file.ReadInt32(timestamp);

	// Player Alias
	file.ReadInt8(length);

	static char botAlias[MAX_NAME_LENGTH];
	file.ReadString(botAlias, sizeof(botAlias), length);
	botAlias[length] = '\0';

	// Player Steam ID
	int steamID;
	file.ReadInt32(steamID);

	// Mode
	int mode;
	file.ReadInt8(mode);

	// Style
	int style;
	file.ReadInt8(style);

	// Player Sensitivity
	int intPlayerSensitivity;
	file.ReadInt32(intPlayerSensitivity);

	// Player MYAW
	int intPlayerMYaw;
	file.ReadInt32(intPlayerMYaw);

	// Tickrate
	int tickrateAsInt;
	file.ReadInt32(tickrateAsInt);
	float tickrate = view_as<float>(tickrateAsInt);
	if (tickrate != RoundToZero(1 / GetTickInterval()))
	{
		delete file;
		return invalid;
	}

	// Tick Count
	int tickCount;
	file.ReadInt32(tickCount);

	// The replay has no replay data, this shouldn't happen normally,
	// but this would cause issues in other code, so we don't even try to load this.
	if (tickCount == 0)
	{
		delete file;
		return invalid;
	}

	// Equipped Weapon
	int weapon;
	file.ReadInt32(weapon);

	// Equipped Knife
	int knife;
	file.ReadInt32(knife);

	// Time
	float time;
	file.ReadInt32(view_as<int>(time));

	delete file;

	return time;
}

static bool File_Copy(const char[] source, const char[] destination)
{
	File file_source = OpenFile(source, "rb");

	if (file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "wb");

	if (file_destination == null)
	{
		delete file_source;

		return false;
	}

	int[] buffer = new int[32];
	int cache = 0;

	while (!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);

		file_destination.Write(buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}
