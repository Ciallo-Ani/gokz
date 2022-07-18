/*
	Bot replay playback logic and processes.
	
	The recorded files are read and their information and tick data
	stored into variables. A bot is then used to playback the recorded
	data by setting it's origin, velocity, etc. in OnPlayerRunCmd.
*/



static int preAndPostRunTickCount;

static int playbackTick[RP_MAX_BOTS];
static ArrayList playbackTickData[RP_MAX_BOTS];
static bool inBreather[RP_MAX_BOTS];
static float breatherStartTime[RP_MAX_BOTS];

// Original bot caller, needed for OnClientPutInServer callback
static int botCaller[RP_MAX_BOTS];
static bool botInUsed[RP_MAX_BOTS];
static int botClient[RP_MAX_BOTS];
static bool botDataLoaded[RP_MAX_BOTS];
static int botReplayType[RP_MAX_BOTS];
static int botCourse[RP_MAX_BOTS];
static int botMode[RP_MAX_BOTS];
static int botStyle[RP_MAX_BOTS];
static float botTime[RP_MAX_BOTS];
static int botTimeTicks[RP_MAX_BOTS];
static char botAlias[RP_MAX_BOTS][MAX_NAME_LENGTH];
static bool botPaused[RP_MAX_BOTS];
static bool botPlaybackPaused[RP_MAX_BOTS];
static int botKnife[RP_MAX_BOTS];
static int botWeapon[RP_MAX_BOTS];
static int botJumpType[RP_MAX_BOTS];
static float botJumpDistance[RP_MAX_BOTS];
static int botJumpBlockDistance[RP_MAX_BOTS];

static int botTeleportsUsed[RP_MAX_BOTS];
static int botCurrentTeleport[RP_MAX_BOTS];
static int botButtons[RP_MAX_BOTS];
static float botTakeoffSpeed[RP_MAX_BOTS];
static float botSpeed[RP_MAX_BOTS];
static bool hitBhop[RP_MAX_BOTS];
static bool hitPerf[RP_MAX_BOTS];
static bool botJumped[RP_MAX_BOTS];
static bool botIsTakeoff[RP_MAX_BOTS];



// =====[ EVENTS ]=====

void OnMapStart_PlayBack()
{
	ServerCommand("bot_kick");
	RequestFrame(Frame_CreateUnusedBot);
}

void Frame_CreateUnusedBot()
{
	int mid = RP_MAX_BOTS / 2;

	for(int i = 0; i < RP_MAX_BOTS; i++)
	{
		botClient[i] = GOKZ_CreateBot(i < mid ? CS_TEAM_CT : CS_TEAM_T);
		ResetBotNameAndTag(i);
	}
}

// =====[ PUBLIC ]=====

