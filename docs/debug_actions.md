# Debug actions executor

The World service that carries the debug actions themselves: the node behind the Debug block's
buttons and the hold-middle wheel, and the owner of the Show data collector, the wheel's open gate
and the skeleton overlay. The Process table that names, labels and gates those actions is
`docs/debug.md`.

## Scope

`debug_actions/api.gd` is the facade: one node per process, a child of the entry and a member of
`unfplap_world`. It publishes itself as the table's target when it enters the tree and clears that
target when it leaves, so a caller never passes it in. Its own methods are one per table entry; its
helpers are `wheel.gd` (the wheel), `skeleton.gd` (the overlay), `bed.gd` (the stock bed cuddle),
`pony.gd` (the sex-ready preparation and the scene gate's debug facts) and `idle_stretch.gd` (the
Idle Life deep-stretch bridge).

## Boundary

- **No table.** Action ids, labels, wheel pages and the open-gate decision belong to
  `debug/api.gd`; the executor declares no entry, no label and no page order. Its preload of the
  table is the only edge between the two services.
- **No hotkeys, no settings writes.** The registry declares none, and the executor neither polls
  input for an action nor writes a setting. It reads the debug and skeleton flags it follows at use,
  the way any service reads its typed handles.
- **Peers arrive in `wire`.** The composition root's one call hands it the body-change, initiation,
  negotiation, anatomy, act-frame, HUD, roster, eligibility and estrus handles, and binds the
  pantyhose hull rebuild as a callable so the node never imports a pack file. Nothing else assigns
  those fields, and `wire` is the only writer.
- Every action aims through the table's one aimed-mare rule; the anatomy placement editor shares it
  rather than re-deriving it.

## Live reads

The executor builds its own live-act reads when it enters the tree. They are facade reads: the act
frame's live runtime, the roster's runtime for one body and its live set, the eligibility capability
behind an act target, and the poses service's authored-base reload. A test can install fakes for
these before the node is added, so the actions stay testable without the game. The idle-life entry
is handed in by the host when that mod is present; the actions work without it.

## Ordering and lifecycle

On entry the node publishes the table's target first, then builds the live reads if a suite has not
bound them, then joins the settings-change list and syncs the skeleton overlay; a dispatch that
arrives during that window therefore already resolves the node. A settings edit closes an open wheel
when debug mode goes off and then re-syncs the overlay. On exit it leaves the settings list and
clears the table's target only if it is still that node, so a freed executor leaves no dispatch
behind and a replacement is never cleared by its predecessor.

Both the enter and the close hooks drop an open wheel, so none outlives the world it was opened in.
The world never frees the node; it resets only what the world owned.

## The wheel

Nothing exists until someone holds the middle button with debug mode on, so a pack with debug off
never builds the node at all. The wheel is the executor's child and runs the hovered slot's action
through the table, then writes the one-line result to the HUD toast and the name and result to the
debug log; Show data's multi-line block stays in the log.

Opening needs the table's open gate to pass, and the wheel stays open only while its target still
exists and the act context has not changed page. **Hold the middle mouse button** in captured
desktop play to open it and release it on a slot to run that action; a release in the centre just
closes. The centre names the target and whether she was aimed or the live act; there is no help text
there. A virtual reticle follows mouse motion, and moving onto a slot plays the base game's
`prop_ui_confirm` click once — the centre, the opening and the closing are silent. **Left click**
over a slot also runs it, **right click** and **Escape** close, and the game's `F4`/`F9`/`F10`/`F11`
dev keys close the wheel and pass through. While open, mouse motion, mouse buttons and keys are
consumed, so the act does not thrust or free-look.

The wheel closes on release (running the hovered slot first), debug-off, pause, focus loss, a menu
or headset, a mouse-mode change, a world close or an act-context change. It never pauses the tree,
never dims the frame and claims no hotkey or setting.

## Show data

The executor's collector returns stable sections: the target and its runtime, the estrus cycle, the
scene gate's distance/pose line, the initiation and negotiation rows, the act's own rows, the
stool presentation, the stored act history, the prompt notes the mod contributes and the bed rows.
The act section is present only while the aimed mare owns the live act. The action prints the whole
dictionary as one tab-indented log entry, and the bed action uses the same bed row builder, so the
two never diverge. The collector stays a plain dictionary, so a future always-on overlay can render
it without changing the action.

## Skeleton overlay

