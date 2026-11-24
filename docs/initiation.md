# Proactive requests

The proactive service is the one controller that lets a mare ask Anon for sex. It owns the pacing,
the placeable choice, the walk to him or to a bed and the ask itself. It never starts the act and
never owns an answer: it hands a formed offer over and the negotiation takes the exchange from there.

## When she may ask

An automatic scan runs on a slow cadence and only in a quiet moment: the tree is running, no menu
holds the cursor, Anon is not locked, flying or knocked down, the conversation director is idle and
its own background-AI policy allows her to speak, and no character chat happened recently. While a
negotiation holds the lock the scan stays quiet, so no second mare starts reasoning, walking or
asking at the same time.

Per mare the scan then needs an idle, present and awake runtime with a stable identity, Base
clearance from the eligibility and act-gate answers, and room in her own cooldown. The cooldown is
the history wait since her last request, shortened in heat, and a failed route, a failed reasoning
or a refused handoff leaves a short retry instead.

One mare is reasoned about per pass, with a rotating start, though the pass may assemble options for
several. A blocked quiet moment and a skipped mare are logged when the reason changes rather than on
every pass, so a long cooldown stays quiet.

## The options

Options are built before any reasoning, from one placement pass, so the mare reasons about the
places that actually exist. A cuddle needs the live cuddle, the bed under her and an offer target
naming her; a bed needs an offerable bed pose on a free bed near Anon on the same floor and region; a
standing offer needs an offerable standing pose, a free navigator in Anon's region and Anon inside
the standing reach. That reach is where he must be for her to ask, not how far she will walk. While
she is cuddling, a cuddle is the only option considered.

Only offerable poses survive; an internal pose is rejected rather than replaced by another. Each
survivor then passes the scene-only rows, and a hard scene failure drops it. The player and bed-gate
rows are deliberately not required at formation: Anon is not in position yet, and the Agreement's
own start is what waits for them. A request with no world root or no runtime is rejected outright.

## The reasoning

The reasoning is one bounded model call per scan, given the Context facts and the indexed options,
and it answers whether she offers and which option she means. A no is not a failure: she takes the
full pacing cooldown and the scan moves on. An unavailable or unusable answer leaves the short
retry, and an option index outside the list she was given is a no-offer.

The call runs after the options exist and before she walks, and a request with no options makes no
call at all. An automatic offer needs full AI usage; the debug actions run with less because they
bypass the reasoning and use the requested option, or the first placeable one.

## The walk and the ask

She walks to Anon or leads him to the bed front, and the approach gives up if the quiet moment ends,
the region changes, Anon moves away or her navigator ownership is lost. Walking to Anon ends in a
short settle beside him; the bed lead ends when the front is reached or the navigator finishes, with
its own cap.

The ask is spoken in her normal standing pose, through the director's greeting if it can take one
and otherwise as one generated intent, with one world-context situation recorded beside it. A
non-cuddle offer claims the navigator and asks her to stand; a cuddle keeps the cuddle session's own
navigator owner. Her speed and pace overrides are restored before the request lease leaves.

The handoff forms the Mare offer from the decided values and passes it over. A refusal means the
lease comes back, the short retry is set and no line is spoken. Otherwise she speaks, the situation
is recorded and the attempt ends: the negotiation now owns the answer and the hold.

## Privacy

Visibility is derived once, when the offer forms, with the offer rule for a bed or standing offer and
the cuddle rule for a cuddle. There is no public-offer override and no heat or public-consent rule
that would make a crowded spot private, so a crowded offer is simply public. Live sampling after
formation belongs to the negotiation, and this service does not watch it.

## Pacing after the answer

A refusal or an acceptance reported by the negotiation carries a cooldown signal, but the stored
history cooldown here is the effective per-mare wait. A line that was never an offer reports nothing
at all, so a conversation does not silently cost her the chance to ask. A cuddle's rising edge
clears that mare's cooldown and allows one ask per cuddle.

## Cancellation

One close path ends an attempt. It hands the navigator back with its saved owner, wander, speed and
pace when this service still owns it, sets the short retry unless the world is closing, logs the
reason and clears the attempt. A successful handoff is not a close: it clears the attempt and moves
the lease instead.

A forced debug request closes any live attempt first, and a new Anon offer or the act key interrupts
her walk the same way. A world enter or close cancels a pending reasoning call too, because the call
belonged to the world that is gone. A save during an attempt resumes with no attempt and no lease.

## Boundary and debug

The rules, the facts, the wording and the reasoning are pure: they take plain values and return plain
values, with no node, tree, clock, file, settings or game access. Scene reads belong to the venue
adapter, the model call to the bounded transport, and the conversation to the director, so no stock
director field is read here.

**Trigger bed offer** and **Trigger standing offer** run a forced request and report why a route
ended before the ask; they need the settings page closed to advance. The Show data section reports
the cooldown, the retry, the live attempt and the last skipped reason, and **Clear offer cooldown**
clears the aimed mare's cooldown, retry and last skip.