// Returns the client index of the replay bot, or -1 otherwise
int LoadReplayBot(int client, replay_playback_cache_t cache)
{
	int bot;
	if ((bot = GetUnusedBot(client)) != -1)
	{
		if (IsValidClient(botClient[bot]))
		{
			botCaller[bot] = client;
			RequestFrame(Frame_SetBotStuff, bot);
			if (IsValidClient(botCaller[bot]))
			{
				CreateTimer(0.2, Timer_SpectateMyBot, bot, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		else
		{
			return -1;
		}
	}
	else
	{
		GOKZ_PrintToChat(client, true, "%t", "No Bots Available");
		GOKZ_PlayErrorSound(client);
		return -1;
	}
	
	if (bot == -1)
	{
		LogError("Unused bot could not be found even though only %d out of %d are known to be in use.", 
				 GetBotsInUse(), RP_MAX_BOTS);
		GOKZ_PlayErrorSound(client);
		return -1;
	}

	if (!LoadPlayback(client, bot, cache))
	{
		GOKZ_PlayErrorSound(client);
		return -1;
	}

	return botClient[bot];
}

// Passes the current state of the replay into the HUDInfo struct
void GetPlaybackState(int client, HUDInfo info)
{
	int bot, i;
	for(i = 0; i < RP_MAX_BOTS; i++)
	{
		bot = botClient[i] == client ? i : bot;
	}
	if (i == RP_MAX_BOTS + 1) return;
	
	if (playbackTickData[bot] == INVALID_HANDLE)
	{
		return;
	}
	
	info.TimerRunning = botReplayType[bot] == ReplayType_Jump ? false : true;

	if (playbackTick[bot] < preAndPostRunTickCount)
	{
		info.Time = 0.0;
	}
	else if (playbackTick[bot] >= playbackTickData[bot].Length - preAndPostRunTickCount)
	{
		info.Time = botTime[bot];
	}
	else if (playbackTick[bot] >= preAndPostRunTickCount)
	{
		info.Time = (playbackTick[bot] - preAndPostRunTickCount) * GetTickInterval();
	}

	info.TimeType = botTeleportsUsed[bot] > 0 ? TimeType_Nub : TimeType_Pro;
	info.Speed = botSpeed[bot];
	info.Paused = false;
	info.OnLadder = false;
	info.Noclipping = false;
	info.OnGround = Movement_GetOnGround(client);
	info.Ducking = botButtons[bot] & IN_DUCK > 0;
	info.ID = botClient[bot];
	info.Jumped = botJumped[bot];
	info.HitBhop = hitBhop[bot];
	info.HitPerf = hitPerf[bot];
	info.Buttons = botButtons[bot];
	info.TakeoffSpeed = botTakeoffSpeed[bot];
	info.IsTakeoff = botIsTakeoff[bot] && !Movement_GetOnGround(client);
	info.CurrentTeleport = botCurrentTeleport[bot];
}

int GetBotFromClient(int client)
{
	for (int bot = 0; bot < RP_MAX_BOTS; bot++)
	{
		if (botClient[bot] == client)
		{
			return bot;
		}
	}
	return -1;
}

bool InBreather(int bot)
{
	return inBreather[bot];
}

bool PlaybackPaused(int bot)
{
	return botPlaybackPaused[bot];
}

void PlaybackTogglePause(int bot)
{
	if(botPlaybackPaused[bot])
	{
		botPlaybackPaused[bot] = false;
	}
	else
	{
		botPlaybackPaused[bot] = true;
	}
}

void PlaybackSkipForward(int bot)
{
	if (playbackTick[bot] + RoundToZero(RP_SKIP_TIME / GetTickInterval()) < playbackTickData[bot].Length)
	{
		PlaybackSkipToTick(bot, playbackTick[bot] + RoundToZero(RP_SKIP_TIME / GetTickInterval()));
	}
}

void PlaybackSkipBack(int bot)
{
	if (playbackTick[bot] < RoundToZero(RP_SKIP_TIME / GetTickInterval()))
	{
		PlaybackSkipToTick(bot, 0);
	}
	else
	{
		PlaybackSkipToTick(bot, playbackTick[bot] - RoundToZero(RP_SKIP_TIME / GetTickInterval()));
	}
}

int PlaybackGetTeleports(int bot)
{
	return botCurrentTeleport[bot];
}

void TrySkipToTime(int client, int seconds)
{
	if (!IsValidClient(client))
	{
		return;
	}
	
	int tick = seconds * 128;
	int bot = GetBotFromClient(GetObserverTarget(client));
	
	if (tick >= 0 && tick < playbackTickData[bot].Length)
	{
		PlaybackSkipToTick(bot, tick);
	}
	else
	{
		GOKZ_PrintToChat(client, true, "%t", "Replay Controls - Invalid Time");
	}
}

float GetPlaybackTime(int bot)
{
	if (playbackTick[bot] < preAndPostRunTickCount)
	{
		return 0.0;
	}
	if (playbackTick[bot] >= playbackTickData[bot].Length - (preAndPostRunTickCount * 2))
	{
		return botTime[bot];
	}
	if (playbackTick[bot] >= preAndPostRunTickCount)
	{
		return (playbackTick[bot] - preAndPostRunTickCount) * GetTickInterval();
	}

	return 0.0;
}



// =====[ EVENTS ]=====

void OnClientPutInServer_Playback(int client)
{
	if (!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return;
	}
}

void OnPlayerRunCmd_Playback(int client, int &buttons)
{
	if (!IsFakeClient(client))
	{
		return;
	}
	
	for (int bot; bot < RP_MAX_BOTS; bot++)
	{
		// Check if not the bot we're looking for
		if (!botInUsed[bot] || botClient[bot] != client || !botDataLoaded[bot] || 
			playbackTickData[bot] == null || playbackTickData[bot].Length < 1)
		{
			continue;
		}

		PlaybackVersion2(client, bot, buttons);
	}
}



// =====[ PRIVATE ]=====

static void Frame_SetBotStuff(int bot)
{
	SetBotStuff(bot);
}

static Action Timer_SpectateMyBot(Handle timer, int bot)
{
	MakePlayerSpectate(botCaller[bot], botClient[bot]);

	return Plugin_Stop;
}

// Returns false if there was a problem loading the playback e.g. doesn't exist
static bool LoadPlayback(int client, int bot, replay_playback_cache_t cache)
{
	// Check magic number in header
	if (cache.header.general.magicNumber != RP_MAGIC_NUMBER)
	{
		LogError("invalid magicNumber: \"%d\".", cache.header.general.magicNumber);
		return false;
	}

	// Check replay format version
	switch(cache.header.general.formatVersion)
	{
		case 2:
		{
			if (!LoadFormatVersion2Replay(client, bot, cache))
			{
				return false;
			}
		}

		default:
		{
			LogError("Failed to load replay file with unsupported format version: \"%d\".", cache.header.general.formatVersion);
			return false;
		}
	}

	return true;
}

static bool LoadFormatVersion2Replay(int client, int bot, replay_playback_cache_t cache)
{
	// Replay type
	int replayType = cache.header.general.replayType;

	// GOKZ version
	char gokzVersion[32];
	strcopy(gokzVersion, sizeof(gokzVersion), cache.header.general.gokzVersion);

	// Map name 
	char mapName[64];
	strcopy(mapName, sizeof(mapName), cache.header.general.mapName);

	// Map filesize
	int mapFileSize = cache.header.general.mapFileSize;

	// Server IP
	int serverIP = cache.header.general.serverIP;

	// Timestamp
	int timestamp = cache.header.general.timestamp;

	// Player Alias
	strcopy(botAlias[bot], sizeof(botAlias[]), cache.header.general.playerAlias)

	// Player Steam ID
	int steamID = cache.header.general.playerSteamID;

	// Mode
	botMode[bot] = cache.header.general.mode;

	// Style
	botStyle[bot] = cache.header.general.style;

	// Player Sensitivity
	float playerSensitivity = cache.header.general.playerSensitivity;

	// Player MYAW
	float playerMYaw = cache.header.general.playerMYaw;

	// Tickrate
	float tickrate = cache.header.general.tickrate;

	// Tick Count
	int tickCount = cache.header.general.tickCount;

	// Equipped Weapon
	botWeapon[bot] = cache.header.general.equippedWeapon;

	// Equipped Knife
	botKnife[bot] = cache.header.general.equippedKnife;

	// Big spit to console
	PrintToConsole(client, "Replay Type: %d\nGOKZ Version: %s\nMap Name: %s\nMap Filesize: %d\nServer IP: %d\nTimestamp: %d\nPlayer Alias: %s\nPlayer Steam ID: %d\nMode: %d\nStyle: %d\nPlayer Sensitivity: %f\nPlayer m_yaw: %f\nTickrate: %f\nTick Count: %d\nWeapon: %d\nKnife: %d", replayType, gokzVersion, mapName, mapFileSize, serverIP, timestamp, botAlias[bot], steamID, botMode[bot], botStyle[bot], playerSensitivity, playerMYaw, tickrate, tickCount, botWeapon[bot], botKnife[bot]);

	switch(cache.header.general.replayType)
	{
		case ReplayType_Run:
		{
			// Time
			botTime[bot] = cache.header.run.time;
			botTimeTicks[bot] = RoundToNearest(botTime[bot] * tickrate);

			// Course
			botCourse[bot] = cache.header.run.course;

			// Teleports Used
			botTeleportsUsed[bot] = cache.header.run.teleportsUsed;

			// Type
			botReplayType[bot] = ReplayType_Run;

			// Finish spit to console
			PrintToConsole(client, "Time: %f\nCourse: %d\nTeleports Used: %d", botTime[bot], botCourse[bot], botTeleportsUsed[bot]);
		}

		default:
		{
			return false;
		}
	}

	delete playbackTickData[bot];

#if DEBUG
	if (cache.aFrames == null)
	{
		GOKZ_PrintToChat(client, true, "aFrame is null");
		return false;
	}

	if (cache.aFrames.Length < 1)
	{
		GOKZ_PrintToChat(client, true, "aFrame Length is < 1");
		return false;
	}
#endif

	preAndPostRunTickCount = RoundToZero(RP_PLAYBACK_BREATHER_TIME / GetTickInterval());
	playbackTickData[bot] = view_as<ArrayList>(CloneHandle(cache.aFrames));
	playbackTick[bot] = 0;
	botDataLoaded[bot] = true;

	return true;
}

void PlaybackVersion2(int client, int bot, int &buttons)
{
	int size = playbackTickData[bot].Length;
	ReplayTickData prevTickData;
	ReplayTickData currentTickData;
	
	// If first or last frame of the playback
	if (playbackTick[bot] == 0 || playbackTick[bot] == (size - 1))
	{
		// Move the bot and pause them at that tick
		playbackTickData[bot].GetArray(playbackTick[bot], currentTickData);
		playbackTickData[bot].GetArray(IntMax(playbackTick[bot] - 1, 0), prevTickData);
		TeleportEntity(client, currentTickData.origin, currentTickData.angles, view_as<float>( { 0.0, 0.0, 0.0 } ));
		
		if (!inBreather[bot])
		{
			// Start the breather period
			inBreather[bot] = true;
			breatherStartTime[bot] = GetEngineTime();
		}
		else if (GetEngineTime() > breatherStartTime[bot] + RP_PLAYBACK_BREATHER_TIME)
		{
			// End the breather period
			inBreather[bot] = false;
			botPlaybackPaused[bot] = false;

			// Start the bot if first tick. Clear bot if last tick.
			playbackTick[bot]++;
			if (playbackTick[bot] == size)
			{
				StopPlayBack(bot);
			}
		}
	}
	else
	{
		// Check whether somebody is actually spectating the bot
		int spec;
		for (spec = 1; spec < MAXPLAYERS + 1; spec++)
		{
			if (IsValidClient(spec) && GetObserverTarget(spec) == botClient[bot])
			{
				break;
			}
		}
		if (spec == MAXPLAYERS + 1 && !IsReplayBotControlled(bot, botClient[bot]))
		{
			StopPlayBack(bot);
			return;
		}
		
		// Load in the next tick
		playbackTickData[bot].GetArray(playbackTick[bot], currentTickData);
		playbackTickData[bot].GetArray(IntMax(playbackTick[bot] - 1, 0), prevTickData);
		
		// Check if the replay is paused
		if (botPlaybackPaused[bot])
		{
			TeleportEntity(client, currentTickData.origin, currentTickData.angles, view_as<float>( { 0.0, 0.0, 0.0 } ));
			return;
		}

		// Play timer start/end sound, if necessary. Reset teleports
		if (playbackTick[bot] == preAndPostRunTickCount && botReplayType[bot] == ReplayType_Run)
		{
			EmitSoundToClientSpectators(client, gC_ModeStartSounds[GOKZ_GetCoreOption(client, Option_Mode)]);
			botCurrentTeleport[bot] = 0;
		}
		if (playbackTick[bot] == botTimeTicks[bot] + preAndPostRunTickCount && botReplayType[bot] == ReplayType_Run)
		{
			EmitSoundToClientSpectators(client, gC_ModeEndSounds[GOKZ_GetCoreOption(client, Option_Mode)]);
		}

		// Set velocity to travel from current origin to recorded origin
		float currentOrigin[3], velocity[3];
		Movement_GetOrigin(client, currentOrigin);
		MakeVectorFromPoints(currentOrigin, currentTickData.origin, velocity);
		ScaleVector(velocity, 1.0 / GetTickInterval());
		TeleportEntity(client, NULL_VECTOR, currentTickData.angles, velocity);
		
		botSpeed[bot] = GetVectorHorizontalLength(currentTickData.velocity);

		// Set buttons
		int newButtons;
		if (currentTickData.flags & RP_IN_ATTACK)
		{
			newButtons |= IN_ATTACK;
		}
		if (currentTickData.flags & RP_IN_ATTACK2)
		{
			newButtons |= IN_ATTACK2;
		}
		if (currentTickData.flags & RP_IN_JUMP)
		{
			newButtons |= IN_JUMP;
		}
		if (currentTickData.flags & RP_IN_DUCK || currentTickData.flags & RP_FL_DUCKING)
		{
			newButtons |= IN_DUCK;
		}
		if (currentTickData.flags & RP_IN_FORWARD)
		{
			newButtons |= IN_FORWARD;
		}
		if (currentTickData.flags & RP_IN_BACK)
		{
			newButtons |= IN_BACK;
		}
		if (currentTickData.flags & RP_IN_LEFT)
		{
			newButtons |= IN_LEFT;
		}
		if (currentTickData.flags & RP_IN_RIGHT)
		{
			newButtons |= IN_RIGHT;
		}
		if (currentTickData.flags & RP_IN_MOVELEFT)
		{
			newButtons |= IN_MOVELEFT;
		}
		if (currentTickData.flags & RP_IN_MOVERIGHT)
		{
			newButtons |= IN_MOVERIGHT;
		}
		if (currentTickData.flags & RP_IN_RELOAD)
		{
			newButtons |= IN_RELOAD;
		}
		if (currentTickData.flags & RP_IN_SPEED)
		{
			newButtons |= IN_SPEED;
		}
		buttons = newButtons;
		botButtons[bot] = buttons;

		int entityFlags = GetEntityFlags(client);
		// Set the bot's MoveType
		MoveType replayMoveType = view_as<MoveType>(currentTickData.flags & RP_MOVETYPE_MASK);
		if (Movement_GetSpeed(client) > SPEED_NORMAL * 2)
		{
			Movement_SetMovetype(client, MOVETYPE_NOCLIP);
		}
		else if (replayMoveType == MOVETYPE_WALK && currentTickData.flags & RP_FL_ONGROUND)
		{
			botPaused[bot] = false;
			SetEntityFlags(client, entityFlags | FL_ONGROUND);
			Movement_SetMovetype(client, MOVETYPE_WALK);
		}
		else if (replayMoveType == MOVETYPE_LADDER)
		{
			botPaused[bot] = false;
			Movement_SetMovetype(client, MOVETYPE_LADDER);
		}
		else
		{
			Movement_SetMovetype(client, MOVETYPE_NOCLIP);
		}
		
		if (currentTickData.flags & RP_UNDER_WATER)
		{
			SetEntityFlags(client, entityFlags | FL_INWATER);
		}

		// Set some variables
		if (currentTickData.flags & RP_TELEPORT_TICK)
		{
			botCurrentTeleport[bot]++;
			Movement_SetMovetype(client, MOVETYPE_NOCLIP);
		}

		if (currentTickData.flags & RP_TAKEOFF_TICK)
		{
			hitPerf[bot] = currentTickData.flags & RP_HIT_PERF > 0;
			botIsTakeoff[bot] = true;
			botTakeoffSpeed[bot] = GetVectorHorizontalLength(currentTickData.velocity);
		}

		if ((currentTickData.flags & RP_SECONDARY_EQUIPPED) && !IsCurrentWeaponSecondary(client))
		{
			int item = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
			if (item != -1)
			{
				char name[64];
				GetEntityClassname(item, name, sizeof(name));
				FakeClientCommand(client, "use %s", name);
			}
		}
		else if (!(currentTickData.flags & RP_SECONDARY_EQUIPPED) && IsCurrentWeaponSecondary(client))
		{
			int item = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
			if (item != -1)
			{
				char name[64];
				GetEntityClassname(item, name, sizeof(name));
				FakeClientCommand(client, "use %s", name);
			}
		}

		#if defined DEBUG2
		if(!botPlaybackPaused[bot])
		{
			PrintToServer("Tick: %d", playbackTick[bot]);
			PrintToServer("X %f \nY %f \nZ %f\nPitch %f\nYaw %f", currentTickData.origin[0], currentTickData.origin[1], currentTickData.origin[2], currentTickData.angles[0], currentTickData.angles[1]);
			if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_WALK)) PrintToServer("MOVETYPE_WALK");
			if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_LADDER)) PrintToServer("MOVETYPE_LADDER");
			if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_NOCLIP)) PrintToServer("MOVETYPE_NOCLIP");
			if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_NOCLIP)) PrintToServer("MOVETYPE_NONE");

			if(currentTickData.flags & RP_IN_ATTACK) PrintToServer("IN_ATTACK");
			if(currentTickData.flags & RP_IN_ATTACK2) PrintToServer("IN_ATTACK2");
			if(currentTickData.flags & RP_IN_JUMP) PrintToServer("IN_JUMP");
			if(currentTickData.flags & RP_IN_DUCK) PrintToServer("IN_DUCK");
			if(currentTickData.flags & RP_IN_FORWARD) PrintToServer("IN_FORWARD");
			if(currentTickData.flags & RP_IN_BACK) PrintToServer("IN_BACK");
			if(currentTickData.flags & RP_IN_LEFT) PrintToServer("IN_LEFT");
			if(currentTickData.flags & RP_IN_RIGHT) PrintToServer("IN_RIGHT");
			if(currentTickData.flags & RP_IN_MOVELEFT) PrintToServer("IN_MOVELEFT");
			if(currentTickData.flags & RP_IN_MOVERIGHT) PrintToServer("IN_MOVERIGHT");
			if(currentTickData.flags & RP_IN_RELOAD) PrintToServer("IN_RELOAD");
			if(currentTickData.flags & RP_IN_SPEED) PrintToServer("IN_SPEED");
			if(currentTickData.flags & RP_IN_USE) PrintToServer("IN_USE");
			if(currentTickData.flags & RP_IN_BULLRUSH) PrintToServer("IN_BULLRUSH");

			if(currentTickData.flags & RP_FL_ONGROUND) PrintToServer("FL_ONGROUND");
			if(currentTickData.flags & RP_FL_DUCKING ) PrintToServer("FL_DUCKING");
			if(currentTickData.flags & RP_FL_SWIM) PrintToServer("FL_SWIM");
			if(currentTickData.flags & RP_UNDER_WATER) PrintToServer("WATERLEVEL!=0");
			if(currentTickData.flags & RP_TELEPORT_TICK) PrintToServer("TELEPORT");
			if(currentTickData.flags & RP_TAKEOFF_TICK) PrintToServer("TAKEOFF");
			if(currentTickData.flags & RP_HIT_PERF) PrintToServer("PERF");
			if(currentTickData.flags & RP_SECONDARY_EQUIPPED) PrintToServer("SECONDARY_WEAPON_EQUIPPED");
			PrintToServer("==============================================================");
		}
		#endif

		playbackTick[bot]++;
	}
}

