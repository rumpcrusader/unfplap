# Debug actions executor

The executor is the world node behind the Debug block's buttons and the hold-middle wheel. It owns
the action implementations, the Show data collector, the wheel itself and the skeleton overlay. The
process-wide table owns the ids, labels, pages and open gate; the executor declares none of them.

## Boundary and lifecycle

The executor has no table of its own: its preload of the table is the only edge. It declares no
hotkey and writes no setting, reading the debug and skeleton switches the way any service reads its
own typed handles. Its peers arrive in the composition's one wire call; nothing else assigns them.

On entry it publishes itself as the table's target before it builds its live reads, so a dispatch in
that window already resolves it. A settings edit closes an open wheel when debug goes off and
resyncs the overlay. On exit it clears the target only if it is still that node, so a replacement is
never cleared by its predecessor. Both the world enter and the world close drop an open wheel, and
the world never frees the node.

## The wheel

Nothing exists until someone holds the middle button with debug on, so a pack with debug off never
builds it. The centre names the target and whether it was aimed or came from the live act. Holding
the middle button opens it and releasing on a slot runs that action; a release in the centre just
closes. A left click over a slot runs it, a right click or Escape closes, and the game's developer
keys close it and pass through. While open it consumes mouse motion, mouse buttons and keys, so the
act neither thrusts nor free-looks.

The wheel closes on a lost target, a dead gate, a changed act context, a world close, a settings
change that turns debug off, a pause, a lost focus, a mouse-mode change, a menu or a headset. It
leaves the tree running, never dims the view, holds no key of its own and changes no setting.

## Show data and the skeleton

Show data collects a stable, indented block for the aimed mare and her runtime: the live evidence a
debug session needs, gathered in one place so a later overlay can render the same sections. The act
section exists only while she owns the live act, and the whole block prints as one log entry.

The skeleton overlay follows its own persisted switch and exists only while debug is also on. It
draws the nearby loaded ponies' body, face and hair skeletons and updates at a fixed rate over a
bounded range. Clicking a joint prints its details; the click arrives through the one mod input
path, never a global hotkey. The switch itself belongs to the anatomy settings.

## The actions

Triggering an offer forces the proactive ask for the aimed mare: it skips the quiet, cooldown and
reasoning checks but keeps eligibility, the pose list and the free-bed gates. Bed cuddle is the stock
bed invite, and its result goes to the log. Make sex-ready clears her busy state and writes the
game's bond record, raising her only as far as dating and leaving the romance tier untouched; a
missing bond store refuses before anything changes.

The remaining actions change the live game state through the service that owns it, or edit whichever
placement the anatomy editor selects, which shares the aimed-mare rule with every other action. The
pose actions reload the authored base or toggle an internal variant and never end the act. A hull
rebuild asks the garment pack to rebuild its depth field and is inert without the pack. Every action
returns one line for its surface while the detailed rows go to the log.
