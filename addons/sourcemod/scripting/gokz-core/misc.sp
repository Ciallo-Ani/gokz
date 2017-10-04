/*
	Miscellaneous
	
	Small features that aren't worth splitting into their own file.
*/



// =========================  GOKZ.CFG  ========================= //

void OnMapStart_KZConfig()
{
	char kzConfigPath[] = "sourcemod/gokz/gokz.cfg";
	char kzConfigPathFull[64];
	FormatEx(kzConfigPathFull, sizeof(kzConfigPathFull), "cfg/%s", kzConfigPath);
	
	if (FileExists(kzConfigPathFull))
	{
		ServerCommand("exec %s", kzConfigPath);
	}
	else
	{
		SetFailState("Failed to load config (cfg/%s not found).", kzConfigPath);
	}
}



// =========================  GODMODE  ========================= //

void UpdateGodMode(int client)
{
	SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
}



// =========================  NOCLIP  ========================= //

void ToggleNoclip(int client)
{
	if (!IsPlayerAlive(client))
	{
		return;
	}
	
	if (Movement_GetMoveType(client) != MOVETYPE_NOCLIP)
	{
		Movement_SetMoveType(client, MOVETYPE_NOCLIP);
	}
	else
	{
		Movement_SetMoveType(client, MOVETYPE_WALK);
	}
}



// =========================  PLAYER COLLISION  ========================= //

void UpdatePlayerCollision(int client)
{
	SetEntData(client, FindSendPropInfo("CBaseEntity", "m_CollisionGroup"), 2, 4, true);
}



// =========================  HIDE PLAYERS  ========================= //

void SetupClientHidePlayers(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmitClient);
}

public Action OnSetTransmitClient(int entity, int client)
{
	if (GetOption(client, Option_ShowingPlayers) == ShowingPlayers_Disabled
		 && entity != client
		 && entity != GetObserverTarget(client))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}



// =========================  HIDE WEAPON  ========================= //

void UpdateHideWeapon(int client)
{
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 
		GetOption(client, Option_ShowingWeapon) == ShowingWeapon_Enabled);
}

void OnOptionChanged_HideWeapon(int client, Option option)
{
	if (option == Option_ShowingWeapon)
	{
		UpdateHideWeapon(client);
	}
}



// =========================  CONNECTION MESSAGES  ========================= //

void PrintConnectMessage(int client)
{
	if (!gCV_gokz_connection_messages.BoolValue || IsFakeClient(client))
	{
		return;
	}
	
	GOKZ_PrintToChatAll(false, "%t", "Client Connection Message", client);
}

void PrintDisconnectMessage(int client, Event event) // Hooked to player_disconnect event
{
	if (!gCV_gokz_connection_messages.BoolValue || IsFakeClient(client))
	{
		return;
	}
	
	char reason[64];
	GetEventString(event, "reason", reason, sizeof(reason));
	GOKZ_PrintToChatAll(false, "%t", "Client Disconnection Message", client, reason);
}



// =========================  FORCE SV_FULL_ALLTALK 1  ========================= //

void OnRoundStart_ForceAllTalk()
{
	gCV_sv_full_alltalk.IntValue = 1;
}



// =========================  SLAY ON END  ========================= //

void OnTimerEnd_SlayOnEnd(int client)
{
	if (GetOption(client, Option_SlayOnEnd) == SlayOnEnd_Enabled)
	{
		CreateTimer(3.0, Timer_SlayPlayer, GetClientUserId(client));
	}
}

public Action Timer_SlayPlayer(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (IsValidClient(client))
	{
		ForcePlayerSuicide(client);
	}
	return Plugin_Continue;
}



// =========================  ERROR SOUNDS  ========================= //

#define SOUND_ERROR "buttons/button10.wav"

void PlayErrorSound(int client)
{
	if (GetOption(client, Option_ErrorSounds) == ErrorSounds_Enabled)
	{
		EmitSoundToClient(client, SOUND_ERROR);
	}
}



// =========================  STOP SOUNDS  ========================= //

