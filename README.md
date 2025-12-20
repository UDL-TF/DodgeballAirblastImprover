# Dodgeball Airblast Hitreg Improver

Ultra-light dodgeball airblast consistency plugin for TF2, now based entirely on real engine reflects.

This plugin is a server-side SourcePawn plugin that improves how reliable Pyro airblast feels in TF2 Dodgeball by slightly extending the actual flamethrower airblast range using `tf2attributes`, instead of doing synthetic or “second chance” reflects.

Rockets are still reflected by the game engine. The plugin only tweaks how far the airblast deflection volume reaches in dodgeball.

---

## What It Does Now

- Uses `tf2attributes` to apply the `deflection size multiplier` attribute to Pyro flamethrowers while TF2Dodgeball is active.
- Slightly increases the airblast deflection range so close calls that should have hit are more likely to register.
- Only applies to dodgeball gameplay (when the TFDB plugin is running and dodgeball is enabled).
- Adds an optional spherical “gate” in front of the Pyro that must also contain the rocket for a deflect to register, removing angle/yaw bias from the stock cube hitbox without adding late “second chance” reflects.

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

Additionally, the plugin hooks the TF2Dodgeball forward `TFDB_OnRocketDeflectPre` and applies an extra, purely restrictive spherical check plus a hard straight-line range cap:

- Uses the Pyro’s eye position as the center of a sphere.
- Derives a radius from a base cube edge length (default `256.0` units, matching the stock cube) and the current `deflection size multiplier` value on the flamethrower.
- Clamps that radius to a configurable hard maximum straight-line range (default `256.0` units) so rockets cannot be deflected beyond the pink “cutoff” line even if the underlying sphere would reach further.
- If the rocket is outside this clamped radius when the engine would normally deflect it, the plugin cancels the deflect by resetting the rocket’s event deflection counter and stopping the forward.

This preserves the stock engine cube as the primary detection volume and the TF attribute as the only “range increase” knob, while enforcing a simple radial cutoff (the “pink line” in design diagrams) that does not depend on yaw, angle, or distance scaling tricks.

---

## Scope and Safety

- Requires TF2Dodgeball (`TF2Dodgeball.smx`) and `tf2attributes.smx`.
- Only touches:
  - Pyro primary flamethrower in dodgeball.
  - The `deflection size multiplier` attribute.
  - TF2Dodgeball’s rocket deflect handling via `TFDB_OnRocketDeflectPre`, and only to *reject* deflects that fall outside the configured sphere.
- Does not:
  - Modify stock TF2 outside dodgeball.
  - Alter damage, projectile paths, or rocket logic beyond cancelling a would-be deflect when it is outside the spherical cutoff.
  - Add any client-side requirements.

If TFDB or `tf2attributes` is missing or not ready, the plugin safely does nothing.

---

## Player Perception

Players should experience:

- Fewer “it should have reflected” moments on close-range or fast rockets.
- No noticeable change in basic dodgeball mechanics.
- No delayed or “snapping” reflects caused by post-hoc correction.

From a player’s point of view, the server simply has solid Pyro reflect hitreg in dodgeball.
