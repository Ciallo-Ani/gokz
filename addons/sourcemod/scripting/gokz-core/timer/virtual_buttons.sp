/*
	Most commonly referred to in the KZ community as timer tech.
	Lets players press 'virtual' start and end buttons without looking.
*/



static float lastUsePressTime[MAXPLAYERS + 1];
static bool hasStartedTimerSincePressingUse[MAXPLAYERS + 1];
static bool hasEndedTimerSincePressingUse[MAXPLAYERS + 1];
static bool hasTeleportedSincePressingUse[MAXPLAYERS + 1];
static bool hasVirtualStartButton[MAXPLAYERS + 1];
static bool hasVirtualEndButton[MAXPLAYERS + 1];
static float virtualStartOrigin[MAXPLAYERS + 1][3];
static float virtualEndOrigin[MAXPLAYERS + 1][3];
static int virtualStartCourse[MAXPLAYERS + 1];
static int virtualEndCourse[MAXPLAYERS + 1];
static bool virtualButtonsLocked[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

bool GetHasVirtualStartButton(int client)
{
	return hasVirtualStartButton[client];
}

bool GetHasVirtualEndButton(int client)
{
	return hasVirtualEndButton[client];
}

bool ToggleVirtualButtonsLock(int client)
{
	virtualButtonsLocked[client] = !virtualButtonsLocked[client];
	return virtualButtonsLocked[client];
}



// =====[ EVENTS ]=====

void OnClientPutInServer_VirtualButtons(int client)
{
	hasStartedTimerSincePressingUse[client] = false;
	hasVirtualEndButton[client] = false;
	hasVirtualStartButton[client] = false;
	virtualButtonsLocked[client] = false;
}

void OnStartButtonPress_VirtualButtons(int client, int course)
{
	if (!virtualButtonsLocked[client])
	{
		Movement_GetOrigin(client, virtualStartOrigin[client]);
		virtualStartCourse[client] = course;
		hasVirtualStartButton[client] = true;
	}
}

void OnEndButtonPress_VirtualButtons(int client, int course)
{
	// Prevent setting end virtual button to where it would usually be unreachable
	if (IsPlayerStuck(client))
	{
		return;
	}
	
	if (!virtualButtonsLocked[client])
	{
		Movement_GetOrigin(client, virtualEndOrigin[client]);
		virtualEndCourse[client] = course;
		hasVirtualEndButton[client] = true;
	}
}

void OnPlayerRunCmdPost_VirtualButtons(int client, int buttons)
{
	if (buttons & IN_USE && !(gI_OldButtons[client] & IN_USE))
	{
		lastUsePressTime[client] = GetGameTime();
		hasStartedTimerSincePressingUse[client] = false;
		hasEndedTimerSincePressingUse[client] = false;
		hasTeleportedSincePressingUse[client] = false;
	}
	
	if (PassesUseCheck(client))
	{
		if (GetHasVirtualStartButton(client) && InRangeOfVirtualStart(client) && CanReachVirtualStart(client))
		{
			if (TimerStart(
					client, 
					virtualStartCourse[client], 
					.playSound = !hasStartedTimerSincePressingUse[client]))
			{
				hasStartedTimerSincePressingUse[client] = true;
				OnVirtualStartButtonPress_Teleports(client);
			}
		}
		else if (GetHasVirtualEndButton(client) && InRangeOfVirtualEnd(client) && CanReachVirtualEnd(client))
		{
			TimerEnd(client, virtualEndCourse[client]);
			hasEndedTimerSincePressingUse[client] = true; // False end counts as well
		}
	}
}

void OnCountedTeleport_VirtualButtons(int client)
{
	hasTeleportedSincePressingUse[client] = true;
}



// =====[ PRIVATE ]=====

static bool PassesUseCheck(int client)
{
	if (GetGameTime() - lastUsePressTime[client] < GOKZ_VIRTUAL_BUTTON_USE_DETECTION_TIME + EPSILON
		 && !hasEndedTimerSincePressingUse[client]
		 && !hasTeleportedSincePressingUse[client])
	{
		return true;
	}
	
	return false;
}

static bool InRangeOfVirtualStart(int client)
{
	return InRangeOfButton(client, virtualStartOrigin[client]);
}

static bool InRangeOfVirtualEnd(int client)
{
	return InRangeOfButton(client, virtualEndOrigin[client]);
}

static bool InRangeOfButton(int client, const float buttonOrigin[3])
{
	float origin[3];
	Movement_GetOrigin(client, origin);
	float distanceToButton = GetVectorDistance(origin, buttonOrigin);
	
	switch (GOKZ_GetCoreOption(client, Option_Mode))
	{
		case Mode_SimpleKZ:return distanceToButton <= GOKZ_SKZ_VIRTUAL_BUTTON_RADIUS;
		case Mode_KZTimer:return distanceToButton <= GOKZ_KZT_VIRTUAL_BUTTON_RADIUS;
	}
	return false;
}

static bool CanReachVirtualStart(int client)
{
	return CanReachButton(client, virtualStartOrigin[client]);
}

static bool CanReachVirtualEnd(int client)
{
	return CanReachButton(client, virtualEndOrigin[client]);
}

static bool CanReachButton(int client, const float buttonOrigin[3])
{
	float origin[3];
	Movement_GetOrigin(client, origin);
	Handle trace = TR_TraceRayFilterEx(origin, buttonOrigin, MASK_PLAYERSOLID, RayType_EndPoint, TraceEntityFilterPlayers);
	bool didHit = TR_DidHit(trace);
	delete trace;
	return !didHit;
}
