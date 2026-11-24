# Mod integrations

The integrations service is the optional bridge to other installed mods. It presents another mod's
reactions through the act without changing that mod, lists every supported integration in its own
settings tab whether or not the other mod is installed, and owns the shipped body-change provider
for the changelings pack.

## Catalog and tab

The catalog is the single source for both the tab and the adapter: a mod's identity, the version it
was verified with, its feature names and its binding paths. A verified version says what the
adapter was tested with, not a compatibility promise; the tab reports neither the installed version
nor a mismatch. Each section is collapsible under an Experimental notice, and the tab's one Debug
block carries the garment field rows.

## Provider model

The per-pony adapter owns the per-act state: it resolves the catalog bindings at act start,
rechecks a required one each tick, leaves an optional one pending until it appears, saves every
original value before its first write and restores in reverse on stop, feature-off, a missing
required binding, a failed start, the act end or a reset. A provider owns only policy: whether it
applies and which properties it wants set. It never reads a node, a tree, the clock, the filesystem,
the settings file or a runtime's private fields.

A provider that needs the shared excitement Beat hold asks the adapter for it. The hold is
refcounted by owner, so the kiss and a provider can hold it together and only the last release
restores the original pause; no provider writes the Beat itself.

## Kissing

The kiss provider keeps the other mod's build-up under act control and suppresses the game's own
burst excitement. At start it clears the pending excitement, takes the shared hold and suppresses
the optional fidgets. Below the close band the target level is zero. Once she is close and a real
stroke landed inside the grace, the target ramps with readiness toward a cap read from her own
stage, and the provider eases her level toward it. When the player stops stroking the target falls
and the level fades. The held cause stays only while the level is above rest, and the afterglow
lets the other mod's own hold and fade run. A climax pins the target at the cap, so the reaction
stays fully active for her bond even while the player keeps thrusting. An Affection kiss keeps its
own cause, and act control resumes after it.

The optional fidgets stay suppressed through the act because they move the skeleton root or lift a
planted hoof; her climax restores them for its duration and they are suppressed again afterwards.
The horn, wing and earth-pony tail/ear families are the reactions in scope, and the act's own wing
controller creates the open-wing node the shiver needs.

## Pantyhose and Panties

The garment module is world-side: it lifts a worn piece over the anatomy and carries the coat's own
rump wobble into the cloth. The lift samples a shared depth field of the anatomy at rest. The field
covers the closed body only, so a player who keeps the undress off during an act can see the opened
shapes through the cloth; normally the piece is gone by then. The adapter updates the hull
transform and every per-node uniform each frame, re-discovers the worn nodes on a slower fallback,
and overrides only the worn node, so two mares never share a transform. When neither the lift nor
the wobble needs the copied shader, the original material comes back.

Cloth jiggle follows the game's own wobble rather than running a second simulator. It reads the
live field from the first reference pair that carries one and whose mesh is visible, otherwise from
the game body, otherwise from the first pair with a live field. A missing field, a hidden mesh or a
non-positive amount leaves the cloth rigid with its lift. The copied shaders run the coat's own
spring, ripple and vertical bob on the cloth after the lift, and the bob follows the body's up
rather than a trimmed piece's own axis. The six per-node jiggle uniforms and the ten hull uniforms
fill the shader's instance-uniform budget exactly, so a new per-node value has to be packed into an
existing one.

At act start the module reads what she wears from the pack and sends the game's own take-off action
through the director, falling back to the wardrobe calls when that path is unavailable. She stays
undressed afterwards: the adapter restores nothing at the act end. A missing wardrobe, pony id or
worn piece is a quiet no-op, a renamed pack shader is left alone and logged once, and the pack is
never edited.

## Queen Chrysalis

The changelings module is a body-change provider for the pack's queen. It registers one provider
layer with her profile and placement, without a settings row or a tab section, and reports her as
an installed mare so the Characters selector can show her even while she is away. Her own body gets
a princess-profile fit, the pack's ownership marker and the spring tail chain; a disguise borrows
the copied pony's fit and keeps the marker. The marker matters because her hide pass removes every
mesh that lacks it, and the anatomy's visibility poll stores the hidden state, so nothing re-shows
it later. A source-owned tail is wrapped by the adapter and moved by the resolved tail offset,
while the act modifiers rotate and restore the chain inside the wrapper.

The provider observes the pack's own state at its cadence and pushes a change; the base service
never polls. It captures the old body before the pack moves it, so an act can suspend on the body
it knows, and it re-prepares the new body once the shape is known. A young or male shape never
resumes the act. Her own change keeps the player's offer pending, and only a shape the player names
spends it. The reveal policy offers after a climax in her own form while no offer is pending, and
the requested reveal supplies the peak and the memory mark.

Her player words are text rules: a line selects a shape only when it is a whole name or carries an
imperative request, and any negation in the line beats the request phrase. A name mentioned inside
ordinary talk, a negated line and a description select nothing. The adapter refuses the shape she
already wears, herself, an ambiguous tie and a body it cannot copy, and answers a short note for
those; ordinary talk gets no note.

## Failure

An absent pack, a renamed node or a missing field is a quiet no-op, so a pack update cannot crash
the integration. The compatibility shaders are a pinned copy of the verified pack look; a changed
or renamed pack shader is left alone. The module never edits the pack and needs no new signal or
rebuilt pack.
