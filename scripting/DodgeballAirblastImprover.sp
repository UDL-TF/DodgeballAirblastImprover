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
ConVar g_hCvarSphereDebug;

bool g_bSphereGateSuppressed[MAXPLAYERS + 1];
float g_fSphereGateSavedMult[MAXPLAYERS + 1];

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
	g_hCvarSphereMaxRange   = CreateConVar("sm_tfdb_airblast_max_range", "275.0", "Hard maximum straight-line airblast range for rockets (0 = no cap)");
	g_hCvarSphereDebug      = CreateConVar("sm_tfdb_airblast_sphere_debug", "0", "Print debug when sphere gate cancels a rocket deflect (1=on,0=off)");

	AutoExecConfig(true, "DodgeballAirblastImprover", "sourcemod");

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

static float UDL_ComputeSphereRadius(int client)
{
	float baseEdge = g_hCvarSphereBaseSize.FloatValue;
	float mult = UDL_GetDeflectionSizeMultiplier(client);
	float scale = 1.0 + mult;
	float radius = (baseEdge * scale) * g_hCvarSphereScale.FloatValue;

	float maxRange = g_hCvarSphereMaxRange.FloatValue;
	if (maxRange > 0.0 && radius > maxRange)
	{
		radius = maxRange;
	}

	return radius;
}

static bool UDL_IsAnyRocketInSphere(int client, float radius)
{
	if (radius <= 0.0)
	{
		return false;
	}

	float clientPos[3];
	GetClientEyePosition(client, clientPos);

	float radiusSq = radius * radius;

	for (int i = 0; i < MAX_ROCKETS; i++)
	{
		if (!TFDB_IsValidRocket(i))
		{
			continue;
		}

		int rocketEnt = TFDB_GetRocketEntity(i);
		if (rocketEnt <= MaxClients || !IsValidEntity(rocketEnt))
		{
			continue;
		}

		float rocketPos[3];
		GetEntPropVector(rocketEnt, Prop_Send, "m_vecOrigin", rocketPos);

		float distSq = GetVectorDistance(clientPos, rocketPos, true);
		if (distSq <= radiusSq)
		{
			return true;
		}
	}

	return false;
}

static void UDL_SuppressDeflectAttribute(int client)
{
	if (g_bSphereGateSuppressed[client])
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

	Address attr = TF2Attrib_GetByName(weapon, "deflection size multiplier");
	float mult = 0.0;
	if (attr != Address_Null)
	{
		mult = TF2Attrib_GetValue(attr);
	}

	g_fSphereGateSavedMult[client] = mult;
	g_bSphereGateSuppressed[client] = true;

	TF2Attrib_SetByName(weapon, "airblast_deflect_projectiles_disabled", 1.0);

	int userid = GetClientUserId(client);
	if (userid != 0)
	{
		CreateTimer(0.0, UDL_TimerRestoreDeflectAttribute, userid);
	}
}

public Action UDL_TimerRestoreDeflectAttribute(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || client > MaxClients)
	{
		return Plugin_Stop;
	}

	if (!g_bSphereGateSuppressed[client])
	{
		return Plugin_Stop;
	}

	g_bSphereGateSuppressed[client] = false;

	if (!UDL_IsPyro(client))
	{
		return Plugin_Stop;
	}

	if (!LibraryExists("tf2attributes"))
	{
		return Plugin_Stop;
	}

	if (!TF2Attrib_IsReady())
	{
		return Plugin_Stop;
	}

	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return Plugin_Stop;
	}

	char classname[64];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if (!StrEqual(classname, "tf_weapon_flamethrower", false))
	{
		return Plugin_Stop;
	}

	TF2Attrib_RemoveByName(weapon, "airblast_deflect_projectiles_disabled");

	float mult = g_fSphereGateSavedMult[client];
	if (mult <= 0.0)
	{
		mult = 0.2;
	}

	TF2Attrib_SetByName(weapon, "deflection size multiplier", mult);

	return Plugin_Stop;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!g_hCvarSphereGateEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!UDL_IsPyro(client))
	{
		return Plugin_Continue;
	}

	if (!TFDB_IsDodgeballEnabled())
	{
		return Plugin_Continue;
	}

	if (!(buttons & IN_ATTACK2))
	{
		return Plugin_Continue;
	}

	float radius = UDL_ComputeSphereRadius(client);

	if (!UDL_IsAnyRocketInSphere(client, radius))
	{
		if (g_hCvarSphereDebug.BoolValue && UDL_IsClientValid(client))
		{
			PrintToChat(client, "[TFDB] Sphere gate ignoring extended deflect: no rocket within %.1f units", radius);
		}

		UDL_SuppressDeflectAttribute(client);
	}

	return Plugin_Continue;
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

	float radius = UDL_ComputeSphereRadius(iOwner);

	float dist = GetVectorDistance(clientPos, rocketPos);
	if (dist > radius)
	{
		if (g_hCvarSphereDebug.BoolValue)
		{
			if (UDL_IsClientValid(iOwner))
			{
				PrintToChat(iOwner, "[TFDB] Sphere gate blocked deflect: dist=%.1f, radius=%.1f", dist, radius);
			}
			PrintToServer("[TFDB] Sphere gate blocked deflect (owner %d, rocket %d): dist=%.1f, radius=%.1f", iOwner, iEntity, dist, radius);
		}
		TFDB_SetRocketEventDeflections(iIndex, TFDB_GetRocketDeflections(iIndex));
		return Plugin_Stop;
	}

	return Plugin_Continue;
}