The overlay follows the persisted skeleton flag while debug mode is on, and it exists only while
both are on. It draws nearby loaded ponies' body, face and hair/tail skeletons as thin unshaded
lines with joint circles, updating at a fixed rate and covering a bounded range. Left-clicking a
joint prints its bone name, parent, world/local origin, rotation, scale and rest; hovering one turns
it red. Colors: body green, face amber, hair/tail pink. The click is forwarded from the one mod
input path, not a global hotkey. The flag itself belongs to `docs/anatomy.md`.

## Action notes

- **Placement** actions edit the selected target (global default or pointed mare). The Anatomy
  Actions block starts with the **Placement target** pill. See `docs/anatomy.md`.
- **Trigger bed/standing offer** forces a proactive ask for the aimed test mare. It bypasses the
  quiet, cooldown and AI-usage checks but keeps the eligibility gate, pose and free-bed gates.
- **Bed cuddle** is the stock bed invite migrated from the lab's Mouse4 key. It sits on the wheel
  only; `bed.gd` finds the player's bed, reclines Anon, moves a far mare to the bed approach and
  calls the stock `accept()` path. The detailed result goes to the debug log.
- **Make sex-ready** is the lab's Mouse5 qualification migrated to the Mare page. It clears the
  aimed adult mare's busy state, writes the game's own bond record (dating only when she is below
  it; engaged and married stay), clears her pending plan/offer and the boundary and dating
  cooldowns, and commits a neutral mood. Her romance tier is untouched. A missing relationship
  runtime or bond save path refuses before anything changes. The record is written through the
  game's own save path, so the action is a debug cheat like Reset act history; the detailed rows go
  to the debug log and the toast names the mare.
- **Force deep stretch** runs Idle Life's deep stretch on whichever body the action picks: the act's
  pony when one is live, the aimed mare otherwise. It interrupts an idle already running through the
  other mod's finish path and calls its forced play, so the stretch is not cut short by her posture,
  a conversation or a live act. Idle Life is optional: without it the action reports that it is not
  running. This is a debug preview, not an integration; `idle_stretch.gd` is the one file that names
  the other mod's entry.
- **Force/Clear heat** and **Force/Clear diestrus** are one slot each. The label follows the
  aimed mare's current phase; Clear sets the session phase back to normal. **Resume automatic
  cycle** clears the override and is settings-only. The action writes the session override through
  the estrus service, and the runtime keeps the cycle reads for the HUD and the debug block. See
  `docs/estrus.md`.
- **Reset act history** clears the stored row; **Force neglect warning/stop** act on the live act
  and are consumed on the next unpaused frame.
- **Clear offer cooldown** clears the aimed mare's proactive-offer cooldown, short retry and last
  scan skip, so she can be offered again immediately. See `docs/initiation.md`.
- **Trigger Anon offer** forms an Anon offer for the aimed mare as if Anon had just asked her; the
  Anon classifier and the Mare response still run.
- **Force act face** cycles the base-game faces; see `docs/face.md`.
- **Form: true form**, **Form: next named shape** and **Form: bring her out** are the generic
  body-change actions, drawn only while a shape-changing source is installed so a launch without a
  provider has no dead buttons. In a live act the first two go through the act's own request and
  the body handover continues the act; outside an act they ask the body-change service, which
  forwards to the provider and runs the idle change path. The named action cycles the shipped adult
  mares and names the next one in its result. Bring-out only asks the provider to put an away actor
  in the world and is not a change. See `docs/body_change.md`.
- **Reload posed base** re-reads the active pose's authored JSON in place; a running act picks it
  up on its next frame. With no live act it re-reads the authored base. See `docs/poses.md`.
- **Pose: test variant** is a Debug-block button with no hotkey: it toggles the internal
  `standing_test` pose in a live standing act, runs the authored `standing ↔ standing_test` edge
  and logs the request code and the status event. It never ends the act, releases the pose or
  restores bones; in a missionary act it refuses. See `docs/poses.md`. The real oral edge has no
  debug action: its key is the only trigger.
- **Pose: face-sit** is a Debug-block button with no hotkey: in a live missionary or face-sit act
  it requests the other id of the internal `missionary ↔ bed_facesit` pair and logs the request
  code. It refuses with a reason when no act is active, the view is not missionary or face-sit, the
  act is not active, the pose is changing, a kiss is running or the anatomy act body is
  unavailable. It never ends the act. See `docs/poses.md`.
- **Pantyhose: rebuild hull** clears the shared garment depth field and rebuilds it from the
  anatomy mesh after a precision edit; the build time is logged with debug logs on. It is inert
  when the pack is absent. See `docs/integrations.md` (`## Pantyhose & Panties`).
