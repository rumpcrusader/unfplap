# Automatic thrust

The auto-thrust service owns the automatic stroke as a machine the act drives: the band, the pace,
the waveform and the hold-X layer. It generates the movement a mouse would, and the act feeds that
movement into the same stroke tracker, so scoring, intensity, pattern, audio and the body follow the
manual rules without a second path. Nothing in the service is about her; the act hands it the
current depth where it needs one.

## The stroke machine

The band is a bottom and a peak share of his reach, the pace is thrusts per second and the shape is
the waveform the cycle follows. The band stays wide enough for a stroke to clear the tracker's
reversal gap and for the smallest peak to reach a thrust's travel, so nothing generated is too
shallow to count. Every shape starts and ends at the bottom, so the tracker only ever sees depth.
Turning it on picks the cycle up at the depth of the hand, and the peak is lifted when the band sits
shallower than that.

## Controls

A tap of X starts and stops the machine; the mouse wheel sets its pace while it runs, and the mouse
otherwise does nothing. Holding X opens a small layer for the band, the pace and the shape; that
layer applies its own adjustments: the top row adds, the home row subtracts, in the order the HUD
shows. The shape key steps to the next waveform and writes it to the settings, so an experiment
survives the act. Releasing X keeps the layer for a short grace, and a press that ever opened the
layer never toggles the machine on release.

## The act's lifetime

A fresh act starts from the settings: the starting pace, both band ends and the shape. The service
reads those values at the act start and nowhere else, so an edit during an act reaches the next one
rather than the running stroke. A body swap stops the stroke and keeps the live band, pace and shape;
the resume restarts it at the hand's depth, and a fresh act starts over from the settings.
