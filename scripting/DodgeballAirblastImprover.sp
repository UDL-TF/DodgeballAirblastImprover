#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tfdb>

public Plugin myinfo =
{
	name = "TFDB Airblast Hitreg Improver",
	author = "Darka, Tolfx",
	description = "Dodgeball airblast consistency assistance and fix",
	version = "1.0.0",
	url = "udl.tf"
};

#define UDL_GRACE_WINDOW 0.05
#define UDL_BASE_HULL_RADIUS 40.0
#define UDL_LOCKON_RADIUS_SCALE 1.15
#define UDL_VELOCITY_REF_SPEED 3000.0
#define UDL_VELOCITY_MAX_SCALE 1.25

static float g_RocketLastPos[MAX_ROCKETS + 1][3];
static float g_RocketVelocity[MAX_ROCKETS + 1][3];
static int g_RocketLockTarget[MAX_ROCKETS + 1];
static int g_RocketReflectCount[MAX_ROCKETS + 1];
static int g_RocketEntity[MAX_ROCKETS + 1];
static bool g_RocketInUse[MAX_ROCKETS + 1];
static float g_LastAirblastTime[MAXPLAYERS + 1];

static void UDL_ResetState()
{
	for (int i = 0; i <= MAX_ROCKETS; i++)
	{
		for (int j = 0; j < 3; j++)
		{
			g_RocketLastPos[i][j] = 0.0;
			g_RocketVelocity[i][j] = 0.0;
		}
		g_RocketLockTarget[i] = 0;
		g_RocketReflectCount[i] = 0;
		g_RocketEntity[i] = -1;
		g_RocketInUse[i] = false;
	}

	for (int c = 1; c <= MaxClients; c++)
	{
		g_LastAirblastTime[c] = 0.0;
	}
}

public void OnPluginStart()
{
	UDL_ResetState();
}

public void OnMapStart()
{
	UDL_ResetState();
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!UDL_IsPyro(client))
	{
		return Plugin_Continue;
	}

	if (!(buttons & IN_ATTACK2))
	{
		return Plugin_Continue;
	}

	int weaponEnt = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weaponEnt <= 0 || !IsValidEntity(weaponEnt))
	{
		return Plugin_Continue;
	}

	char classname[64];
	GetEdictClassname(weaponEnt, classname, sizeof(classname));

	if (StrEqual(classname, "tf_weapon_flamethrower", false))
	{
		g_LastAirblastTime[client] = GetGameTime();
	}

	return Plugin_Continue;
}

public void TFDB_OnRocketCreated(int iIndex, int iEntity)
{
	if (iIndex < 0 || iIndex > MAX_ROCKETS)
	{
		return;
	}

	if (!IsValidEntity(iEntity))
	{
		return;
	}

	float origin[3];
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", origin);

	for (int j = 0; j < 3; j++)
	{
		g_RocketLastPos[iIndex][j] = origin[j];
		g_RocketVelocity[iIndex][j] = 0.0;
	}

	g_RocketLockTarget[iIndex] = TFDB_GetRocketTarget(iIndex);
	g_RocketReflectCount[iIndex] = TFDB_GetRocketDeflections(iIndex);
	g_RocketEntity[iIndex] = iEntity;
	g_RocketInUse[iIndex] = true;
}

public void TFDB_OnRocketStateChanged(int iIndex, RocketState iState, RocketState iNewState)
{
	if (iIndex < 0 || iIndex > MAX_ROCKETS)
	{
		return;
	}

	if (!TFDB_IsValidRocket(iIndex))
	{
		g_RocketInUse[iIndex] = false;
		g_RocketEntity[iIndex] = -1;
	}
}

static void UDL_ClosestPointOnSegment(const float start[3], const float end[3], const float point[3], float out[3])
{
	float seg[3];
	seg[0] = end[0] - start[0];
	seg[1] = end[1] - start[1];
	seg[2] = end[2] - start[2];

	float segLenSq = seg[0] * seg[0] + seg[1] * seg[1] + seg[2] * seg[2];
	if (segLenSq <= 0.0001)
	{
		out[0] = start[0];
		out[1] = start[1];
		out[2] = start[2];
		return;
	}

	float toPoint[3];
	toPoint[0] = point[0] - start[0];
	toPoint[1] = point[1] - start[1];
	toPoint[2] = point[2] - start[2];

	float t = (seg[0] * toPoint[0] + seg[1] * toPoint[1] + seg[2] * toPoint[2]) / segLenSq;

	if (t < 0.0)
	{
		t = 0.0;
	}
	else if (t > 1.0)
	{
		t = 1.0;
	}

	out[0] = start[0] + seg[0] * t;
	out[1] = start[1] + seg[1] * t;
	out[2] = start[2] + seg[2] * t;
}

static float UDL_ClampFloat(float value, float min, float max)
{
	if (value < min)
	{
		return min;
	}

	if (value > max)
	{
		return max;
	}

	return value;
}

