#include <sourcemod>
#include <sdktools>
#include <sdktools_trace>
#include <sdkhooks>
#include <dhooks>
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
float g_fLastAirblastTime[MAXPLAYERS + 1];
int g_iRocketDamageHandledTick[2049];
bool g_bHasTFDBLastDeflectTime;
bool g_bHasTFDBGetFlags;
bool g_bHasTFDBEventDefs;
bool g_bHasTFDBDefs;
bool g_bHasTFDBState;
bool g_bHasTFDBFindRocket;
bool g_bHasTFDBHomingThink;
bool g_bHasTFDBOtherThink;
Handle g_hFlameThrowerSecondaryAttack;
ConVar g_cvDBTickDebug;

public MRESReturn Hook_FlameThrowerSecondaryAttack(int pThis)
{
	if (!IsValidEntity(pThis))
	{
		return MRES_Ignored;
	}

	int owner = GetEntPropEnt(pThis, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients)
	{
		return MRES_Ignored;
	}

	if (!IsClientInGame(owner) || !IsPlayerAlive(owner))
	{
		return MRES_Ignored;
	}

	if (TF2_GetPlayerClass(owner) != TFClass_Pyro)
	{
		return MRES_Ignored;
	}

	if (!LibraryExists("tfdb"))
	{
		return MRES_Ignored;
	}

	if (!TFDB_IsDodgeballEnabled())
	{
		return MRES_Ignored;
	}

	g_iLastAirblastTick[owner] = GetGameTickCount();
	g_fLastAirblastTime[owner] = GetGameTime();

	if (g_cvDBTickDebug != null && g_cvDBTickDebug.BoolValue)
	{
		PrintToServer("[DBTick] Airblast via DHooks: %N", owner);
	}

	return MRES_Ignored;
}

static void DBTick_HookDamageForClient(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (!IsClientInGame(client))
	{
		return;
	}

	SDKHook(client, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnPlayerTakeDamage);
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
		g_fLastAirblastTime[i] = 0.0;
	}

	for (int i = 0; i < sizeof(g_iRocketDamageHandledTick); i++)
	{
		g_iRocketDamageHandledTick[i] = 0;
	}

	g_bHasTFDBLastDeflectTime = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketLastDeflectionTime") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketLastDeflectionTime") == FeatureStatus_Available;
	g_bHasTFDBGetFlags = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketFlags") == FeatureStatus_Available;
	g_bHasTFDBEventDefs = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketEventDeflections") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketEventDeflections") == FeatureStatus_Available;
	g_bHasTFDBDefs = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketDeflections") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketDeflections") == FeatureStatus_Available;
	g_bHasTFDBState = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketState") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "TFDB_SetRocketState") == FeatureStatus_Available;
	g_bHasTFDBFindRocket = GetFeatureStatus(FeatureType_Native, "TFDB_FindRocketByEntity") == FeatureStatus_Available;
	g_bHasTFDBHomingThink = GetFeatureStatus(FeatureType_Native, "TFDB_HomingRocketThink") == FeatureStatus_Available;
	g_bHasTFDBOtherThink = GetFeatureStatus(FeatureType_Native, "TFDB_RocketOtherThink") == FeatureStatus_Available;

	g_cvDBTickDebug = CreateConVar("sm_dbtick_debug", "1", "Debug TFDB airblast tick patch");

	g_hFlameThrowerSecondaryAttack = DHookCreate(294, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Hook_FlameThrowerSecondaryAttack);
	if (g_hFlameThrowerSecondaryAttack == null)
	{
		SetFailState("Failed to create CTFFlameThrower::SecondaryAttack hook");
	}

	DHookEnableDetour(g_hFlameThrowerSecondaryAttack, false, Hook_FlameThrowerSecondaryAttack);

	HookEvent("player_spawn", DBTick_OnPlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", DBTick_OnPlayerDeath, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		DBTick_HookDamageForClient(i);
	}
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iLastAirblastTick[i] = 0;
		g_fLastAirblastTime[i] = 0.0;
	}

	for (int i = 0; i < sizeof(g_iRocketDamageHandledTick); i++)
	{
		g_iRocketDamageHandledTick[i] = 0;
	}
}

