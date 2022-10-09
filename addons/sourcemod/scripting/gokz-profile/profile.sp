
#define ITEM_INFO_NAME "name"
#define ITEM_INFO_MODE "mode"
#define ITEM_INFO_RANK "rank"
#define ITEM_INFO_POINTS "points"

int profileTargetPlayer[MAXPLAYERS];
int profileMode[MAXPLAYERS];
bool profileWaitingForUpdate[MAXPLAYERS];



// =====[ PUBLIC ]=====

void ShowProfile(int client, int player = 0)
{
	if (player != 0)
	{
		profileTargetPlayer[client] = player;
		profileMode[client] = GOKZ_GetCoreOption(player, Option_Mode);
	}
	
	if (GOKZ_GL_GetRankPoints(profileTargetPlayer[client], profileMode[client]) < 0)
	{
		if (!profileWaitingForUpdate[client])
		{
			GOKZ_GL_UpdatePoints(profileTargetPlayer[client], profileMode[client]);
			profileWaitingForUpdate[client] = true;
		}
		return;
	}
	
	profileWaitingForUpdate[client] = false;
	Menu menu = new Menu(MenuHandler_Profile);
	menu.SetTitle("%T - %N", "Profile Menu - Title", client, profileTargetPlayer[client]);
	ProfileMenuAddItems(client, menu);
	menu.Display(client, MENU_TIME_FOREVER);
}



// =====[ EVENTS ]=====

void Profile_OnClientConnected(int client)
{
	profileTargetPlayer[client] = 0;
	profileWaitingForUpdate[client] = false;
}

void Profile_OnClientDisconnect(int client)
{
	profileTargetPlayer[client] = 0;
	profileWaitingForUpdate[client] = false;
}

void Profile_OnPointsUpdated(int player, int mode, int timeType, bool isTotal, int oldTotalPoints, int newTotalPoints, int oldMapPoints, int newMapPoints)
{
	char sColor[16];
	FormatEx(sColor, sizeof(sColor), "%s", StrEqual(gC_TimeTypeNames[timeType], "PRO", false) ? "{purple}" : "{blue}");

	if (isTotal)
	{
		if (newTotalPoints == 0)
		{
			return;
		}

		char status[32];
		int diff = newTotalPoints - oldTotalPoints;
		if (diff > 0)
		{
			FormatEx(status, sizeof(status), "{green}获得了%d分{default}", diff);
		}
		else
		{
			FormatEx(status, sizeof(status), "{lightred}失去了%d分{default}", -diff);
		}

		GOKZ_PrintToChat(player, false, "%s%s %s >> {default}总积分发生变化, 你%s, 现在有: {gold}%d分", 
			sColor, gC_ModeNamesShort[mode], gC_TimeTypeNames[timeType], status, newTotalPoints);
	}
	else
	{
		if (newMapPoints == 0)
		{
			return;
		}
		else if (oldMapPoints <= 0)
		{
			GOKZ_PrintToChat(player, false, "%s%s %s >> {default}完成地图{green}获得了%d分", 
				sColor, gC_ModeNamesShort[mode], gC_TimeTypeNames[timeType], newMapPoints);
		}
		else
		{
			GOKZ_PrintToChat(player, false, "%s%s %s >> {default}刷新地图纪录{green}获得了%d分", 
				sColor, gC_ModeNamesShort[mode], gC_TimeTypeNames[timeType], newMapPoints - oldMapPoints);
		}
	}
}

void Profile_OnRankUpdated(int client, int mode, int rank)
{
	GOKZ_PrintToChat(client, false, "{green}%s >> {default}你现在的称号为: %s[%s]", gC_ModeNamesShort[mode], gC_rankColor[rank], gC_rankName[rank]);
}

void Profile_OnRankUpdated(int client, int mode, int rank)
{
	GOKZ_PrintToChat(client, false, "{green}%s >> {default}你现在的称号为: %s[%s]", gC_ModeNamesShort[mode], gC_rankColor[rank], gC_rankName[rank]);
}

