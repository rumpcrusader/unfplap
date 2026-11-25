# Settings

The settings service is the one authority for global settings: their declarations, shipped
defaults, typed accessors, the player files and their schema, the settings page and the one change
notification every edit produces. It also owns the file and the generic storage behind per-mare
profiles; the meaning of a consent or participation value belongs to the system that reads it.

## The shipped and player split

The shipped settings document is the only source of a declared default. The shipped characters
document is content rather than settings: the global profile a mare starts from, the shipped
per-mare profiles and the placement rows. Prompts are shipped content too and never part of a
player file. The player keeps a settings document holding the declared values, the section state
and the player placement rows, and a characters document holding profile differences, per-mare
overrides and placement rows; the characters file is absent while the player has no character data.
A player value wins over the shipped value, and an absent player key is filled from the default.

## Declarations and accessors

A declaration owns the dotted path, label, help, tab, group, bounds or options and the debug flag;
its value lives only in the shipped document. The accessor is typed, so a wrong getter or a
mistyped name fails at parse time. A player-facing number clamps to its declared bounds. A debug
number is stored and returned verbatim, and its range only shapes the spin box. A choice or list
validates its members instead of clamping, and a non-finite number falls back to the shipped
default. One declaration, one shipped value and one typed read are the whole setting; a service
carries no private default, no table copy and no cache. A service reads its typed handle at use,
hot or cold; there is no per-act settings snapshot and no per-service cache. The act's reaction,
camera and dialogue configs are built once at the act start from the same typed handles because
those services hold state; every feature, presentation and act value is read where it is used.

## Panels

The panel order is General, Anatomy, Poses, World, Characters and Integrations. A declaration's
position in the catalogue is its position on the page, and a section starts where it first appears.
Poses is injected after Anatomy and is always present: its player rows are the oral and anal
enables, and its tuning rows live in its Debug block. Turning on Enable debug adds one collapsed
Debug section at the end of a tab, keeping the same group names. The Anatomy rows dim while the
anatomy pill is Never. The act key is a hidden physical-key setting drawn by hand because a key
capture is not one of the generic widgets. Each section remembers its open state by tab and group.

## Characters

The Characters form edits one mare's profile: her preferences, consent and participation, plus her
Teat size look. Auto keeps the size chosen for her, and a new size shows up the next time she is
spawned, because it is a look rather than a scoring axis. The form uses the game's own picker and
lists installed off-roster mares under Other mares. Edits stage until Save preset, and Reset to
default returns her to her provider or shipped template. Only differences from the resolved profile
are stored, so a later template or provider update still reaches a mare the player has not edited.
Participation is subtractive, and the character list asks a target with no veto, so an opted-out
mare stays selectable.

## Change notification

Every edit ends in one pass, and that pass is the only way a change reaches a service. The mod
channel calls its listeners in registration order; the game's own settings channel is separate and
carries the key that changed. A callable registered twice keeps one place, a released listener is
dropped, and a listener removed during the pass is not called in that pass. A provider layer and a
settled body change notify the same mod channel. The entry never relays a change itself.

## Persistence and migration

Loading reads both player files once, migrates them, merges the result over the defaults and writes
the pair back, so every declared setting ends up in the player's file the first time. Changing a
shipped default therefore reaches only a new player: the existing one keeps their saved choice, and
folding that choice into the shipped document is a deliberate promotion.

A file that cannot be read, is empty, is not an object or carries a newer schema is preserved with
an invalid suffix and replaced from the shipped defaults, and the two files are checked separately,
so a bad characters file never discards the settings file. A schema-10 file is split into the
settings and characters documents, and a characters file that is already present wins over copies
in the settings file. Anything older than that split keeps its retired keys, which this build
ignores; the missing declarations take their shipped defaults and that loss is accepted. Retired
keys are erased on load, and a retired setting declares the replacement it maps onto.

A write rebuilds both documents from one in-memory view. The pair is not atomic: a failed write
leaves the edit live in memory but unsaved and logs both the path and the errors. Hand editing is
unsupported; the invalid copy is the recovery path.

## Profiles and consent

The default profile resolves the shipped default, then provider layers, then the player's saved
differences. A per-mare profile resolves the same way over her own template, which is why removing
an override returns her to the shipped profile. Identity facts and the resolved consent block are
memoised per settings generation and provider revision, so a scan pays a lookup instead of building
a template; consent is handed out as a detached copy. A provider can assert a pony's eligibility,
and that assertion is never a player value. The player's saved block is a sparse difference, and a
clear returns to the provider's default without touching the assertion.

## Invalid shipped data

A shipped document that cannot be used at all is fatal to the load: one problem is logged, the
loaders answer an empty document, no write runs and the entry installs no hooks; the game keeps
running. The schema check enforces the declared path set, each JSON type, option membership and the
player-facing bounds, never a value. An accessor is never named after an engine built-in, because a
preloaded script constant would resolve the built-in instead.

## Extending a setting

A setting is contributed from the service that owns its behaviour: one declaration where the
player should see it, one value in the shipped document, one typed read at the use site. A setting
whose value is not one of the generic widgets is declared hidden and drawn by hand. A rule table or
constant set that repeats setting values is a default copy too; build it from the declared handles
where it is used. A value that must stay playable gets a declared bound and a help line saying why,
never a consumer-side clamp.
