# VGM2SNM

**VGM2SNM** is a VGM sound file to SnevenTracker module converter written in Ruby. Currently only one SN76489 sound chip is supported.

The converter operates by accumulating register writes at the given refresh rate, and outputting appropriate note events to the module at the _end_ of each tick. In practice VGM rips (not generated VGMs) are rarely frame-accurate (by using `vgm_facc` for example), and may contain many sub-frame delays making clean SNM logs impossible.
