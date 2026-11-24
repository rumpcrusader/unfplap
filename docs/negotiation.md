# Negotiation

The negotiation is one exchange from the first offer to a formed Agreement and its start or
termination. It owns the Anon offer, the Anon decision, the Mare response, the hold during the
exchange, the global lock and the Agreement package. A mare's own offer arrives formed; the act
receives only a handle.

## The exchange

One exchange runs at a time, and each one is either a Mare offer, offered by her side of the mod, or
an Anon offer, taken from the first new player line while Anon is talking to a mare. Both end the
same way: a positive answer with a live scene forms an Agreement, and everything else closes the
exchange. The service samples visibility itself rather than trusting the offer that reached it, so
one authority answers both routes.

An Anon offer captures the pose options it sends and the classifier's answer indexes that captured
list, never a list recomputed afterwards. A clear offer whose index falls outside the captured list
is a refusal with a toast, and an unusable answer is a refusal that names the classifier. A genuine
non-offer is silent on purpose: it reports no outcome, shows no toast and writes no cooldown, so the
proactive pacing never learns about a line that was only conversation.

A Mare offer arrives with her chosen option, her line and the request lease. The service re-checks
Base clearance, takes the lease over, and watches for her answer on the first new line from the
conversation target, so the classifier never races her reply to the same line. A yes runs the same
placement check as the other route and forms the Agreement; an unclear answer is a refusal.

## The two decisions

The Mare response decides a player's offer: a clear acceptance forms the Agreement, a plain refusal
writes the offer cooldown, and a counter-offer writes none and queues one short line declining the
place or the timing while still wanting him. A failed or unclear answer is a refusal with no
cooldown, because nothing was actually declined.

The Anon decision answers a Mare offer: an unclear line is a refusal, a malformed reply is a
failure, and either way the offer cooldown is written only on a real decline. The classifier reads a
fixed sentence describing what she just asked, never the spoken wording, so phrasing cannot decide
the answer.

The live placement check guards every route: whichever way an option was chosen, it is checked
against the live scene before an Agreement can form. A bed that moved or a standing spot that closed
is an interruption, with no Agreement and the hold back.

## The Agreement

The Agreement is the frozen result of a yes: the id and generation, the mare, the option, its
visibility, the pose pair it was checked against, the acceptance time and the life it has left, and
the trigger that formed it. It is built once and never rewritten, and it stays inside the service;
the act only ever holds a handle, whose stale copies are harmless because the id and generation no
longer match.

The readiness read is the one question the offer and the auto-start ask. It answers no unless the
Agreement exists, its handle is valid and it has not expired; a private Agreement whose visibility
is gone is cancelled there through the one close path, with its interruption line, and the read then
answers no. There is no extra flag and no scene row: the scene gate stays the readiness authority.

The offer reports the start's answer back, and every terminal outcome closes the Agreement, releases
the lock and releases the hold unless the act adopted it on a successful start. A start failure is
an ordinary close. A cancel arrives as a typed call rather than a callback inside the handle, so the
handle stays plain data.

## The lock

One exchange at a time includes the time an Agreement waits to start. A live offer or Agreement
blocks a new Mare offer, an Anon offer and a proactive approach; an attempt that still reaches the
service is refused as locked, logged and toasted. The act key is the only break: a press that does
not match the live Agreement exactly ends whatever was live and leaves nothing behind.

## Privacy

Visibility is read once when the exchange forms. A public exchange is never sampled again: that
answer was derived at formation and cannot be lost, so the public case costs nothing while it lives.
A private one is sampled on a slow cadence, and the first sample that says it is no longer private
ends the exchange with the privacy reason, its shared interruption line and no cooldown.

## The hold

A Mare offer's request lease becomes this service's hold; an Anon offer claims its own. A cuddle
offer claims only the attention and affection hold and leaves the cuddle session its own navigator
lease. While the exchange lives, every tick re-asserts the hold and keeps Anon the conversation
target, so the mare does not wander off mid-answer.

A lost hold, a missing ledger or a conversation target outside Anon's surroundings ends the exchange
as the target having left. Every terminal outcome releases the hold, and only a successful start
leaves the adopted hold to the act.

## Feedback and pacing

A refusal, an occupied scene, a lock block and every terminal outcome reach the player as a toast
and the log as one line. The cooldown signal a real decline or an acceptance produces goes to the
proactive pacing as data; the wait itself belongs to that service, and a counter-offer, an expiry,
an interruption and a start failure write none.

A counter-offer's one generated line and a privacy loss's interruption line are queued to the same
dialogue channel, and a line whose mare has already left the tree drops itself. A plain refusal keeps
the game's own dialogue and adds nothing. The exchange, the Agreement and the pending watch live in
memory only, and a world close drops them; no reasoning record is written, and a failed exchange
leaves the proactive service's own history untouched. With **Enable debug** on, the log carries the
exchange's state, the hold claim and loss, a privacy loss, the press result and each outcome; Show
data reports the phase, the lock, the live offer or Agreement and its remaining life.
