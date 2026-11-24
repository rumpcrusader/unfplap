# Debug actions

The debug service is the process-wide table of debug operations: the labels every surface shows, the
gates that hide an action, and the dispatch a Debug block button or an action-wheel slot runs. A
debug action is a one-off command, never a stored preference. It owns no node and runs nothing
itself; the executor publishes itself to the table and every read resolves it there.

## The table

One entry describes one operation: its label and help, the method that runs it, the settings tab and
row it joins, whether the settings block draws it, its compact wheel label and, where the label
follows the aimed mare's phase, its second wording. Entries that share a row must stay adjacent.

A wheel-only action is marked so the settings block skips it, which keeps the wheel as its only
trigger; such actions are desktop-only. A runtime gate hides an action on every surface, the wheel
included, and a closed gate is a hidden button rather than a dead one. The wheel's pages are part of
the table as well, and the live act chooses between the act page and the mare page.

A full label falls back to the entry's label, and so does the compact one. When an entry names a
phase and the target reports that phase, the entry's second wording replaces it, so one slot can
read Force or Clear without a second entry.

## Dispatch

Dispatch resolves its target first, then calls the entry's method and returns its message, or the
empty string when the action cannot run. A button or slot with no executor is a no-op, and a freed
executor leaves no dispatch behind.

The wheel's open gate is one decision over the frame's facts: debug on, a desktop build, a live
world, an unpaused tree, the desktop view, a focused window, a captured cursor, no open menu, no
text focus and the left button up. A headless display, a pause, a free mouse or a typing caret each
close it on its own, and every caller reads that one decision rather than re-deriving it.

## No hotkeys, and the console

The table declares no global hotkey. A Debug block button or a wheel slot is the only trigger, which
leaves the game's own developer keys usable while the mod is loaded; a declared hotkey remains
possible for an action that genuinely has to fire while the world is unpaused.

The console is the game's own: the developer flag gates it, a player build opens that flag by
pressing Settings > Updates several times, and an act's control lock keeps it shut while an act
runs.

## Logging and the perf panel

Enable debug controls logging and the detailed overlays, not the HUD. Every line, including the rows
of a multi-line block, carries the mod's prefix; one sink adds it, so no other module prints its own
way.

Print perf logs is a separate switch and needs Enable debug too. With both on, the profiler prints
one window a second and the corner panel shows the same tree as it printed, every row coloured
against its own target so a red cell is the place to look first. A permanent first row gives the
mod's whole cost in one line and keeps the window's worst single call, and the caption carries the
engine frame numbers and the measured refresh rate once a second window exists. The panel ignores
the mouse and never blocks the act view or the wheel.

Either switch off hides the panel, and the next window redraws the same node.