void StopSounds(int client)
{
	ClientCommand(client, "snd_playsounds Music.StopAllExceptMusic");
	GOKZ_PrintToChat(client, true, "%t", "Stopped Sounds");
}

Action OnNormalSound_StopSounds(int entity)
{
	char className[20];
	GetEntityClassname(entity, className, sizeof(className));
	if (StrEqual(className, "func_button", false))
	{
		return Plugin_Handled; // No sounds directly from func_button
	}
	return Plugin_Continue;
}



// =========================  PLAYER MODELS  ========================= //

#define PLAYER_MODEL_T "models/player/tm_leet_varianta.mdl"
#define PLAYER_MODEL_CT "models/player/ctm_idf_variantc.mdl"

void UpdatePlayerModel(int client)
{
	if (gCV_gokz_player_models.BoolValue)
	{
		// Do this after a delay so that gloves apply correctly after spawning
		CreateTimer(0.1, Timer_UpdatePlayerModel, GetClientUserId(client));
	}
}

public Action Timer_UpdatePlayerModel(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client))
	{
		return;
	}
	
	switch (GetClientTeam(client))
	{
		case CS_TEAM_T:
		{
			SetEntityModel(client, PLAYER_MODEL_T);
		}
		case CS_TEAM_CT:
		{
			SetEntityModel(client, PLAYER_MODEL_CT);
		}
	}
	
	UpdatePlayerModelAlpha(client);
}

void UpdatePlayerModelAlpha(int client)
{
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, _, _, _, gCV_gokz_player_models_alpha.IntValue);
}

void OnMapStart_PlayerModel()
{
	gCV_sv_disable_immunity_alpha.IntValue = 1; // Ensures player transparency works	
	
	PrecacheModel(PLAYER_MODEL_T, true);
	PrecacheModel(PLAYER_MODEL_CT, true);
}



// =========================  PISTOL  ========================= //

static char pistolEntityNames[PISTOL_COUNT][] = 
{
	"weapon_hkp2000", 
	"weapon_glock", 
	"weapon_p250", 
	"weapon_elite", 
	"weapon_deagle", 
	"weapon_cz75a", 
	"weapon_fiveseven", 
	"weapon_tec9"
};

static int pistolTeams[PISTOL_COUNT] = 
{
	CS_TEAM_CT, 
	CS_TEAM_T, 
	CS_TEAM_NONE, 
	CS_TEAM_NONE, 
	CS_TEAM_NONE, 
	CS_TEAM_NONE, 
	CS_TEAM_CT, 
	CS_TEAM_T
};

void UpdatePistol(int client)
{
	GivePistol(client, GetOption(client, Option_Pistol));
}

void OnOptionChanged_Pistol(int client, Option option)
{
	if (option == Option_Pistol)
	{
		UpdatePistol(client);
	}
}

static void GivePistol(int client, int pistol)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)
		 || GetClientTeam(client) == CS_TEAM_NONE)
	{
		return;
	}
	
	int playerTeam = GetClientTeam(client);
	bool switchedTeams = false;
	
	// Switch teams to the side that buys that gun so that gun skins load
	if (pistolTeams[pistol] == CS_TEAM_CT && playerTeam != CS_TEAM_CT)
	{
		CS_SwitchTeam(client, CS_TEAM_CT);
		switchedTeams = true;
	}
	else if (pistolTeams[pistol] == CS_TEAM_T && playerTeam != CS_TEAM_T)
	{
		CS_SwitchTeam(client, CS_TEAM_T);
		switchedTeams = true;
	}
	
	// Give the player this pistol
	int currentPistol = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if (currentPistol != -1)
	{
		RemovePlayerItem(client, currentPistol);
	}
	GivePlayerItem(client, pistolEntityNames[pistol]);
	
	// Go back to original team
	if (switchedTeams)
	{
		CS_SwitchTeam(client, playerTeam);
	}
}



// =========================  JOIN TEAM HANDLING  ========================= //

static bool hasSavedPosition[MAXPLAYERS + 1];
static float savedOrigin[MAXPLAYERS + 1][3];
static float savedAngles[MAXPLAYERS + 1][3];

