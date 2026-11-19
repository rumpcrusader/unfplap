extends RefCounted
## The act state machine's one definition. The runtime owns the live state; every consumer reads
## these names instead of copying the numeric values. Pure data: no scene, no service.

enum State { IDLE, POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, RESTORE }

const STATE_IDLE := State.IDLE
const STATE_POSING_IN := State.POSING_IN
const STATE_ACTIVE := State.ACTIVE
const STATE_CLIMAX := State.CLIMAX
const STATE_AFTERGLOW := State.AFTERGLOW
const STATE_RESTORE := State.RESTORE


## True while an act is live: from the start pose until the afterglow has ended.
static func is_live(value: int) -> bool:
	return value == State.POSING_IN or value == State.ACTIVE or value == State.CLIMAX \
		or value == State.AFTERGLOW


## True while the runtime presents the pony; only the teardown is excluded.
static func is_presenting(value: int) -> bool:
	return value != State.RESTORE
