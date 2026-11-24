# VR act

The optional room-scale VR standing act. Desktop paths never create it. It drives the same depth and
anatomy actions as the desktop controls; the fork's auto-speed and stroke-depth controls are
deliberately not imported.

## Ownership

The VR handle is per act and lives with the act handle: the session builds it when an act begins in
a headset and frees it with the act, and a desktop launch or a missing rig returns no handle. It
resolves the player, the avatar, the headset camera and rig origin, and the avatar's hip target from
the live scene. Its controller is a scene adapter with typed callables, never the runtime node, so
the session binds the anatomy target, the impact calls and the command dispatcher to it and VR
construction does not live in anatomy.

## Controls

The right hand's primary click is the act key. Its face button toggles the anatomy hole, and the
left hand's face button emits the oral command while the anatomy gate is open. A real hand petting
her is the act's own caress event.

Depth is movement of the hips along the act's forward axis from the reference the tracker gave when
it first reported, not a button. The controller prefers a body tracker's hip joint and otherwise
accepts a positional tracker whose label names the waist or hip. With no tracking data it leaves the
depth alone and rebases, so a tracking gap does not jump the stroke when data returns.

Anatomy actions stay additive and gated, and the buttons reach the same runtime forwards as the
desktop keys; `docs/anatomy.md` owns that behaviour.

## Rules

- Only the standing pose is supported. The mare stays in place, so the act never needs Anon's ground
  position from the rig root, which stays at the spawn anchor.
- A headset session has no desktop pointer: the headset view stands in for a captured mouse in the
  start gate, the offer refresh, refusal and the act key. A headset rig is a plain node with neither
  the desktop control lock nor the flight property, so the readiness read compares those against
  true instead of casting a missing property to a boolean.
- VR is behind the anatomy master. Desktop human Anon owns the free act camera.
- A form change in this act uses the same handover with no new input-map key: the reveal ask and the
  named shape arrive through the game's own talk turn. There is no act-HUD form hint in any build,
  and Enable debug writes the state to the run log only. The flame covers the re-pose and the
  camera and view adjustment; the head-tracked view is not broken by the reopen.