void SetupClientJoinTeam(int client)
{
	hasSavedPosition[client] = false;
}

void JoinTeam(int client, int team)
{
	if (team == CS_TEAM_SPECTATOR && GetClientTeam(client) != CS_TEAM_SPECTATOR)
	{
		Movement_GetOrigin(client, savedOrigin[client]);
		Movement_GetEyeAngles(client, savedAngles[client]);
		hasSavedPosition[client] = true;
		ChangeClientTeam(client, CS_TEAM_SPECTATOR);
		Call_GOKZ_OnJoinTeam(client, team);
	}
	else if ((team == CS_TEAM_CT && GetClientTeam(client) != CS_TEAM_CT) || (team == CS_TEAM_T && GetClientTeam(client) != CS_TEAM_T))
	{
		ForcePlayerSuicide(client);
		CS_SwitchTeam(client, team);
		CS_RespawnPlayer(client);
		if (hasSavedPosition[client])
		{
			Movement_SetOrigin(client, savedOrigin[client]);
			Movement_SetEyeAngles(client, savedAngles[client]);
			hasSavedPosition[client] = false;
		}
		else
		{
			TimerStop(client);
		}
		Call_GOKZ_OnJoinTeam(client, team);
	}
	UpdateTPMenu(client);
}

void OnTimerStart_JoinTeam(int client)
{
	hasSavedPosition[client] = false;
}



// =========================  CHAT PROCESSING  ========================= //

#define MAX_MESSAGE_LENGTH 128

Action OnClientSayCommand_ChatProcessing(int client, const char[] command, const char[] message)
{
	if (!gCV_gokz_chat_processing.BoolValue)
	{
		return Plugin_Continue;
	}
	
	if (gB_BaseComm && BaseComm_IsClientGagged(client)
		 || UsedBaseChat(client, command, message)
		 || IsChatTrigger())
	{
		return Plugin_Handled;
	}
	
	// Resend messages that may have been a command with capital letters
	if ((message[0] == '!' || message[0] == '/') && IsCharUpper(message[1]))
	{
		char loweredMessage[MAX_MESSAGE_LENGTH];
		String_ToLower(message, loweredMessage, sizeof(loweredMessage));
		FakeClientCommand(client, "say %s", loweredMessage);
		return Plugin_Handled;
	}
	
	char sanitisedMessage[MAX_MESSAGE_LENGTH];
	strcopy(sanitisedMessage, sizeof(sanitisedMessage), message);
	SanitiseChatInput(sanitisedMessage, sizeof(sanitisedMessage));
	
	char sanitisedName[MAX_NAME_LENGTH];
	GetClientName(client, sanitisedName, sizeof(sanitisedName));
	SanitiseChatInput(sanitisedName, sizeof(sanitisedName));
	
	if (TrimString(sanitisedMessage) == 0)
	{
		return Plugin_Handled;
	}
	
	if (GetClientTeam(client) == CS_TEAM_SPECTATOR)
	{
		GOKZ_PrintToChatAll(false, "{bluegrey}%s{default} : %s", sanitisedName, sanitisedMessage);
	}
	else
	{
		GOKZ_PrintToChatAll(false, "{lime}%s{default} : %s", sanitisedName, sanitisedMessage);
	}
	return Plugin_Handled;
}

static bool UsedBaseChat(int client, const char[] command, const char[] message)
{
	// Assuming base chat is in use, check if message will get processed by basechat
	if (message[0] != '@')
	{
		return false;
	}
	
	if (strcmp(command, "say_team", false) == 0)
	{
		return true;
	}
	else if (strcmp(command, "say", false) == 0 && CheckCommandAccess(client, "sm_say", ADMFLAG_CHAT))
	{
		return true;
	}
	
	return false;
}

static void SanitiseChatInput(char[] message, int maxlength)
{
	Color_StripFromChatText(message, message, maxlength);
	CRemoveColors(message, maxlength);
	// Chat gets double formatted, so replace '%' with '%%%%' to end up with '%'
	ReplaceString(message, maxlength, "%", "%%%%");
}



