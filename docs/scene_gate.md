# Scene gate

The scene gate is the live half of the act gate. `act_gate` answers whether an adult mare may
act right now; this service answers whether the scene is ready right now: her runtime state, the
pause, conversation, sleep, an act or aftercare already running, cuddles and affection, the pose's
profile, form, view and source, Anon's readiness, the navigator, the footstool supply, the pose
asset and rig, and the bed. It also owns the physical refusal the strict tolerance stop uses.

## Kinds of answer

The gate answers three shapes of question. A general start adds the final scene rows to the policy
verdict; a proactive offer uses the offer-safe subset; an accepted Agreement runs the scene-only
rows against the capabilities frozen at formation. Every scene row carries the policy's own row
type, so a caller can report one list. The merge keeps the policy snapshot beside the scene's own
pass, and the pure policy never sees a bed, a navigator, a pose asset or the player's body.

The structural rows come first and fail closed: a missing body, world, player or game stops the
rest instead of being reported as a scene problem. A forced offer, used by the debug trigger, skips
the pause row and nothing else.

## The small checks

The hint and the act key share one composite readiness rather than building rows: the structural
handles and the pose-independent scene rows, the pose's profile, source, asset and rig, Anon's side
and any bed, the navigator, her posture, the stool pair, and Base clearance. The clearance read is
always last, so a scene that is busy for a cheaper reason never pays it. The composite and the full
row verdict must answer the same thing.

## An accepted Agreement

An Agreement's start runs only the live world rows, because Base clearance and the pose capability
were frozen when it formed. Aftercare is not a row there: the act clears it at start. The form and
view are not rows either: they were frozen with the pose pair and the act applies them, so
re-testing the live pair could refuse what formation accepted. Two rows stay transient, Anon's
position and the bed-side condition, and the start waits on them within the Agreement's lifetime;
any other failure ends the Agreement as failed. The negotiation's hold is exempt from the
affection, navigator-owner and posture rows, so its reserved lease still blocks while its own hold
does not.

## Pose capability

Every pose question is a capability read of shared pose data: its frame, its bed and stool needs,
its standing-free flag, its authored act sources, whether it is public and offerable, and the
player forms and views it supports. The gate never compares pose ids, and an unknown or internal
pose reads as the fail-closed default.

## Beds

A bed pose resolves the bed under her, or the one the offer carries. Whether the mattress can seat
her at all is the stock bed's own rule, measured against her own body scale as it offers her the
spot; the mod overrides nothing there, and a mare the bed cannot fit is refused before she ever
lies down. The gate's own rows answer the rest: the bed exists, no other mare is on it, and her
posture and Anon's side suit the source.

## The navigator owner

The gate reads the navigator's owner as a lease vocabulary, not as intent. A free owner passes.
This mod's request controller may hold her while she is idle. A sleep lease passes only for an
awake pony already lying in a bed, and other sleep use is refused. This mod's other owners, weather
and shows are blocked. A cuddle or leisure seat passes only for a bed pose when the act's source is
one the pose authors, player conversation is free, and routine owners are free only with no active
route. A player-owned or resting bond is free; anything unrecognised is blocked.

## The running act

The running verdict is the act's own periodic check. Being held, another affection, an active
cuddle, a reserved navigator, a bed a second mare lies on, or the player's form changing all
interrupt it; conversation does not, because the act clears the listener itself. A failed verdict
goes through the one stop.

## Buck and push

The physical refusal asks her affection to buck and falls back to a knockdown push on Anon, and it
reports whether either ran. Only the strict tolerance stop uses it: the live act key never bucks,
and no gate verdict carries a refusal.

## Debug

The debug line assembles the live values from the runtime's context and prints the rows, both hints
and the act values. The offer side forwards the same line rather than building a second one.