// Set the bot client's GOKZ options, clan tag and name based on the loaded replay data
static void SetBotStuff(int bot)
{
	if (!botInUsed[bot] || !botDataLoaded[bot])
	{
		return;
	}

	int client = botClient[bot];
	
	// Set its movement options just in case it could negatively affect the playback
	GOKZ_SetCoreOption(client, Option_Mode, botMode[bot]);
	GOKZ_SetCoreOption(client, Option_Style, botStyle[bot]);
	
	// Clan tag and name
	SetBotClanTag(bot);
	SetBotName(bot);

	// Set bot weapons
	// Always start by removing the pistol and knife
	int currentPistol = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if (currentPistol != -1)
	{
		RemovePlayerItem(client, currentPistol);
	}
	
	int currentKnife = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
	if (currentKnife != -1)
	{
		RemovePlayerItem(client, currentKnife);
	}

	char weaponName[128];
	// Give the bot the knife stored in the replay
	/*
	if (botKnife[bot] != 0)
	{
		CS_WeaponIDToAlias(CS_ItemDefIndexToID(botKnife[bot]), weaponName, sizeof(weaponName));
		Format(weaponName, sizeof(weaponName), "weapon_%s", weaponName);	
		GivePlayerItem(client, weaponName);
	}
	else
	{
		GivePlayerItem(client, "weapon_knife");
	}
	*/
	// We are currently not doing that, as it would require us to disable the
	// FollowCSGOServerGuidelines failsafe if the bot has a non-standard knife.
	GivePlayerItem(client, "weapon_knife");
	
	// Give the bot the pistol stored in the replay
	if (botWeapon[bot] != -1)
	{
		CS_WeaponIDToAlias(CS_ItemDefIndexToID(botWeapon[bot]), weaponName, sizeof(weaponName));
		Format(weaponName, sizeof(weaponName), "weapon_%s", weaponName);
		GivePlayerItem(client, weaponName);
	}

	botCurrentTeleport[bot] = 0;
}

