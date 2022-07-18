/*
	Cached info about the map's available replay bots stored in an ArrayList.
*/



// =====[ PUBLIC ]=====

// Adds a replay to the cache
void AddToReplayInfoCache(int course, int mode, int style, int timeType, bool global = false)
{
	char path[PLATFORM_MAX_PATH];
	// We want to find files that look like "0_KZT_NRM_PRO.rec" or "0_KZT_NRM_PRO.replay"
	BuildPath(Path_SM, path, sizeof(path), "%s/%s/%d_%s_NRM_%s%s.replay", RP_DIRECTORY_RUNS, gC_CurrentMap, 
		course, gC_ModeNamesShort[mode], gC_TimeTypeNames[timeType], global?"_GB":"");

	replay_playback_cache_t playback_cache;
	if (!AddPlaybackToCache(path, playback_cache))
	{
		return;
	}

	gA_PlaybackCache.PushArray(playback_cache, sizeof(replay_playback_cache_t));

	replay_info_cache_t info_cache;
	info_cache.course = course;
	info_cache.mode = mode;
	info_cache.style = style;
	info_cache.timeType = timeType;
	info_cache.global = global;

	gA_ReplayInfoCache.PushArray(info_cache, sizeof(replay_info_cache_t));
}

void RemoveReplayInfoFromCache(int course, int mode, int style, int timeType, bool global = false)
{
	for(int i = 0; i < gA_PlaybackCache.Length; i++)
	{
		replay_info_cache_t info_cache;
		gA_ReplayInfoCache.GetArray(i, info_cache, sizeof(replay_info_cache_t));

		if (info_cache.course == course &&
			info_cache.mode == mode &&
			info_cache.style == style &&
			info_cache.timeType == timeType &&
			info_cache.global == global)
		{
			gA_ReplayInfoCache.Erase(i);
			gA_PlaybackCache.Erase(i);
			return;
		}
	}
}



// =====[ EVENTS ]=====

