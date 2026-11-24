# Conversation director

The director service is the mod's one bridge to the game's conversation director: the quiet gate the
automatic scan asks, the authored greeting and queued lines, the situation records and the
player-line baselines and watches. It owns no prompt text and no request schema, and the model
transport belongs to the classifier service.

## The quiet gate

The gate answers whether the automatic scan may begin now and, when it may not, gives a stable
reason name. It asks the game's own state rather than a mod setting: pause, menu and mouse state,
whether the player is free, whether the director is idle and clear of an approach, a group exchange
or a hearing, and finally the game's own background-AI policy and its recent-chat window. A closed
gate is a named reason, never a bare no.

The reason order is the gate's order, and the reason names are the request scan's stable log words.

## The watches

The answer watch is one at a time: a watch starts by recording the director's player-line baselines,
and a scope cancel drops it. The baseline is what makes an old line left in place not an answer; a
transcript signal is read first, and a field that changed from the baseline answers too.

The offer watch belongs to the negotiation, which arms and disarms it around the field. It captures
the first new line the player says while he addresses her, holding it until the director is idle
again so her reply to that line cannot read as a new ask.

## The lines

A greeting opens one authored line, and a queued line carries its purpose, its key and a validity
rule. The queue asks that rule again when the line finally delivers, so a line whose moment has
passed drops instead of speaking. A situation record is one replaceable event in the director's
world context. The service neither writes the model prompt nor parses the reply.

## Lifecycle

Nothing is persisted. The transcript hook, the watches, the pending line and the baselines live for
one world: a world close drops them before the director node is freed, and a world enter hooks the
new director.

## Debug

The gate's reason names are the request scan's stable debug reasons, so a blocked scan logs one line
rather than a stream.
