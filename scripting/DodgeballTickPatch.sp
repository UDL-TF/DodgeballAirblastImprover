#include <sourcemod>
#include <sdktools>
#include <sdktools_trace>
#include <tf2>
#include <tf2_stocks>
#include <tfdb>

#define DB_TICKPATCH_MAX_RANGE 275.0
#define DB_TICKPATCH_MAX_INTENT_AGE 0.03

public Plugin myinfo =
{
	name = "TFDB Airblast Tick Patch",
	author = "Darka",
	description = "Tick-based airblast reflect correction for TF2 Dodgeball",
	version = "1.0.0",
	url = ""
};

int g_iLastAirblastTick[MAXPLAYERS + 1];
int g_iLastButtons[MAXPLAYERS + 1];
float g_fLastAirblastTime[MAXPLAYERS + 1];
bool g_bHasTFDBForceReflect;
bool g_bHasTFDBLastDeflectTime;
bool g_bHasTFDBGetFlags;
bool g_bHasTFDBEventDefs;
bool g_bHasTFDBDefs;
bool g_bHasTFDBState;

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

public bool DBTick_TraceFilter(int entity, int contentsMask, any data)
{
	int rocketEnt = data;

	if (entity >= 1 && entity <= MaxClients)
	{
		return false;
	}

	if (entity == rocketEnt)
	{
		return false;
	}

	return true;
}

public void OnPluginStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iLastAirblastTick[i] = 0;
		g_iLastButtons[i] = 0;
		g_fLastAirblastTime[i] = 0.0;
	}

	g_bHasTFDBForceReflect = GetFeatureStatus(FeatureType_Native, "TFDB_ForceReflect") == FeatureStatus_Available;
	g_bHasTFDBLastDeflectTime = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketLastDeflectionTime") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketLastDeflectionTime") == FeatureStatus_Available;
	g_bHasTFDBGetFlags = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketFlags") == FeatureStatus_Available;
	g_bHasTFDBEventDefs = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketEventDeflections") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketEventDeflections") == FeatureStatus_Available;
	g_bHasTFDBDefs = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketDeflections") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketDeflections") == FeatureStatus_Available;
	g_bHasTFDBState = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketState") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketState") == FeatureStatus_Available;

	HookEvent("player_spawn", DBTick_OnPlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", DBTick_OnPlayerDeath, EventHookMode_Post);
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iLastAirblastTick[i] = 0;
		g_iLastButtons[i] = 0;
		g_fLastAirblastTime[i] = 0.0;
	}
}

public void OnClientPutInServer(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
	g_iLastButtons[client] = 0;
	g_fLastAirblastTime[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
	g_iLastButtons[client] = 0;
	g_fLastAirblastTime[client] = 0.0;
}

public void DBTick_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
	g_iLastButtons[client] = 0;
	g_fLastAirblastTime[client] = 0.0;
}

public void DBTick_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
	g_iLastButtons[client] = 0;
	g_fLastAirblastTime[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	bool pressed = (buttons & IN_ATTACK2) != 0 && (g_iLastButtons[client] & IN_ATTACK2) == 0;
	g_iLastButtons[client] = buttons;

	if (!pressed)
	{
		return Plugin_Continue;
	}

	if (!UDL_IsPyro(client))
	{
		return Plugin_Continue;
	}

	if (!LibraryExists("tfdb"))
	{
		return Plugin_Continue;
	}

	if (!TFDB_IsDodgeballEnabled())
	{
		return Plugin_Continue;
	}

	int active = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (active <= MaxClients || !IsValidEntity(active))
	{
		return Plugin_Continue;
	}

	char classname[64];
	GetEdictClassname(active, classname, sizeof(classname));
	if (!StrEqual(classname, "tf_weapon_flamethrower", false))
	{
		return Plugin_Continue;
	}

	if (HasEntProp(active, Prop_Send, "m_iClip1"))
	{
		int clip = GetEntProp(active, Prop_Send, "m_iClip1");
		if (clip <= 0)
		{
			return Plugin_Continue;
		}
	}

	g_iLastAirblastTick[client] = GetGameTickCount();
	g_fLastAirblastTime[client] = GetGameTime();

	return Plugin_Continue;
}

