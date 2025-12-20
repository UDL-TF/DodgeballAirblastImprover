#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tfdb>

public Plugin myinfo =
{
	name = "TFDB Airblast Hitreg Improver",
	author = "Darka, Tolfx",
	description = "Dodgeball airblast consistency assistance and fix",
	version = "1.0.0",
	url = "udl.tf"
};

static void UDL_ApplyAirblastAttributes(int client)
{
	if (!UDL_IsPyro(client))
	{
		return;
	}

	if (!LibraryExists("tfdb"))
	{
		return;
	}

	if (!TFDB_IsDodgeballEnabled())
	{
		return;
	}

	if (!LibraryExists("tf2attributes"))
	{
		return;
	}

	if (!TF2Attrib_IsReady())
	{
		return;
	}

	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return;
	}

	char classname[64];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if (!StrEqual(classname, "tf_weapon_flamethrower", false))
	{
		return;
	}

	TF2Attrib_SetByName(weapon, "deflection size multiplier", 0.2);
}

public void UDL_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	UDL_ApplyAirblastAttributes(client);
}

public void OnPluginStart()
{
	HookEvent("player_spawn", UDL_OnPlayerSpawn, EventHookMode_Post);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			UDL_ApplyAirblastAttributes(client);
		}
	}
}

static bool UDL_IsClientValid(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client);
}

static bool UDL_IsPyro(int client)
{
	if (!UDL_IsClientValid(client))
	{
		return false;
	}

	if (TF2_GetPlayerClass(client) != TFClass_Pyro)
	{
		return false;
	}

	return true;
}