// =========================  VALID JUMP TRACKING  ========================= //

/*
	Valid jump tracking is intended to detect when the player
	has performed a normal jump that hasn't been affected by
	(unexpected) teleports or other cases that may result in
	the player becoming airborne, such as spawning.
	
	There are ways to trick the plugin, but it is rather
	unlikely to happen during normal gameplay.
*/

static bool validJump[MAXPLAYERS + 1];
static int lastJumpTick[MAXPLAYERS + 1];
static int lastOriginTeleportTick[MAXPLAYERS + 1];
static int lastVelocityTeleportTick[MAXPLAYERS + 1];

bool GetValidJump(int client)
{
	return validJump[client];
}

static void InvalidateJump(int client)
{
	if (validJump[client])
	{
		validJump[client] = false;
		Call_GOKZ_OnJumpInvalidated(client);
	}
}

void OnStopTouchGround_ValidJump(int client, bool jumped)
{
	// Make sure leaving the ground wasn't caused by anything fishy
	if (IsValidStopTouchGround(client))
	{
		validJump[client] = true;
		lastJumpTick[client] = GetGameTickCount();
		Call_GOKZ_OnJumpValidated(client, jumped, false);
	}
	else
	{
		InvalidateJump(client);
	}
}

static bool IsValidStopTouchGround(int client)
{
	if (Movement_GetMoveType(client) != MOVETYPE_WALK)
	{
		return false;
	}
	
	// Return false if there was a recent teleport
	
	int originTpTicks = GetGameTickCount() - lastOriginTeleportTick[client];
	if (originTpTicks <= 2)
	{
		return false;
	}
	
	// Allow 0 ticks since last velocity teleport in case mode has set speed already
	int velocityTpTicks = GetGameTickCount() - lastVelocityTeleportTick[client];
	if (velocityTpTicks <= 2 && velocityTpTicks != 0)
	{
		return false;
	}
	
	return true;
}

void OnChangeMoveType_ValidJump(int client, MoveType oldMoveType, MoveType newMoveType)
{
	if (oldMoveType == MOVETYPE_LADDER && newMoveType == MOVETYPE_WALK) // Ladderjump
	{
		validJump[client] = true;
		Call_GOKZ_OnJumpValidated(client, false, true);
	}
	else
	{
		InvalidateJump(client);
	}
}

void OnClientDisconnect_ValidJump(int client)
{
	InvalidateJump(client);
}

void OnPlayerSpawn_ValidJump(int client)
{
	InvalidateJump(client);
}

void OnPlayerDeath_ValidJump(int client)
{
	InvalidateJump(client);
}

void OnTeleport_ValidJump(int client, bool origin, bool velocity)
{
	if (origin)
	{
		lastOriginTeleportTick[client] = GetGameTickCount();
		InvalidateJump(client);
	}
	else if (velocity)
	{
		lastVelocityTeleportTick[client] = GetGameTickCount();
		// Allow short grace period for velocity so that modes may set player speed
		if (GetGameTickCount() - Movement_GetTakeoffTick(client) > 1)
		{
			InvalidateJump(client);
		}
	}
}



// =========================  JUMP BEAM  ========================= //

#define JUMP_BEAM_LIFETIME 4.0

static int jumpBeam;

void OnMapStart_JumpBeam()
{
	jumpBeam = PrecacheModel("materials/sprites/laser.vmt", true);
}

void OnPlayerRunCmd_JumpBeam(int targetClient)
{
	// In this case, spectators are handled from the target 
	// client's OnPlayerRunCmd call, otherwise the jump 
	// beam will be all broken up.
	
	KZPlayer targetPlayer = new KZPlayer(targetClient);
	
	if (targetPlayer.fake || !targetPlayer.alive || targetPlayer.onGround || !targetPlayer.validJump)
	{
		return;
	}
	
	// Send to self
	SendJumpBeam(targetPlayer, targetPlayer);
	
	// Send to spectators
	for (int client = 1; client <= MaxClients; client++)
	{
		KZPlayer player = new KZPlayer(client);
		if (player.inGame && !player.alive && player.observerTarget == targetClient)
		{
			SendJumpBeam(player, targetPlayer);
		}
	}
}

