# Dodgeball Airblast Hitreg Improver

**Ultra-Light Dodgeball Hitreg Consistency Plugin for TF2**

This plugin is a server-side SourcePawn plugin designed to improve **airblast consistency** in Team Fortress 2 dodgeball without altering visible gameplay, balance, or skill ceiling.

The plugin compensates for **32-bit Source Engine tick discretization**, projectile tunneling, and human reaction variance — making dodgeball *feel* correct rather than easier.

Players will not perceive assistance.  
They will perceive **clean hitreg**.

---

## Design Philosophy

- Invisible assistance only
- No automation or auto-reflect
- No changes to flamethrower behavior
- Dodgeball rockets only
- Skill ceiling preserved
- Server-side math corrections only

If players can *tell* something is helping them, it's too much.

---

## Why This Exists

On 32-bit TF2 servers:

- Airblast hit detection is discrete (≈256-unit cube)
- Rockets can travel farther than the reflect volume in a single tick
- High-speed dodgeball rockets can "skip" reflect checks
- Players experience phantom misses and inconsistent timing

This plugin **undoes these limitations** without modifying the engine.

---

## Feature Stack

This plugin is composed of five independent systems that stack together:

1. **Grace Window on Timing** (Micro-Latency Buffer)
2. **Target Bias Assistance** (Lock-On Favoring)
3. **Sub-Tick Rocket Sweep**
4. **Inflated Airblast Hull** (Server-Side Only)
5. **Velocity-Scaled Forgiveness**

Each system is scoped, gated, and applied only to dodgeball rockets.

---

## Rocket Tracking Infrastructure

### Rocket Identification

- Only rockets spawned by the dodgeball plugin are tracked
- Stock TF2 projectiles are ignored

### Per-Rocket State

Each tracked rocket stores:

```sourcepawn
struct RocketData
{
    float lastPos[3];
    float velocity[3];
    int lockTarget;
    int reflectCount;
}
```

---

## Feature Details

### 1. Grace Window on Timing

**Micro-Latency Buffer**

#### Purpose

Compensates for:
- Human reaction variance
- Network latency
- Tick-based discretization

#### Behavior

A reflect succeeds if the Pyro airblasts slightly early or slightly late.

#### Implementation

Per-client storage:

```sourcepawn
float lastAirblastTime[MAXPLAYERS + 1];
```

On airblast:

```sourcepawn
lastAirblastTime[client] = GetGameTime();
```

On reflect eligibility:

```sourcepawn
if (Abs(GetGameTime() - lastAirblastTime[client]) <= 0.05)
{
    ReflectRocket();
}
```

#### Notes

- 50ms is below conscious perception
- Removes "I swear I hit that" frustration
- Feels like consistency, not assistance

---

### 2. Target Bias Assistance

**Lock-On Favoring**

#### Purpose

Helps the intended airblaster without preventing saves.

#### Behavior

If a rocket is locked onto a player, that player receives a slightly larger reflect window.

#### Implementation

```sourcepawn
if (rocketTarget == client)
{
    reflectRadius *= 1.15;
}
```

#### Notes

- Teammates can still reflect
- Reinforces personal responsibility
- Integrates naturally with dodgeball lock-on logic

---

### 3. Sub-Tick Rocket Sweep

**Core Hitreg Fix**

#### Purpose

Eliminates projectile tunneling caused by:
- High rocket speed
- Low tick resolution
- Discrete airblast hull checks

#### Behavior

Per tick:
1. Store the rocket's previous position
2. Perform a manual hull trace between last tick → current tick
3. Detect intersections with the airblast hull

#### Implementation

```sourcepawn
float lastPos[2048][3];

public OnGameFrame()
{
    for (each dodgeball rocket)
    {
        float curPos[3];
        GetEntPropVector(rocket, Prop_Data, "m_vecOrigin", curPos);

        TraceHull(
            lastPos[rocket],
            curPos,
            airblastHullMins,
            airblastHullMaxs,
            result
        );

        if (result.hit && PyroAirblastingNearby())
        {
            ReflectRocket();
        }

        lastPos[rocket] = curPos;
    }
}
```

#### Notes

- Fully server-side
- No visual snapping
- Feels like better netcode
- Must be limited to dodgeball rocket count

---

### 4. Inflated Airblast Hull

**Server-Side Only**

#### Purpose

Compensates for edge misses caused by:
- Discrete collision checks
- Fast projectile movement

#### Behavior

A custom, slightly larger hull is used only for reflect detection.

#### Hull Definition

```sourcepawn
float mins[3] = { -40.0, -40.0, -40.0 };
float maxs[3] = {  40.0,  40.0,  40.0 };
```

*(Default engine hull is approximately ±32)*

#### Notes

- Visual gameplay unchanged
- Does not affect non-dodgeball gameplay
- Used only during reflect checks

---

### 5. Velocity-Scaled Forgiveness

#### Purpose

Prevents late-round rockets from becoming mechanically unreflectable.

#### Behavior

Reflect forgiveness scales with rocket speed.

#### Implementation

```sourcepawn
float speed = GetVectorLength(rocketVel);

float forgiveness = Clamp(speed / 3000.0, 1.0, 1.25);
reflectRadius *= forgiveness;
```

#### Notes

- Self-balancing
- No effect on slow rockets
- Maximum assistance capped at 25%

---

## Per-Tick Execution Order

1. Update rocket positions
2. Perform sub-tick rocket sweep
3. Check airblast timing grace window
4. Apply lock-on target bias
5. Apply velocity-scaled forgiveness
6. Perform airblast hull check
7. Reflect rocket if all conditions pass

---

## Performance Constraints

- Dodgeball rockets only
- Rocket count is capped
- No global entity scanning
- One sweep trace per rocket per tick
- Per-client grace window storage only

Designed for 32-bit server stability.

---

## Player Perception Goals

### Players will say:

- "Hitreg feels clean"
- "Fast volleys are playable"
- "This server just feels better"

### Players will not:

- Notice assistance
- Detect automation
- Feel skill compression

---

## Summary

This plugin does not make dodgeball easier.

It makes dodgeball behave correctly under:
- 32-bit limitations
- Tick-based simulation
- High-speed projectile gameplay

**This is not helping players.**  
**This is removing simulation error.**
