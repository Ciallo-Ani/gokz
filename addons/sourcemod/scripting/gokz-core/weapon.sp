void OnClientDisconnect_Weapon(int client)
{
	if (IsClientInGame(client))
	{
		RemoveClientAllWeapons(client);
	}
}

void OnWeaponDrop_ClearWeapon(int entity)
{
	ClearWeapon(entity);
}



// ======[ PRIVATE ]======

static void ClearWeapon(int entity)
{
	if(IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

static void RemoveClientAllWeapons(int client)
{
	int weapon = -1;
	int max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < max; i++)
	{
		if ((weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i)) == -1)
		{
			continue;
		}

		if (RemovePlayerItem(client, weapon))
		{
			AcceptEntityInput(weapon, "Kill");
		}
	}
}