public int MenuHandler_Profile(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		
		if (StrEqual(info, ITEM_INFO_MODE, false))
		{
			if (++profileMode[param1] == MODE_COUNT)
			{
				profileMode[param1] = 0;
			}
		}
		else if (StrEqual(info, ITEM_INFO_RANK, false))
		{
			ShowRankInfo(param1);
			return 0 0;
		}
		else if (StrEqual(info, ITEM_INFO_POINTS, false))
		{
			ShowPointsInfo(param1);
			return 0 0;
		}
		
		ShowProfile(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}



// =====[ PRIVATE ]=====

static void ProfileMenuAddItems(int client, Menu menu)
{
	char display[32];
	int player = profileTargetPlayer[client];
	int mode = profileMode[client];
	
	FormatEx(display, sizeof(display), "%T: %s",
			 "Profile Menu - Mode", client, gC_ModeNames[mode]);
	menu.AddItem(ITEM_INFO_MODE, display);
	
	FormatEx(display, sizeof(display), "%T: %s",
			 "Profile Menu - Rank", client, gC_rankName[gI_Rank[player][mode]]);
	menu.AddItem(ITEM_INFO_RANK, display);
	
	FormatEx(display, sizeof(display), "%T: %d",
			 "Profile Menu - Points", client, GOKZ_GL_GetRankPoints(player, mode));
	menu.AddItem(ITEM_INFO_POINTS, display);
}

static void ShowRankInfo(int client)
{
	Menu menu = new Menu(MenuHandler_RankInfo);
	menu.SetTitle("%T - %N", "Rank Info Menu - Title", client, profileTargetPlayer[client]);
	RankInfoMenuAddItems(client, menu);
	menu.Display(client, MENU_TIME_FOREVER);
}

static void RankInfoMenuAddItems(int client, Menu menu)
{
	char display[32];
	int player = profileTargetPlayer[client];
	int mode = profileMode[client];
	
	FormatEx(display, sizeof(display), "%T: %s",
			 "Rank Info Menu - Current Rank", client, gC_rankName[gI_Rank[player][mode]]);
	menu.AddItem("", display);
	
	int next_rank = gI_Rank[player][mode] + 1;
	if (next_rank == RANK_COUNT)
	{
		FormatEx(display, sizeof(display), "%T: -",
			 "Rank Info Menu - Next Rank", client);
		menu.AddItem("", display);
		
		FormatEx(display, sizeof(display), "%T: 0",
				 "Rank Info Menu - Points needed", client);
		menu.AddItem("", display);
	}
	else
	{
		FormatEx(display, sizeof(display), "%T: %s",
			 "Rank Info Menu - Next Rank", client, gC_rankName[next_rank]);
		menu.AddItem("", display);
		
		FormatEx(display, sizeof(display), "%T: %d",
				 "Rank Info Menu - Points needed", client, gI_rankThreshold[mode][next_rank] - GOKZ_GL_GetRankPoints(player, mode));
		menu.AddItem("", display);
	}
}

static int MenuHandler_RankInfo(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Cancel)
	{
		ShowProfile(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

static void ShowPointsInfo(int client)
{
	Menu menu = new Menu(MenuHandler_PointsInfo);
	menu.SetTitle("%T - %N", "Points Info Menu - Title", client, profileTargetPlayer[client]);
	PointsInfoMenuAddItems(client, menu);
	menu.Display(client, MENU_TIME_FOREVER);
}

static void PointsInfoMenuAddItems(int client, Menu menu)
{
	char display[32];
	int player = profileTargetPlayer[client];
	int mode = profileMode[client];
	
	FormatEx(display, sizeof(display), "%T: %d",
			 "Points Info Menu - Overall Points", client, GOKZ_GL_GetPoints(player, mode, TimeType_Nub));
	menu.AddItem("", display);
	
	FormatEx(display, sizeof(display), "%T: %d",
			 "Points Info Menu - Pro Points", client, GOKZ_GL_GetPoints(player, mode, TimeType_Pro));
	menu.AddItem("", display);
	
	FormatEx(display, sizeof(display), "%T: %d",
			 "Points Info Menu - Overall Completion", client, GOKZ_GL_GetFinishes(player, mode, TimeType_Nub));
	menu.AddItem("", display);
	
	FormatEx(display, sizeof(display), "%T: %d",
			 "Points Info Menu - Pro Completion", client, GOKZ_GL_GetFinishes(player, mode, TimeType_Pro));
	menu.AddItem("", display);
}

static int MenuHandler_PointsInfo(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Cancel)
	{
		ShowProfile(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}
