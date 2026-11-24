# Anatomy and tail seating

The anatomy service is the optional adult anatomy layer and the tail seat. It is the authority on
which bodies receive the anatomy, how the mesh, material and attached parts are bound and shown,
what the act drives on it, how the worn garment clears it, and where the placement block and tail
seat come from. Eligibility, act readiness, thrust scoring and pose belong to their own services.

## Attachment and identity

The anatomy attaches to an adult identity that has the hip bone and a stable id, including mares
added by other mods; the base-game roster is not a whitelist. It is never the player's own pony. A
provider's adult assertion can override the age flag, and it changes age, not sex. The service asks
eligibility once for its own target and never inspects filly, stallion or provider flags itself.

The stable id prefers the body's relationship metadata and falls back to its identity id;
placement, the per-mare profile and the act history all key off that one value. The presented
body's form supplies the rig and scale, the placement fit, the ownership marker and any source tail
root. A borrowed body uses its own fit while the player's placement override follows the stable id;
a body with no stored form uses the default built from its identity.

A profile that opts out of anatomy releases the anatomy and the tail together and keeps its stored
form, so the rest of her profile survives. The Characters selector asks a different target, with no
participation veto, so an opted-out mare stays editable.

## Visibility

The anatomy mode decides attachment and act visibility. `never` detaches the anatomy, while
`always` shows it whenever the body is presented. `act` keeps it from posing in through the
afterglow and the restore fade, until the act teardown or the world-close release drops the handle.
A far LOD mesh hides the mesh, teats, strip and dock without detaching, so a near/far swap never
rebuilds the attachment.

## Appearance

The material is built per pony from her coat and the tone, height, lip and anal settings; the inner
fold and clitoris colours are separate. Teats are grown from her own belly and skinned with her
weights rather than laid on as a stock part, so they ride her belly and blend into her coat. Their
size is the per-mare Teat size look: Auto keeps the size chosen for her, and a new size shows up the
next time she is spawned. A princess or borrowed body brings its own rear anchor and scale, and
only Celestia has a hand-placed teat look. The skin strip bridges the dock to the teats. The dock
style chooses a copy of the anatomy material, the game's coat material, or no dock; with the
anatomy detached the dock falls back to the coat.

## Act presentation

The act gets one anatomy handle per pony, created by the act start and released by the act teardown
or the world-close release. The handle reads the live pose view and the act stage by reference and
allocates nothing per frame. The shape drive takes the part's girth for the fill and grip, moves the
drive from vulva to anus over an eased hole mix, and lets the mouth contact subtract from both. A
climax adds open/close pulses on top of the grip instead of replacing it, so the lips keep their
shaft hold.

Her own wink runs while the tip rests at her lips or while the stroke is shallow after a climax. It
never runs on top of a climax pulse, the anal drive or the mouth contact, and the idle rest and the
climax pulses share one countdown so two schedulers cannot overlap. A face contact parks the part
once, zeroes the fill and grip and clears the shaft; the first opening tick restores it.

The `V` key asks for the anal target during the active and climax phases, when the holes feature is
on, the contact is neither mouth nor face and the per-mare anal consent holds. The `N` key requests
the standing oral edge when the oral feature, the oral consent and the stretch holder allow. The
input service consumes either key only while the act offers the target, and a refusal is the HUD's
line. A mouth target falls back to the vulva when the contact leaves the mouth, so the key cannot
stay locked out after the oral edge.

Every fluid path is behind the fluid feature. One persistent fluid node serves every act and the
idle discharge. The afterglow tracks the part at her entrance, so penetration reads as zero, and
the act end closes the shape, clears the part and clears the mouth viseme.

## Garment lift

The optional worn-garment bridge samples the anatomy's outer surface as a depth field. That field
describes her closed rest body, not the act: the cloth is normally taken off before an act, and a
player who leaves the undress off may deliberately see the opened or stretched shapes through it.
Every mare shares one field, rebuilt off the frame path, and the adapter updates only the transform
every frame. The lift applies only while the anatomy mesh is shown, so a hidden or far mesh leaves
the cloth alone. The debug heatmap is a separate overlay that copies the live transform.

## Placement and tail seating

Placement is one block: a global default, the player part, and a sparse per-mare override. It
resolves the player's override by stable id, then a provider layer, then the shipped row, then the
global default; only keys that differ from the resolved row are stored. The mesh is placed at the
saved offset with the calibrated lift and mapped through the hip bind. Per-size missionary trims
move only the anatomy mesh, never the body, skeleton or saved placement. The placement actions
write the selected default or pointed mare immediately, and Reset returns the default block or
drops her override.

The tail seat moves every adult mare's hair tail base to the game's reference dock. The game seats
tails itself, so the seat measures the already-seated tail and its offset replaces the game's trim
rather than stacking on it. The tail follows the anatomy decision: a body whose form names a source
tail root returns the tail to its provider, a source-owned tail outside the game skeletons is
placed by its owner and has no dock, and the princesses' fitted bodies have no hair seat. A
placement edit applies live, and the dock is rebuilt once a drag settles so the base-ring snap does
not run per tick.

## Failure and limits

A missing anatomy asset is a broken build, not a runtime state, and a body without the hip bone is
skipped with one debug line. The body-coat patch depends on the game's coat hooks; a game update
that removes them disables the patch, not the anatomy. The coat line needs the pelvis bone and a
hind-leg tip, and a missing tip leaves it straight; it reads the skeleton after the modifiers so
it follows the motions it exists to track. The act's hole, fluid and discharge follow the same line
as the shader, so the shaft tracks the visible opening. The garment field is a rear-facing depth
field, so an undercut it cannot represent is a known limit.

The service owns no base-game import; its scene reads go through the world service, so a base-game
rename stays one accessor change.