static void SetBotClanTag(int bot)
{
	char tag[MAX_NAME_LENGTH];

	if (botReplayType[bot] == ReplayType_Run)
	{
		if (botCourse[bot] == 0)
		{
			// KZT PRO
			FormatEx(tag, sizeof(tag), "%s %s", 
				gC_ModeNamesShort[botMode[bot]], gC_TimeTypeNames[GOKZ_GetTimeTypeEx(botTeleportsUsed[bot])]);
		}
		else
		{
			// KZT B2 PRO
			FormatEx(tag, sizeof(tag), "%s B%d %s", 
				gC_ModeNamesShort[botMode[bot]], botCourse[bot], gC_TimeTypeNames[GOKZ_GetTimeTypeEx(botTeleportsUsed[bot])]);
		}
	}
	else if (botReplayType[bot] == ReplayType_Jump)
	{
		// KZT LJ
		FormatEx(tag, sizeof(tag), "%s %s",
			gC_ModeNamesShort[botMode[bot]], gC_JumpTypesShort[botJumpType[bot]]);
	}
	else
	{
		// KZT
		FormatEx(tag, sizeof(tag), "%s", 
			gC_ModeNamesShort[botMode[bot]]);
	}

	CS_SetClientClanTag(botClient[bot], tag);
}