static bool UDL_PerformReflect(int rocketIndex, int rocketEnt, int client)
{
	if (!TFDB_IsValidRocket(rocketIndex))
	{
		return false;
	}

	if (!UDL_IsPyro(client))
	{
		return false;
	}

	if (!IsValidEntity(rocketEnt))
	{
		return false;
	}

	float now = GetGameTime();

	float angles[3];
	float dirForward[3];
	float right[3];
	float up[3];

	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, dirForward, right, up);
	NormalizeVector(dirForward, dirForward);

	TFDB_SetRocketDirection(rocketIndex, dirForward);

	float speed = TFDB_GetRocketSpeed(rocketIndex);
	float vel[3];
	vel[0] = dirForward[0] * speed;
	vel[1] = dirForward[1] * speed;
	vel[2] = dirForward[2] * speed;

	SetEntPropVector(rocketEnt, Prop_Data, "m_vecVelocity", vel);

	int deflections = TFDB_GetRocketDeflections(rocketIndex);
	TFDB_SetRocketDeflections(rocketIndex, deflections + 1);

	int eventDeflections = TFDB_GetRocketEventDeflections(rocketIndex);
	TFDB_SetRocketEventDeflections(rocketIndex, eventDeflections + 1);

	TFDB_SetRocketLastDeflectionTime(rocketIndex, now);

	g_RocketReflectCount[rocketIndex] = deflections + 1;
	g_RocketLockTarget[rocketIndex] = TFDB_GetRocketTarget(rocketIndex);

	return true;
}

static bool UDL_TryAssistForRocket(int rocketIndex, int rocketEnt, const float lastPos[3], const float curPos[3], float now)
{
	float lastDeflectTime = TFDB_GetRocketLastDeflectionTime(rocketIndex);
	if (now - lastDeflectTime < 0.001)
	{
		return false;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!UDL_IsPyro(client))
		{
			continue;
		}

		float dt = FloatAbs(now - g_LastAirblastTime[client]);
		if (dt > UDL_GRACE_WINDOW)
		{
			continue;
		}

		float eyePos[3];
		GetClientEyePosition(client, eyePos);

		float closest[3];
		UDL_ClosestPointOnSegment(lastPos, curPos, eyePos, closest);

		float dist = GetVectorDistance(eyePos, closest);

		float reflectRadius = UDL_BASE_HULL_RADIUS;

		int rocketTarget = TFDB_GetRocketTarget(rocketIndex);
		if (rocketTarget == client)
		{
			reflectRadius *= UDL_LOCKON_RADIUS_SCALE;
		}

		float rocketVel[3];
		GetEntPropVector(rocketEnt, Prop_Data, "m_vecVelocity", rocketVel);
		float speed = GetVectorLength(rocketVel);
		if (speed <= 0.0)
		{
			speed = TFDB_GetRocketSpeed(rocketIndex);
		}

		if (speed > 0.0)
		{
			float forgiveness = speed / UDL_VELOCITY_REF_SPEED;
			forgiveness = UDL_ClampFloat(forgiveness, 1.0, UDL_VELOCITY_MAX_SCALE);
			reflectRadius *= forgiveness;
		}

		if (dist <= reflectRadius)
		{
			if (UDL_PerformReflect(rocketIndex, rocketEnt, client))
			{
				return true;
			}
		}
	}

	return false;
}

public void OnGameFrame()
{
	if (!TFDB_IsDodgeballEnabled())
	{
		return;
	}

	if (!TFDB_GetRoundStarted())
	{
		return;
	}

	int rocketCount = TFDB_GetRocketCount();
	if (rocketCount <= 0)
	{
		return;
	}

	float now = GetGameTime();

	if (rocketCount > MAX_ROCKETS)
	{
		rocketCount = MAX_ROCKETS;
	}

	for (int i = 0; i < rocketCount; i++)
	{
		if (!TFDB_IsValidRocket(i))
		{
			g_RocketInUse[i] = false;
			continue;
		}

		int rocketEnt = TFDB_GetRocketEntity(i);
		if (rocketEnt <= 0 || !IsValidEntity(rocketEnt))
		{
			g_RocketInUse[i] = false;
			continue;
		}

		float curPos[3];
		GetEntPropVector(rocketEnt, Prop_Send, "m_vecOrigin", curPos);

		if (!g_RocketInUse[i])
		{
			for (int j = 0; j < 3; j++)
			{
				g_RocketLastPos[i][j] = curPos[j];
				g_RocketVelocity[i][j] = 0.0;
			}

			g_RocketEntity[i] = rocketEnt;
			g_RocketLockTarget[i] = TFDB_GetRocketTarget(i);
			g_RocketReflectCount[i] = TFDB_GetRocketDeflections(i);
			g_RocketInUse[i] = true;
			continue;
		}

		float lastPos[3];
		for (int j = 0; j < 3; j++)
		{
			lastPos[j] = g_RocketLastPos[i][j];
		}

		for (int j = 0; j < 3; j++)
		{
			g_RocketLastPos[i][j] = curPos[j];
		}

		if (!UDL_TryAssistForRocket(i, rocketEnt, lastPos, curPos, now))
		{
			continue;
		}
	}
}