public void OnClientPutInServer(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
	g_fLastAirblastTime[client] = 0.0;

	DBTick_HookDamageForClient(client);
}

public void OnClientDisconnect(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
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
	g_fLastAirblastTime[client] = 0.0;

	DBTick_HookDamageForClient(client);
}

public void DBTick_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_iLastAirblastTick[client] = 0;
	g_fLastAirblastTime[client] = 0.0;
}

public Action OnPlayerTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!UDL_IsPyro(victim))
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

	if (!(damagetype & DMG_BLAST))
	{
		return Plugin_Continue;
	}

	int rocketEnt = inflictor;
	if (rocketEnt <= 0 || !IsValidEntity(rocketEnt))
	{
		return Plugin_Continue;
	}

	if (!g_bHasTFDBFindRocket)
	{
		return Plugin_Continue;
	}

	int iIndex = TFDB_FindRocketByEntity(rocketEnt);
	if (iIndex <= 0)
	{
		return Plugin_Continue;
	}

	int tick = GetGameTickCount();
	if (g_iRocketDamageHandledTick[iIndex] == tick)
	{
		return Plugin_Continue;
	}

	if (g_bHasTFDBLastDeflectTime)
	{
		float lastDef = TFDB_GetRocketLastDeflectionTime(iIndex);
		if (lastDef > 0.0 && (GetGameTime() - lastDef) < 0.05)
		{
			return Plugin_Continue;
		}
	}

	char cls[64];
	GetEdictClassname(rocketEnt, cls, sizeof(cls));
	if (!StrEqual(cls, "tf_projectile_rocket", false))
	{
		return Plugin_Continue;
	}

	float rocketPos[3];
	if (HasEntProp(rocketEnt, Prop_Data, "m_vecAbsOrigin"))
	{
		GetEntPropVector(rocketEnt, Prop_Data, "m_vecAbsOrigin", rocketPos);
	}
	else
	{
		GetEntPropVector(rocketEnt, Prop_Send, "m_vecOrigin", rocketPos);
	}

	float eye[3];
	float eyeAngles[3];
	float dir[3];
	float right[3];
	float up[3];

	GetClientEyePosition(victim, eye);
	GetClientEyeAngles(victim, eyeAngles);
	GetAngleVectors(eyeAngles, dir, right, up);

	float to[3];
	to[0] = rocketPos[0] - eye[0];
	to[1] = rocketPos[1] - eye[1];
	to[2] = rocketPos[2] - eye[2];

	float forwardDist = GetVectorDotProduct(to, dir);
	if (forwardDist <= 0.0)
	{
		return Plugin_Continue;
	}

	if (DB_TICKPATCH_MAX_RANGE > 0.0 && forwardDist > DB_TICKPATCH_MAX_RANGE)
	{
		return Plugin_Continue;
	}

	float side = FloatAbs(GetVectorDotProduct(to, right));
	if (side > 140.0)
	{
		return Plugin_Continue;
	}

	float vert = FloatAbs(GetVectorDotProduct(to, up));
	if (vert > 120.0)
	{
		return Plugin_Continue;
	}

	Handle trace = TR_TraceRayFilterEx(eye, rocketPos, MASK_SOLID_BRUSHONLY, RayType_EndPoint, DBTick_TraceFilter, rocketEnt);
	bool blocked = TR_DidHit(trace) && TR_GetFraction(trace) < 0.99;
	CloseHandle(trace);

	if (blocked)
	{
		return Plugin_Continue;
	}

	int lastTick = g_iLastAirblastTick[victim];
	int dtick = tick - lastTick;
	if (dtick < 0 || dtick > 4)
	{
		return Plugin_Continue;
	}

	float lastTime = g_fLastAirblastTime[victim];
	if (lastTime <= 0.0)
	{
		return Plugin_Continue;
	}

	float dt = GetGameTime() - lastTime;
	if (dt > DB_TICKPATCH_MAX_INTENT_AGE)
	{
		return Plugin_Continue;
	}

	if (g_cvDBTickDebug != null && g_cvDBTickDebug.BoolValue)
	{
		PrintToServer("[DBTick] Direct-hit reflect attempt: rocket=%d pyro=%N", iIndex, victim);
	}

	if (!DBTick_TryPatchReflect(iIndex, rocketEnt, victim))
	{
		return Plugin_Continue;
	}

	g_iRocketDamageHandledTick[iIndex] = tick;

	damage = 0.0;
	return Plugin_Handled;
}

