# TF2 Dodgeball Airblast Improvements

Ultra-light dodgeball airblast consistency plugin for TF2, now based entirely on real engine reflects.

This plugin is a server-side SourcePawn plugin that improves how reliable Pyro airblast feels in TF2 Dodgeball by slightly extending the actual flamethrower airblast range using `tf2attributes`, instead of doing synthetic or “second chance” reflects.

Rockets are still reflected by the game engine. The plugin only tweaks how far the airblast deflection volume reaches in dodgeball.

---

## What It Does Now

- Uses `tf2attributes` to apply the `deflection size multiplier` attribute to Pyro flamethrowers while TF2Dodgeball is active.
- Slightly increases the airblast deflection range so close calls that should have hit are more likely to register.
- Only applies to dodgeball gameplay (when the TFDB plugin is running and dodgeball is enabled).
- Does not perform any custom reflect logic, ray tracing, or “assist” reflects.

The result is that reflects feel more consistent and less “just outside range”, without late, desynced, or obviously assisted deflections.

---

## Design Philosophy

- Use only the game’s native reflect logic.
- Adjust the underlying airblast attribute instead of simulating extra hits.
- Dodgeball rockets only.
- Preserve the skill ceiling and timing; keep the change subtle.
- Server-side, configuration-free.

If players can tell something is helping them beyond what the engine would do, it is too much.

---

## Implementation Overview

File: `scripting/DodgeballAirblastImprover.sp`

The plugin:

- Includes `tf2attributes` and `tfdb`.
- On plugin start, hooks the `player_spawn` event and immediately applies attributes to any already connected clients.
- When a player spawns (or on plugin load for existing players), it:
  - Checks that TF2Dodgeball is available and enabled.
  - Checks that `tf2attributes` is available and ready.
  - If the client is a Pyro, finds their primary weapon and, if it is a flamethrower, applies:

```sourcepawn
TF2Attrib_SetByName(weapon, "deflection size multiplier", 0.2);
```

This value is chosen to be a small, noticeable bump in reflect consistency rather than a dramatic range increase.

---

## Scope and Safety

- Requires TF2Dodgeball (`TF2Dodgeball.smx`) and `tf2attributes.smx`.
- Only touches:
  - Pyro primary flamethrower in dodgeball.
  - The `deflection size multiplier` attribute.
- Does not:
  - Modify stock TF2 outside dodgeball.
  - Alter damage, projectile paths, or rocket logic.
  - Add any client-side requirements.

If TFDB or `tf2attributes` is missing or not ready, the plugin safely does nothing.

---

## Player Perception

Players should experience:

- Fewer “it should have reflected” moments on close-range or fast rockets.
- No noticeable change in basic dodgeball mechanics.
- No delayed or “snapping” reflects caused by post-hoc correction.

From a player’s point of view, the server simply has solid Pyro reflect hitreg in dodgeball.

---

## DodgeballTickPatch

Ultra-light tick/intent patch that helps TF2Dodgeball notice legitimate reflects that the core plugin would otherwise miss because counters or timing do not line up perfectly.

### What It Does

- Hooks TF2Dodgeball rocket events and looks for rockets that would hit a Pyro who very recently airblasted.
- When a valid, recent airblast is detected but TFDB did not produce a reflect, it:
  - Calls the engine’s real `ForceReflect` so the rocket is deflected normally.
  - Bumps TFDB’s internal `eventDeflections` counter one step ahead of `deflections` so the core plugin runs its own “new deflect” branch on the next think.
  - Optionally cleans up TFDB rocket state flags so the rocket is not left stuck in drag or stolen states.
- Leaves all normal, on-time reflects entirely to TFDB and the engine.

The result is that “I clearly airblasted that” moments caused by unlucky server tick alignment now turn into real reflects and target retargets, using TFDB’s existing logic.

### Intent Gate (No Free Reflects)

To avoid free or buffered reflects, the plugin only helps when the Pyro’s intent is extremely recent:

- Tracks the engine tick (`GetGameTickCount`) and game time of each airblast per client.
- For each candidate rocket, requires:
  - `dtick = currentTick - lastTick` in the range `0..2`.
  - `dt = GetGameTime() - lastTime` ≤ `0.03` seconds.

If either condition fails, the plugin does nothing and the rocket behaves exactly as vanilla TF2Dodgeball.

This gives ±2 ticks of scheduling forgiveness and at most 30 ms of real intent while still preserving skill-based timing.

### Implementation Overview

File: `scripting/DodgeballTickPatch.sp`

The plugin:

- Includes `tfdb` and uses feature flags to only touch TFDB natives that exist on the running version.
- On relevant rocket callbacks, checks:
  - That TF2Dodgeball is loaded and the rocket belongs to dodgeball.
  - That the victim is a Pyro with a very recent, valid airblast intent.
- When it decides to help a reflect, it:
  - Calls the engine reflect once, reusing the real shooter and weapon where possible.
  - Updates `eventDeflections` and `deflections` so TFDB sees “one new deflect” on the next rocket think.
  - Clears problematic `RocketState` flags (dragging or stolen) if that API is available.

If any TFDB natives are missing, the plugin gracefully degrades to only calling the safe operations or doing nothing.

### Scope and Safety

- Requires TF2Dodgeball (`TF2Dodgeball.smx`).
- Only touches dodgeball rockets and their reflect bookkeeping.
- Does not:
  - Add late or second-chance reflects outside the strict intent gate.
  - Change damage, rocket speed, or general dodgeball rules.
  - Affect normal TF2 gameplay outside TF2Dodgeball.