public Action TFDB_OnRocketExplodePre(int iIndex, int iEntity)
{
	if (!g_bHasTFDBForceReflect)
	{
		return Plugin_Continue;
	}

	if (!LibraryExists("tfdb"))
	{
		return Plugin_Continue;
	}

	if (!TFDB_IsDodgeballEnabled())
	{
		return Plugin_Continue;
	}

	if (!TFDB_IsValidRocket(iIndex))
	{
		return Plugin_Continue;
	}

	if (g_bHasTFDBLastDeflectTime)
	{
		float lastDeflect = TFDB_GetRocketLastDeflectionTime(iIndex);
		if (lastDeflect > 0.0 && (GetGameTime() - lastDeflect) < 0.05)
		{
			return Plugin_Continue;
		}
	}

	if (g_bHasTFDBGetFlags)
	{
		RocketFlags flags = TFDB_GetRocketFlags(iIndex);
		if (TestFlags(flags, RocketFlag_Exploded))
		{
			return Plugin_Continue;
		}
	}

	if (iEntity <= MaxClients || !IsValidEntity(iEntity))
	{
		return Plugin_Continue;
	}

	int currentTick = GetGameTickCount();

	float rocketPos[3];
	if (HasEntProp(iEntity, Prop_Data, "m_vecAbsOrigin"))
	{
		GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", rocketPos);
	}
	else
	{
		GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", rocketPos);
	}

	int bestPyro = 0;
	float bestDistSq = 999999999.0;

	for (int client = 1; client <= MaxClients; client++)
	{
		int lastTick = g_iLastAirblastTick[client];
		int dtick = currentTick - lastTick;
		if (dtick < 0 || dtick > 2)
		{
			continue;
		}

		float lastTime = g_fLastAirblastTime[client];
		if (lastTime <= 0.0)
		{
			continue;
		}

		float dt = GetGameTime() - lastTime;
		if (dt > DB_TICKPATCH_MAX_INTENT_AGE)
		{
			continue;
		}

		if (!UDL_IsPyro(client))
		{
			continue;
		}

		float eye[3];
		float eyeAngles[3];
		float dir[3];
		float right[3];
		float up[3];

		GetClientEyePosition(client, eye);
		GetClientEyeAngles(client, eyeAngles);
		GetAngleVectors(eyeAngles, dir, right, up);

		float to[3];
		to[0] = rocketPos[0] - eye[0];
		to[1] = rocketPos[1] - eye[1];
		to[2] = rocketPos[2] - eye[2];

		float forwardDist = GetVectorDotProduct(to, dir);
		if (forwardDist <= 0.0)
		{
			continue;
		}

		if (DB_TICKPATCH_MAX_RANGE > 0.0 && forwardDist > DB_TICKPATCH_MAX_RANGE)
		{
			continue;
		}

		float side = FloatAbs(GetVectorDotProduct(to, right));
		if (side > 140.0)
		{
			continue;
		}

		float vert = FloatAbs(GetVectorDotProduct(to, up));
		if (vert > 120.0)
		{
			continue;
		}

		Handle trace = TR_TraceRayFilterEx(eye, rocketPos, MASK_SOLID_BRUSHONLY, RayType_EndPoint, DBTick_TraceFilter, iEntity);
		bool blocked = TR_DidHit(trace) && TR_GetFraction(trace) < 0.99;
		CloseHandle(trace);

		if (blocked)
		{
			continue;
		}

		float distSq = GetVectorDistance(eye, rocketPos, true);
		if (distSq < bestDistSq)
		{
			bestPyro = client;
			bestDistSq = distSq;
		}
	}

	if (bestPyro == 0)
	{
		return Plugin_Continue;
	}

	if (!UDL_IsPyro(bestPyro))
	{
		return Plugin_Continue;
	}

	if (!TFDB_ForceReflect(iIndex, bestPyro))
	{
		return Plugin_Continue;
	}

	if (g_bHasTFDBEventDefs)
	{
		int eventDefs = TFDB_GetRocketEventDeflections(iIndex) + 1;
		TFDB_SetRocketEventDeflections(iIndex, eventDefs);

		if (g_bHasTFDBDefs)
		{
			TFDB_SetRocketDeflections(iIndex, eventDefs - 1);
		}
	}

	if (g_bHasTFDBState)
	{
		RocketState state = TFDB_GetRocketState(iIndex);
		state = view_as<RocketState>(state & ~(RocketState_Dragging | RocketState_Stolen));
		TFDB_SetRocketState(iIndex, state);
	}

	if (g_bHasTFDBLastDeflectTime)
	{
		TFDB_SetRocketLastDeflectionTime(iIndex, GetGameTime());
	}

	return Plugin_Handled;
}
