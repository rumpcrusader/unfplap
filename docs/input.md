# Input

The input service owns the act key, the mouse policy and the act input shield, and it routes the
debug action wheel. It runs before the game's desktop input, consumes what the act owns, and hands a
press on the act key to the idle offer. It does not own act behaviour: it calls the active runtime's
typed commands and lets the act's own gates refuse what it cannot do.

## The act key

The act key is a real InputMap action rebuilt from the captured `act_key` setting, not a
physical-key poll. A real action is required because the game's own input guard stashes every non-UI
action while text has focus; a raw poll cannot be stashed and would keep firing in chat. A tap in
idle play starts the hinted act, and holding it during an act ends the act or moves it on, matching
the length of the game's own carry hold.

The hold latch belongs to one live act, and both a body swap and a new act reset it; an old key
cannot carry into the next act. The key is captured through the mod's own row because the game's
control page cannot be extended by a mod.

## The shield

While an act is live the shield owns the keyboard. Every key the act does not use is consumed, so
the game's unhandled input, its interface and other mods never see it. Text entry, the talk turn,
the pause overlay and the developer keys stay available, as does everything while a text field owns
focus, the tree is paused or a menu panel is open.

A few act controls are polled each frame instead of arriving as events: the lean, caress, kiss, auto
layer and act key. Swallowing them while leaving the key down is what keeps those controls alive.
The act's discrete hole and oral keys emit command ids only while the runtime's own gate allows
them, and the key is consumed whether the command runs or is refused.

The shield cannot stop a mod that polls raw key state, because the handled flag never reaches a
poll. For the keys the act does not sample, the service feeds the input a matching release, which
the next physics step drains; the player's own release restores the real state. That is a
deliberate, temporary lie about key state, and it lives only while the act does.

The `act_input_shield` setting turns the shield off; the older per-key consumption lists then run
unchanged.

## Mouse and player

During an act the service keeps the cursor captured unless a menu, a text field, a headset or a lost
window owns it, because the act's control lock makes the game skip its own click-to-recapture. Mouse
motion free-looks when the act allows it and otherwise thrusts; while the automatic stroke runs,
mouse motion contributes nothing.

A seated player cannot stand by accident: the guard holds the seated Q state and the movement hold
keeps walking, jumping and couch sleep out of the act while leaving the camera free.

## The wheel

The debug wheel is routed before anything else. A middle-button press may open it while debug is on
and the frame allows; while it is open it owns every event, so the act, the smack, the auto wheel and
the skeleton click never see a consumed one. With debug off, or while a text field, a menu or a
headset owns the input, the middle button is not consumed.

## Limits

Consumption never stops a sibling's own input handler, and tree order cannot change that. Headset
buttons are not keys and are outside the shield. A key that is down when the act ends stays read as
released until the player presses it again, and changing the act key leaves the old key uncleared,
since the hold keeps its state. While typing, the game's own guard blanks the typed keys before any
handler sees them, so the shield consumes nothing and a raw poller sees nothing either.