static void SetBotName(int bot)
{
	char name[MAX_NAME_LENGTH];

	if (botReplayType[bot] == ReplayType_Run)
	{
		// DanZay (01:23.45)
		FormatEx(name, sizeof(name), "%s (%s)", 
			botAlias[bot], GOKZ_FormatTime(botTime[bot]));
	}
	else if (botReplayType[bot] == ReplayType_Jump)
	{
		if (botJumpBlockDistance[bot] == 0)
		{
			// DanZay (291.44)
			FormatEx(name, sizeof(name), "%s (%.2f)", 
				botAlias[bot], botJumpDistance[bot]);
		}
		else
		{
			// DanZay (291.44 on 289 block)
			FormatEx(name, sizeof(name), "%s (%.2f on %d block)", 
				botAlias[bot], botJumpDistance[bot], botJumpBlockDistance[bot]);
		}
	}
	else
	{
		// DanZay
		FormatEx(name, sizeof(name), "%s", 
			botAlias[bot]);
	}
	
	gB_HideNameChange = true;
	SetClientName(botClient[bot], name);
}

// Returns the number of bots that are currently replaying
static int GetBotsInUse()
{
	int botsInUse = 0;
	for (int bot = 0; bot < RP_MAX_BOTS; bot++)
	{
		if (botInUsed[bot] && botDataLoaded[bot])
		{
			botsInUse++;
		}
	}
	return botsInUse;
}