static void SendJumpBeam(KZPlayer player, KZPlayer targetPlayer)
{
	if (player.jumpBeam == JumpBeam_Disabled)
	{
		return;
	}
	
	switch (player.jumpBeam)
	{
		case JumpBeam_Feet:SendFeetJumpBeam(player, targetPlayer);
		case JumpBeam_Head:SendHeadJumpBeam(player, targetPlayer);
		case JumpBeam_FeetAndHead:
		{
			SendFeetJumpBeam(player, targetPlayer);
			SendHeadJumpBeam(player, targetPlayer);
		}
		case JumpBeam_Ground:SendGroundJumpBeam(player, targetPlayer);
	}
}

static void SendFeetJumpBeam(KZPlayer player, KZPlayer targetPlayer)
{
	float origin[3], beamStart[3], beamEnd[3];
	int beamColour[4];
	targetPlayer.GetOrigin(origin);
	
	beamStart = gF_OldOrigin[targetPlayer.id];
	beamEnd = origin;
	GetJumpBeamColour(targetPlayer, beamColour);
	
	TE_SetupBeamPoints(beamStart, beamEnd, jumpBeam, 0, 0, 0, JUMP_BEAM_LIFETIME, 3.0, 3.0, 10, 0.0, beamColour, 0);
	TE_SendToClient(player.id);
}

static void SendHeadJumpBeam(KZPlayer player, KZPlayer targetPlayer)
{
	float origin[3], beamStart[3], beamEnd[3];
	int beamColour[4];
	targetPlayer.GetOrigin(origin);
	
	beamStart = gF_OldOrigin[targetPlayer.id];
	beamEnd = origin;
	if (gB_OldDucking[targetPlayer.id])
	{
		beamStart[2] = beamStart[2] + 54.0;
	}
	else
	{
		beamStart[2] = beamStart[2] + 72.0;
	}
	if (targetPlayer.ducking)
	{
		beamEnd[2] = beamEnd[2] + 54.0;
	}
	else
	{
		beamEnd[2] = beamEnd[2] + 72.0;
	}
	GetJumpBeamColour(targetPlayer, beamColour);
	
	TE_SetupBeamPoints(beamStart, beamEnd, jumpBeam, 0, 0, 0, JUMP_BEAM_LIFETIME, 3.0, 3.0, 10, 0.0, beamColour, 0);
	TE_SendToClient(player.id);
}

static void SendGroundJumpBeam(KZPlayer player, KZPlayer targetPlayer)
{
	float origin[3], takeoffOrigin[3], beamStart[3], beamEnd[3];
	int beamColour[4];
	targetPlayer.GetOrigin(origin);
	targetPlayer.GetTakeoffOrigin(takeoffOrigin);
	
	beamStart = gF_OldOrigin[targetPlayer.id];
	beamEnd = origin;
	beamStart[2] = takeoffOrigin[2];
	beamEnd[2] = takeoffOrigin[2];
	GetJumpBeamColour(targetPlayer, beamColour);
	
	TE_SetupBeamPoints(beamStart, beamEnd, jumpBeam, 0, 0, 0, JUMP_BEAM_LIFETIME, 3.0, 3.0, 10, 0.0, beamColour, 0);
	TE_SendToClient(player.id);
}

static void GetJumpBeamColour(KZPlayer targetPlayer, int colour[4])
{
	if (targetPlayer.ducking)
	{
		colour =  { 255, 0, 0, 110 }; // Red
	}
	else
	{
		colour =  { 0, 255, 0, 110 }; // Green
	}
}



// =========================  CLAN TAG  ========================= //

void UpdateClanTag(int client)
{
	if (!IsFakeClient(client))
	{
		CS_SetClientClanTag(client, gC_ModeNamesShort[GOKZ_GetOption(client, Option_Mode)]);
	}
}

void OnOptionChanged_ClanTag(int client, Option option)
{
	if (option == Option_Mode)
	{
		UpdateClanTag(client);
	}
} 