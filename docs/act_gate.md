# Act gate

The act gate is the dynamic half of the permission question and the one authority on whether this
mare may act right now. It takes the permanent identity answer from `eligibility`, leaves the live scene to
`scene_gate`, and owns everything in between: the relationship and romance read, the Promiscuity
floor, the cycle, her willingness, her act history, her per-mare consent and the heat note the
dialogue prompt appends. A consumer asks it for a capability or for the typed verdict; nothing else
answers these questions.

It stores no verdict and no setting, and never writes the game, the settings or the act history;
its only state is a per-body warm mark that the world clears.

## What an answer is made of

Every fact is read from its owner when the question is asked, so a changed bond, a settings edit or
a body that stopped being eligible shows up on the next ask; nothing is cached between calls. The
answer is a snapshot, and the verdict built from it is rebuilt each time.

## Base clearance

Base clearance is the relationship row: a live relationship runtime, romance eligibility, and the
Promiscuity floor the player picked. It deliberately ignores willingness, her history, the cycle,
the player's form and consent, and that narrow read is what lets the idle hint re-run it on every
pass without rebuilding her bond facts. The love level comes from the game's own ladder cache,
falling back to its ladder for a pony it has not recorded yet. The row cannot see a player-form
change, so romance eligibility is read live and gates it first: a young player still fails.

The act key is that identity act target plus Base clearance, and a cleared service answers no to
every question.

## The verdict

The typed verdict is the fuller answer: a recorded mode, every fact, the per-action consent flags,
the relationship values the reasoning reads, the rows and their effects, and the two policy hints.
`show` is the start hint and `offer` the proactive offer, with the offer weight beside it. Every
field is computed on every call and the mode only records which question was asked; the live routes
use the act key and Base clearance, while the hints and the weight belong to the pure policy behind
the debug line and the reasoning.

Every row carries a reason and an effect, and the reason names the fact that failed. A block refuses
a start and an offer, a refusal fails the policy's willingness row, a history refusal and an offer
block report what her history suppresses, and the public flag is reported without ever failing.

## The Promiscuity floor

The selected floor is the lowest love level that can start an act: a stranger, a crush, a new
couple, a marefriend, head over hooves, or soulmates. `Any Adult` removes only this floor;
adulthood, the relationship runtime and romance eligibility still apply. An unknown value falls
back to the marefriend tier rather than opening the gate.

## Willingness, history and refusal

The game's own kiss willingness is the authority; the gate does not reimplement it. The act-history
store owns the points and tiers behind the history rows. What those rows mean here is narrow: a
withdrawn or hurt tier and an active stop silence the proactive offer and the offer weight, and
they colour what the reasoning is told, but they never refuse the player's press on a live route.
The physical refusal belongs to the act's own consent stop.

Participation is a boundary rather than a mood: a player who opts out of acts never produces an
offer, and the gate reports it as a block so no other system invents a different reason.

## Per-mare consent

Consent is resolved per mare from the shared defaults, a provider layer and the player's
differences, and the gate only reads it. The keys are independent: public is a soft signal for the
reasoning and never gates an act or overrides offer privacy, while anal and oral gate their action
keys. The anatomy feature switches are capability gates, not consent.

## The cycle

The cycle note appends the heat or diestrus line to the normal dialogue prompt, inside or outside
an act, and stays empty where the base would stay shut. The phase is the shared derivation the
estrus service also reads, so the two cannot disagree; the debug Force/Clear actions feed that
override without bypassing any gate.

## Debug and settings

The runtime's debug line prints this verdict rather than re-deriving it, and the trigger-offer
debug actions go through the same service. The gate declares no setting: it reads the Promiscuity
floor and the estrus switch through their owner.