// Returns a bot that isn't currently replaying or already played by caller, or -1 if no unused bots found
static int GetUnusedBot(int client = -1)
{
	for (int bot = 0; bot < RP_MAX_BOTS; bot++)
	{
		if (botInUsed[bot] && botCaller[bot] == client && client != -1)
		{
			return bot;
		}
		else if (!botInUsed[bot])
		{
			botInUsed[bot] = true;

			return bot;
		}
	}
	return -1;
}

static void PlaybackSkipToTick(int bot, int tick)
{
	// Load in the next tick
	ReplayTickData currentTickData;
	playbackTickData[bot].GetArray(tick, currentTickData);

	TeleportEntity(botClient[bot], currentTickData.origin, currentTickData.angles, view_as<float>( { 0.0, 0.0, 0.0 } ));

	int direction = tick < playbackTick[bot] ? -1 : 1;
	for (int i = playbackTick[bot]; i != tick; i += direction)
	{
		playbackTickData[bot].GetArray(i, currentTickData);
		if (currentTickData.flags & RP_TELEPORT_TICK)
		{
			botCurrentTeleport[bot] += direction;
		}
	}

	#if defined DEBUG2
		PrintToServer("X %f \nY %f \nZ %f\nPitch %f\nYaw %f", currentTickData.origin[0], currentTickData.origin[1], currentTickData.origin[2], currentTickData.angles[0], currentTickData.angles[1]);
		if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_WALK)) PrintToServer("MOVETYPE_WALK");
		if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_LADDER)) PrintToServer("MOVETYPE_LADDER");
		if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_NOCLIP)) PrintToServer("MOVETYPE_NOCLIP");
		if(currentTickData.flags & RP_MOVETYPE_MASK == view_as<int>(MOVETYPE_NONE)) PrintToServer("MOVETYPE_NONE");

		if(currentTickData.flags & RP_IN_ATTACK) PrintToServer("IN_ATTACK");
		if(currentTickData.flags & RP_IN_ATTACK2) PrintToServer("IN_ATTACK2");
		if(currentTickData.flags & RP_IN_JUMP) PrintToServer("IN_JUMP");
		if(currentTickData.flags & RP_IN_DUCK) PrintToServer("IN_DUCK");
		if(currentTickData.flags & RP_IN_FORWARD) PrintToServer("IN_FORWARD");
		if(currentTickData.flags & RP_IN_BACK) PrintToServer("IN_BACK");
		if(currentTickData.flags & RP_IN_LEFT) PrintToServer("IN_LEFT");
		if(currentTickData.flags & RP_IN_RIGHT) PrintToServer("IN_RIGHT");
		if(currentTickData.flags & RP_IN_MOVELEFT) PrintToServer("IN_MOVELEFT");
		if(currentTickData.flags & RP_IN_MOVERIGHT) PrintToServer("IN_MOVERIGHT");
		if(currentTickData.flags & RP_IN_RELOAD) PrintToServer("IN_RELOAD");
		if(currentTickData.flags & RP_IN_SPEED) PrintToServer("IN_SPEED");
		if(currentTickData.flags & RP_FL_ONGROUND) PrintToServer("FL_ONGROUND");
		if(currentTickData.flags & RP_FL_DUCKING ) PrintToServer("FL_DUCKING");
		if(currentTickData.flags & RP_FL_SWIM) PrintToServer("FL_SWIM");
		if(currentTickData.flags & RP_UNDER_WATER) PrintToServer("WATERLEVEL!=0");
		if(currentTickData.flags & RP_TELEPORT_TICK) PrintToServer("TELEPORT");
		if(currentTickData.flags & RP_TAKEOFF_TICK) PrintToServer("TAKEOFF");
		if(currentTickData.flags & RP_HIT_PERF) PrintToServer("PERF");
		if(currentTickData.flags & RP_SECONDARY_EQUIPPED) PrintToServer("SECONDARY_WEAPON_EQUIPPED");
		PrintToServer("==============================================================");
	#endif

	Movement_SetMovetype(botClient[bot], MOVETYPE_NOCLIP);
	playbackTick[bot] = tick;
}

static bool IsCurrentWeaponSecondary(int client)
{
	int activeWeaponEnt = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int secondaryEnt = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	return activeWeaponEnt == secondaryEnt;
}

static void MakePlayerSpectate(int client, int bot)
{
	if (!IsValidClient(client) || !IsValidClient(bot))
	{
		return;
	}

	GOKZ_JoinTeam(client, CS_TEAM_SPECTATOR);
	SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", bot);

	CreateTimer(0.1, Timer_UpdateBotName, GetClientUserId(bot));
	EnableReplayControls(client);
}

static Action Timer_UpdateBotName(Handle timer, int botUID)
{
	Event e = CreateEvent("spec_target_updated");
	e.SetInt("userid", botUID);
	e.Fire();

	return Plugin_Handled;
}

static void StopPlayBack(int bot)
{
	delete playbackTickData[bot];
	botInUsed[bot] = false;
	botDataLoaded[bot] = false;
	CancelReplayControlsForBot(bot);
	ResetBotNameAndTag(bot);
}

static void ResetBotNameAndTag(int bot)
{
	gB_HideNameChange = true;
	SetClientName(botClient[bot], IntToStringEx(bot));
	CS_SetClientClanTag(botClient[bot], "!replay");
}