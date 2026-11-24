# Estrus cycle

The estrus service owns the optional mare cycle: which phase a mare is in, her idle wink schedule
and the idle rest it pushes to anatomy. It is off when the cycle feature is off. The act gate reads
the same phase derivation, so the act and the idle animation cannot disagree, and a debug override
is honoured whether the feature is on or off.

## The clock

Her relationship bond day is the clock, not the world clock and not a stored cycle. The phase is
derived from that day and her stable identity, so two mares do not cycle in step and a mare keeps
her dates across sessions. Nothing about the phase is saved.

## The phase

The debug override is read first and wins outright. Without one, the feature switch and a valid
bond day decide; a mare with no relationship runtime, no identity or no bond day is normal. The
phases are heat, diestrus and normal, and the act gate asks the same derivation for its own cycle
row rather than keeping a second answer.

## The schedule

The roster starts a mare's schedule when a body is prepared and stops it when the body leaves. The
phase is polled at its own cadence. When it moves, the idle rest is applied and the wink clock is
reset; in heat the clock calls the wink at the configured gap, sometimes as a small burst, and a
mare leaving heat stops winking and closes the rest. A settings edit re-applies the rest and resets
the clock even when the phase itself did not move.

## Anatomy's part

Anatomy keeps the wink settings and the shapes they drive; estrus decides only when to call the
wink and the rest. With no anatomy link both calls are simply skipped, so the schedule is safe
before the services are wired.

## Settings

The service reads the cycle feature, the wink gap range and the heat rest openness. It snapshots
them when a world starts and again on a settings change, so the schedule follows an edit without a
restart.
