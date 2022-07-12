
int pointsTotal[MAXPLAYERS + 1][MODE_COUNT][TIMETYPE_COUNT];
int finishes[MAXPLAYERS + 1][MODE_COUNT][TIMETYPE_COUNT];
int pointsMap[MAXPLAYERS + 1][MODE_COUNT][TIMETYPE_COUNT];
int requestsInProgress[MAXPLAYERS + 1];



void ResetPoints(int client)
{
	for (int mode = 0; mode < MODE_COUNT; mode++)
	{
		for (int type = 0; type < TIMETYPE_COUNT; type++)
		{
			pointsTotal[client][mode][type] = -1;
			finishes[client][mode][type] = -1;
			pointsMap[client][mode][type] = -1;
		}
	}
	requestsInProgress[client] = 0;
}

void ResetMapPoints(int client)
{
	for (int mode = 0; mode < MODE_COUNT; mode++)
	{
		for (int type = 0; type < TIMETYPE_COUNT; type++)
		{
			pointsMap[client][mode][type] = -1;
		}
	}
	requestsInProgress[client] = 0;
}

int GetRankPoints(int client, int mode)
{
	return pointsTotal[client][mode][TimeType_Nub];
}

int GetPoints(int client, int mode, int timeType)
{
	return pointsTotal[client][mode][timeType];
}

int GetMapPoints(int client, int mode, int timeType)
{
	return pointsMap[client][mode][timeType];
}

int GetFinishes(int client, int mode, int timeType)
{
	return finishes[client][mode][timeType];
}

// Note: This only gets 128 tick records
void UpdatePoints(int client, bool force = false, int mode = -1)
{
	if (requestsInProgress[client] != 0)
	{
		return;
	}
	
	if (mode == -1)
	{
		mode = GOKZ_GetCoreOption(client, Option_Mode);
	}
	
	if (force)
	{
		GetPlayerRanks(client, mode, TimeType_Nub, _, true);
		GetPlayerRanks(client, mode, TimeType_Pro, _, true);
		requestsInProgress[client] += 2;
	}
	else
	{
		if (pointsTotal[client][mode][TimeType_Nub] == -1)
		{
			GetPlayerRanks(client, mode, TimeType_Nub);
			requestsInProgress[client] += 1;
		}
		if (pointsTotal[client][mode][TimeType_Pro] == -1)
		{
			GetPlayerRanks(client, mode, TimeType_Pro);
			requestsInProgress[client] += 1;
		}
	}
	
	if (gI_MapID != -1)
	{
		if (force)
		{
			GetPlayerRanks(client, mode, TimeType_Nub, gI_MapID, true);
			GetPlayerRanks(client, mode, TimeType_Pro, gI_MapID, true);
			requestsInProgress[client] += 2;
		}
		else
		{
			if (pointsMap[client][mode][TimeType_Nub] == -1)
			{
				GetPlayerRanks(client, mode, TimeType_Nub, gI_MapID);
				requestsInProgress[client] += 1;
			}
			if (pointsMap[client][mode][TimeType_Pro] == -1)
			{
				GetPlayerRanks(client, mode, TimeType_Pro, gI_MapID);
				requestsInProgress[client] += 1;
			}
		}
	}
}

static void GetPlayerRanks(int client, int mode, int timeType, int mapID = DEFAULT_INT, bool broadcast = false)
{
	char steamid[21];
	int modes[1], mapIDs[1];
	
	modes[0] = view_as<int>(GOKZ_GL_GetGlobalMode(mode));
	mapIDs[0] = mapID;
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	
	DataPack dp = new DataPack();
	dp.WriteCell(GetClientUserId(client));
	dp.WriteCell(mode);
	dp.WriteCell(timeType);
	dp.WriteCell(mapID == DEFAULT_INT);
	dp.WriteCell(broadcast);
	GlobalAPI_GetPlayerRanks(UpdatePointsCallback, dp, _, _, _, _, steamid, _, _,
							 mapIDs, mapID == DEFAULT_INT ? DEFAULT_INT : 1, { 0 }, 1,
							 modes, 1, { 128 }, 1, timeType == TimeType_Nub ? DEFAULT_BOOL : false, _, _);
}

static void UpdatePointsCallback(JSON_Object ranks, GlobalAPIRequestData request, DataPack dp)
{
	dp.Reset();
	int client = GetClientOfUserId(dp.ReadCell());
	int mode = dp.ReadCell();
	int timeType = dp.ReadCell();
	bool isTotal = dp.ReadCell();
	bool bBroadcast = dp.ReadCell();
	delete dp;
	
	requestsInProgress[client]--;
	
	if (client == 0)
	{
		return;
	}
	
	int points, totalFinishes;
	int oldTotalPoints = pointsTotal[client][mode][timeType];
	int oldMapPoints = pointsMap[client][mode][timeType];
	if (request.Failure || !ranks.IsArray || ranks.Length == 0)
	{
		points = 0;
		totalFinishes = 0;
	}
	else
	{
		APIPlayerRank rank = view_as<APIPlayerRank>(ranks.GetObjectIndexed(0));
		// points = timeType == TimeType_Nub ? rank.PointsOverall : rank.Points;
		points = points == -1 ? 0 : rank.Points;
		totalFinishes = rank.Finishes == -1 ? 0 : rank.Finishes;
	}
	
	if (isTotal)
	{
		pointsTotal[client][mode][timeType] = points;
		finishes[client][mode][timeType] = totalFinishes;

		// not updated
		if (oldTotalPoints == points)
		{
			return;
		}
	}
	else
	{
		pointsMap[client][mode][timeType] = points;

		// not updated
		if (oldMapPoints == points)
		{
			return;
		}
	}
	
	if (bBroadcast)
	{
		Call_OnPointsUpdated(client, mode, timeType, isTotal, oldTotalPoints, pointsTotal[client][mode][timeType], oldMapPoints, pointsMap[client][mode][timeType]);
	}
}