void OnMapStart_ReplayCache()
{
	if (gA_ReplayInfoCache == null)
	{
		gA_ReplayInfoCache = new ArrayList(sizeof(replay_info_cache_t), 0);
	}
	else
	{
		gA_ReplayInfoCache.Clear();
	}

	if (gA_PlaybackCache == null)
	{
		gA_PlaybackCache = new ArrayList(sizeof(replay_playback_cache_t), 0);
	}
	else
	{
		gA_PlaybackCache.Clear();
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s", RP_DIRECTORY_RUNS, gC_CurrentMap);
	DirectoryListing dir = OpenDirectory(path);
	
	// We want to find files that look like "0_KZT_NRM_PRO.rec" or "0_KZT_NRM_PRO.replay"
	char file[PLATFORM_MAX_PATH];
	int course, mode, style, timeType;
	
	while (dir.GetNext(file, sizeof(file)))
	{
		// .rec or .replay
		if (StrContains(file, "re", false) == -1)
		{
			continue;
		}

		file[FindCharInString(file, '.', true)] = '\0';

		if (strlen(file) <= 1)
		{
			continue;
		}

		// Break down file name into pieces
		char pieces[5][16];
		if (ExplodeString(file, "_", pieces, sizeof(pieces), sizeof(pieces[])) < 3)
		{
			continue;
		}

		// Extract info from the pieces
		course = StringToInt(pieces[0]);
		mode = GetModeIDFromString(pieces[1]);
		style = GetStyleIDFromString(pieces[2]);
		timeType = GetTimeTypeIDFromString(pieces[3]);
		if (!GOKZ_IsValidCourse(course) || mode == -1 || style == -1 || timeType == -1 || StrEqual(pieces[4], "GB"))
		{
			continue;
		}

		// Add it to the cache
		AddToReplayInfoCache(course, mode, style, timeType);
	}
	
	delete dir;
}



// =====[ PRIVATE ]=====

static int GetModeIDFromString(const char[] mode)
{
	for (int modeID = 0; modeID < MODE_COUNT; modeID++)
	{
		if (StrEqual(mode, gC_ModeNamesShort[modeID], false))
		{
			return modeID;
		}
	}
	return -1;
}

static int GetStyleIDFromString(const char[] style)
{
	for (int styleID = 0; styleID < STYLE_COUNT; styleID++)
	{
		if (StrEqual(style, gC_StyleNamesShort[styleID], false))
		{
			return styleID;
		}
	}
	return -1;
}

static int GetTimeTypeIDFromString(const char[] timeType)
{
	for (int timeTypeID = 0; timeTypeID < TIMETYPE_COUNT; timeTypeID++)
	{
		if (StrEqual(timeType, gC_TimeTypeNames[timeTypeID], false))
		{
			return timeTypeID;
		}
	}
	return -1;
}

static bool AddPlaybackToCache(char[] path, replay_playback_cache_t cache)
{
	if (!FileExists(path))
	{
		// No Replay Found
		return false;
	}

	File file = OpenFile(path, "rb");

	// Check magic number in header
	int magicNumber;
	file.ReadInt32(magicNumber);
	if (magicNumber != RP_MAGIC_NUMBER)
	{
		LogError("Failed to load invalid replay file: \"%s\".", path);
		delete file;
		return false;
	}

	cache.header.general.magicNumber = magicNumber;

	// Check replay format version
	int formatVersion;
	file.ReadInt8(formatVersion);
	cache.header.general.formatVersion = formatVersion;

	switch(formatVersion)
	{
		case 2:
		{
			if (!AddFormatVersion2ReplayToCache(file, cache))
			{
				return false;
			}
		}

		default:
		{
			LogError("Failed to load replay file with unsupported format version: \"%s\".", path);
			delete file;
			return false;
		}
	}

	return true;
}

static bool AddFormatVersion2ReplayToCache(File file, replay_playback_cache_t cache)
{
	int length;

	// Replay type
	file.ReadInt8(cache.header.general.replayType);

	// GOKZ version
	file.ReadInt8(length);
	file.ReadString(cache.header.general.gokzVersion, length, length);
	cache.header.general.gokzVersion[length] = '\0';

	// Map name 
	file.ReadInt8(length);
	file.ReadString(cache.header.general.mapName, length, length);
	cache.header.general.mapName[length] = '\0';
	if (!StrEqual(cache.header.general.mapName, gC_CurrentMap))
	{
		// Wrong Map
		delete file;
#if DEBUG
		PrintToChatAll("Wrong Map");
#endif
		return false;
	}

	// Map filesize
	file.ReadInt32(cache.header.general.mapFileSize);

	// Server IP
	file.ReadInt32(cache.header.general.serverIP);

	// Timestamp
	file.ReadInt32(cache.header.general.timestamp);

	// Player Alias
	file.ReadInt8(length);
	file.ReadString(cache.header.general.playerAlias, sizeof(GeneralReplayHeader::playerAlias), length);
	cache.header.general.playerAlias[length] = '\0';

	// Player Steam ID
	file.ReadInt32(cache.header.general.playerSteamID);

	// Mode
	file.ReadInt8(cache.header.general.mode);

	// Style
	file.ReadInt8(cache.header.general.style);

	// Player Sensitivity
	file.ReadInt32(view_as<int>(cache.header.general.playerSensitivity));

	// Player MYAW
	file.ReadInt32(view_as<int>(cache.header.general.playerMYaw));

	// Tickrate
	file.ReadInt32(view_as<int>(cache.header.general.tickrate));

	// Tick Count
	file.ReadInt32(cache.header.general.tickCount);

	// The replay has no replay data, this shouldn't happen normally,
	// but this would cause issues in other code, so we don't even try to load this.
	if (cache.header.general.tickCount == 0)
	{
		delete file;
#if DEBUG
		PrintToChatAll("tickCount == 0");
#endif
		return false;
	}

	// Equipped Weapon
	file.ReadInt32(cache.header.general.equippedWeapon);
	
	// Equipped Knife
	file.ReadInt32(cache.header.general.equippedKnife);

	// Time
	file.ReadInt32(view_as<int>(cache.header.run.time));

	// Course
	file.ReadInt8(cache.header.run.course);

	// Teleports Used
	file.ReadInt32(cache.header.run.teleportsUsed);

	// Tick Data
	// Setup playback tick data array list
	if (cache.aFrames == null)
	{
		cache.aFrames = new ArrayList(sizeof(ReplayTickData));
	}
	else
	{
		cache.aFrames.Clear();
	}

	// Read tick data
	any tickDataArray[sizeof(ReplayTickData)];
	for (int i = 0; i < cache.header.general.tickCount; i++)
	{
		file.ReadInt32(tickDataArray[ReplayTickData::deltaFlags]);
		
		for (int index = 1; index < sizeof(tickDataArray); index++)
		{
			int currentFlag = (1 << index);
			if (tickDataArray[ReplayTickData::deltaFlags] & currentFlag)
			{
				file.ReadInt32(tickDataArray[index]);
			}
		}

		ReplayTickData tickData;
		TickDataFromArray(tickDataArray, tickData);
		// HACK: Jump replays don't record proper length sometimes. I don't know why.
		//		 This leads to oversized replays full of 0s at the end.
		// 		 So, we do this horrible check to dodge that issue.
		if (tickData.origin[0] == 0 && tickData.origin[1] == 0 && tickData.origin[2] == 0 && tickData.angles[0] == 0 && tickData.angles[1] == 0)
		{
			break;
		}

		cache.aFrames.PushArray(tickData);
	}

	delete file;

	return true;
}
