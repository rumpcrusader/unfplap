# Outside-act smack

The outside-act smack service owns the pack sound of the game's own flank smack outside an act, and
the handoff of that sound player to the act and back. It reads only the pony nodes the roster hands
it and the `pack_smack_sound` setting through the settings service, and it does no per-frame work.

## A stream swap

The pack layer is a stream swap on the game's own flank-smack player, never a second player. That
keeps the native impact intact: the decal, the blush, the jiggle and her reaction all stay on the
same play call, and the pack variants ride that call instead of competing with it.

Only a pony with that player is touched; a pony without it is ignored, and a restored player gets
put back exactly as it was.

## The variant bag

The pack variants sit behind one no-repeat randomizer, so the next slap is not the same sample as
the last. The player's own pitch stays neutral, leaving the randomizer's built-in variation as the
only shift the ear hears; the act's hand-smack level stays a separate thing.

## Restore and handoff

Before the first swap the service saves the player's stream, level and pitch, and every restore puts
exactly those values back rather than the shipped defaults. A switch-off, an act start or a world
close is enough to restore it.

An act pony is skipped: the act start gives her stock player back so the hands' own per-impact swap
owns it, and the act end reinstalls the pack layer after the hands restore. An act pony therefore
never carries two layers at once.

## The switch and the roster

The service remembers a pony seen while the switch is off, so turning the switch on reaches every
pony already loaded. The setting is live and the service follows the settings change notification
itself, so the entry installs no settings path.

A world close puts every stock player back and forgets its ponies; the loaded pack streams stay for
the next world.

## Extension

A second outside-act cue family joins the same saved-and-restored player record rather than adding a
second listener, and a new pack variant is another catalogue row.
