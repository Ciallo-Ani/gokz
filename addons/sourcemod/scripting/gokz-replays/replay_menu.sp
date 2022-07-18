/*
	Lets player select a replay bot to play back.
*/



static int selectedReplayMode[MAXPLAYERS + 1];
static bool selectedGlobalReplay[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

void DisplayReplayNetworkMenu(int client)
{
	if (gA_ReplayInfoCache.Length == 0)
	{
		GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Map)");
		GOKZ_PlayErrorSound(client);
		return;
	}

	Menu menu = new Menu(MenuHandler_ReplayNetwork);
	menu.SetTitle("选择回放数据库类型\n \n");

	menu.AddItem("global", "全球 Global");
	menu.AddItem("local", "本地 Local");
	menu.Display(client, MENU_TIME_FOREVER);
}

void DisplayReplayModeMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ReplayMode);
	menu.SetTitle("%T", "Replay Menu (Mode) - Title", client, gC_CurrentMap);
	GOKZ_MenuAddModeItems(client, menu, false);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}



// =====[ EVENTS ]=====

public int MenuHandler_ReplayNetwork(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		selectedGlobalReplay[param1] = StrEqual(sInfo, "global");

		DisplayReplayModeMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_ReplayMode(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		selectedReplayMode[param1] = param2;
		DisplayReplayMenu(param1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			DisplayReplayNetworkMenu(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_Replay(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[4];
		menu.GetItem(param2, info, sizeof(info));
		int replayIndex = StringToInt(info);

		replay_playback_cache_t playback_cache;
		gA_PlaybackCache.GetArray(replayIndex, playback_cache, sizeof(replay_playback_cache_t));

#if DEBUG
		bool success = false;

		if (playback_cache.aFrames == null)
		{
			GOKZ_PrintToChat(param1, true, "playback_cache.aFrame == null");
		}
		else if (playback_cache.aFrames.Length < 1)
		{
			GOKZ_PrintToChat(param1, true, "playback_cache.aFrame.Length < 1");
		}
		else
		{
			success = true;
			LoadReplayBot(param1, playback_cache);
		}

		if (!success)
		{
			replay_info_cache_t info_cache;
			gA_ReplayInfoCache.GetArray(replayIndex, info_cache, sizeof(replay_info_cache_t));
			GOKZ_PrintToChat(param1, true, "course -> %d | mode -> %d | style -> %d | timeType -> %d | gb -> %d", 
				info_cache.course, info_cache.mode, info_cache.style, info_cache.timeType, info_cache.global);
		}
#else
		LoadReplayBot(param1, playback_cache);
#endif
	}
	else if (action == MenuAction_Cancel)
	{
		DisplayReplayModeMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}



// =====[ PRIVATE ]=====

static void DisplayReplayMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Replay);
	menu.SetTitle("%T", "Replay Menu - Title", client, gC_CurrentMap, gC_ModeNames[selectedReplayMode[client]]);
	if (ReplayMenuAddItems(client, menu) > 0)
	{
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		if (IsDownloadingGlobalReplay(selectedReplayMode[client]) && selectedGlobalReplay[client])
		{
			GOKZ_PrintToChat(client, true, "{darkred}全球录像正在下载中(%s)", gC_ModeNames[selectedReplayMode[client]]);
		}
		else
		{
			GOKZ_PrintToChat(client, true, "%t", "No Replays Found (Mode)", gC_ModeNames[selectedReplayMode[client]]);
		}

		GOKZ_PlayErrorSound(client);
		DisplayReplayModeMenu(client);
	}
}

// Returns the number of replay menu items added
static int ReplayMenuAddItems(int client, Menu menu)
{
	int replaysAdded = 0;
	int replayCount = gA_ReplayInfoCache.Length;
	char temp[32], indexString[4];

	menu.RemoveAllItems();

	for (int i = 0; i < replayCount; i++)
	{
		IntToString(i, indexString, sizeof(indexString));

		replay_info_cache_t info_cache;
		gA_ReplayInfoCache.GetArray(i, info_cache, sizeof(replay_info_cache_t));

		// Wrong mode or wrong global
		if (info_cache.mode != selectedReplayMode[client] || info_cache.global != selectedGlobalReplay[client])
		{
			continue;
		}
		
		if (info_cache.course == 0)
		{
			FormatEx(temp, sizeof(temp), "Main %s", gC_TimeTypeNames[info_cache.timeType]);
		}
		else
		{
			FormatEx(temp, sizeof(temp), "Bonus %d %s", info_cache.course, gC_TimeTypeNames[info_cache.timeType]);
		}
		menu.AddItem(indexString, temp, ITEMDRAW_DEFAULT);
		
		replaysAdded++;
	}

	return replaysAdded;
}
