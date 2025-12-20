# Dodgeball Airblast Hitreg Improver

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