public Action TFDB_OnRocketExplodePre(int iIndex, int iEntity)
{
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
		if (dtick < 0 || dtick > 4)
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

	if (!DBTick_TryPatchReflect(iIndex, iEntity, bestPyro))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

static bool DBTick_TryPatchReflect(int iIndex, int iEntity, int pyroClient)
{
	if (!LibraryExists("tfdb"))
	{
		return false;
	}

	if (!TFDB_IsDodgeballEnabled())
	{
		return false;
	}

	if (!TFDB_IsValidRocket(iIndex))
	{
		return false;
	}

	if (!UDL_IsPyro(pyroClient))
	{
		return false;
	}

	if (iEntity <= MaxClients || !IsValidEntity(iEntity))
	{
		return false;
	}

	if (g_bHasTFDBLastDeflectTime)
	{
		float lastDeflect = TFDB_GetRocketLastDeflectionTime(iIndex);
		if (lastDeflect > 0.0 && (GetGameTime() - lastDeflect) < 0.05)
		{
			return false;
		}
	}

	if (g_bHasTFDBGetFlags)
	{
		RocketFlags flags = TFDB_GetRocketFlags(iIndex);
		if (TestFlags(flags, RocketFlag_Exploded))
		{
			return false;
		}
	}

	SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", pyroClient);

	if (!g_bHasTFDBDefs || !g_bHasTFDBEventDefs)
	{
		return false;
	}

	int defs = TFDB_GetRocketDeflections(iIndex);
	TFDB_SetRocketEventDeflections(iIndex, defs + 1);

	if (g_bHasTFDBState)
	{
		RocketState state = TFDB_GetRocketState(iIndex);
		state = view_as<RocketState>(state & ~(RocketState_Dragging | RocketState_Stolen));
		TFDB_SetRocketState(iIndex, state);
	}

	float vel[3];
	GetEntPropVector(iEntity, Prop_Data, "m_vecVelocity", vel);
	NormalizeVector(vel, vel);
	ScaleVector(vel, 50.0);

	float pos[3];
	if (HasEntProp(iEntity, Prop_Data, "m_vecAbsOrigin"))
	{
		GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", pos);
	}
	else
	{
		GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", pos);
	}
	
	AddVectors(pos, vel, pos);
	TeleportEntity(iEntity, pos, NULL_VECTOR, NULL_VECTOR);
	
	if (g_bHasTFDBHomingThink)
	{
		TFDB_HomingRocketThink(iIndex);
	}

	if (g_bHasTFDBOtherThink)
	{
		TFDB_RocketOtherThink(iIndex);
	}

	if (g_bHasTFDBLastDeflectTime)
	{
		TFDB_SetRocketLastDeflectionTime(iIndex, GetGameTime());
	}

	if (g_cvDBTickDebug != null && g_cvDBTickDebug.BoolValue)
	{
		PrintToServer("[DBTick] PATCH SPOOF DEFLECT rocket=%d pyro=%N", iIndex, pyroClient);
	}
	
	return true;
}
