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

ConVar g_hCvarSphereGateEnable;
ConVar g_hCvarSphereBaseSize;
ConVar g_hCvarSphereScale;
ConVar g_hCvarSphereMaxRange;

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
	g_hCvarSphereGateEnable = CreateConVar("sm_tfdb_airblast_sphere_enable", "1", "Enable additional sphere-based gate for rocket deflects (1=on,0=off)");
	g_hCvarSphereBaseSize   = CreateConVar("sm_tfdb_airblast_sphere_base", "256.0", "Base size used to derive sphere radius (cube edge length)");
	g_hCvarSphereScale      = CreateConVar("sm_tfdb_airblast_sphere_scale", "1.0", "Extra scalar applied to computed sphere radius");
	g_hCvarSphereMaxRange   = CreateConVar("sm_tfdb_airblast_max_range", "280.0", "Hard maximum straight-line airblast range for rockets (0 = no cap)");

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

static float UDL_GetDeflectionSizeMultiplier(int client)
{
	float mult = 0.0;

	if (!LibraryExists("tf2attributes"))
	{
		return mult;
	}

	if (!TF2Attrib_IsReady())
	{
		return mult;
	}

	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return mult;
	}

	char classname[64];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if (!StrEqual(classname, "tf_weapon_flamethrower", false))
	{
		return mult;
	}

	Address attr = TF2Attrib_GetByName(weapon, "deflection size multiplier");
	if (attr != Address_Null)
	{
		mult = TF2Attrib_GetValue(attr);
	}

	return mult;
}

public Action TFDB_OnRocketDeflectPre(int iIndex, int iEntity, int iOwner, int &iTarget)
{
	if (!g_hCvarSphereGateEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!UDL_IsPyro(iOwner))
	{
		return Plugin_Continue;
	}

	if (!IsValidEntity(iEntity))
	{
		return Plugin_Continue;
	}

	float clientPos[3];
	GetClientEyePosition(iOwner, clientPos);

	float rocketPos[3];
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", rocketPos);

	float baseEdge = g_hCvarSphereBaseSize.FloatValue;
	float mult = UDL_GetDeflectionSizeMultiplier(iOwner);
	float scale = 1.0 + mult;
	float radius = (baseEdge * scale * 0.5) * g_hCvarSphereScale.FloatValue;

	float maxRange = g_hCvarSphereMaxRange.FloatValue;
	if (maxRange > 0.0 && radius > maxRange)
	{
		radius = maxRange;
	}

	float dist = GetVectorDistance(clientPos, rocketPos);
	if (dist > radius)
	{
		TFDB_SetRocketEventDeflections(iIndex, TFDB_GetRocketDeflections(iIndex));
		return Plugin_Stop;
	}

	return Plugin_Continue;
}
