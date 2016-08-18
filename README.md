## FT-Misc-Utils

A collection of (almost) all the miscellaneous Lua scripts I wrote for various FamiTracker / 0CC-FamiTracker utilities.

Some of the scripts will only run on Lua 5.3. Most of them are originally for personal use only, and may differ largely in style; in particular do not expect any comments or help text in them.

### Generator

Scripts that generate new files.

- `dpcm_mixer`: Creates a new DPCM sample from the sum of two DPCM samples.
- `ft_nsf2gbs`: Converts any one-channel N163 NSF exported from FamiTracker 0.4.6 or 0CC-FamiTracker 0.3.13 into a GBS Game Boy sound file. Assembly source of the NSF driver's GB-Z80 port not included.
- `lognsf`: Records the register writes of all tracks of a given NSF, then reports the access history of all used data values in the NSF.
- `organ`: Generates drawbar organ instruments for the N163.
- `raw2fti`: Converts a raw unsigned 8-bit mono PCM stream into N163 instruments without resampling.
- `wavegen`: N163 instrument sampler for loopable WAV files.

### Info

Scripts that only display technical information and do not process files.

- `bpm_custom`: Approximates a given BPM value with a groove, that does not exceed a given size or fits into a pattern evenly.
- `bpm_default`: Represents a module's BPM configuration as a ticks-per-row sequence.
- `bpm_dyadic`: Approximates a given BPM value with a groove, where each first half of the groove sequence is at least as long as the second half, to simplify Gxx use.
- `dpcm_loop`: For a given frequency and machine setting, finds the number of WAV samples and the number of wave cycles required to produce a looped DPCM sample at the same pitch.
- `groove_scaler`: Converts a groove sequence from one refresh rate to another.
- `lfo`: Generates instrument sequences that emulate the 4xy and 7xy effects.
- `safe_4xy`: Calculates the Pxx detune values required near certain notes on the 2A03 such that applying a 4xy vibrato over them will not cause a phase reset.
- `stable_bpm`: Lists all integer refresh rates under 1000 such that the FamiTracker 0.5.0 NSF driver may produce stable BPM values.
- `stable_refresh`: For a given tempo and speed setting, finds all possible NSF refresh intervals such that the resulting BPM generates the same number of ticks on each row.
- `tuplet`: Calculates the delay effects required for tuplets in any tempo or groove setting.
- `vol_factor`: Given a number of 16-step instrument volume sequences, attempts to find a single sequence that can produce all of them under different channel volumes.

### Modules

Scripts that read or write 0CC or FTM modules. They require [this](https://github.com/HertzDevil/luaFTM) fairly incomplete Lua library I made.

- `0cc_0xy`: Converts instruments using arpeggio schemes into individual instruments and arpeggio sequences. The actual 0xy commands themselves are unaffected.
- `0cc_inst`: Clones instruments as necessary such that each channel only uses instruments for the sound chip it belongs to.
- `0cc_Lxx`: Converts delayed note release effect commands into note releases plus Gxx commands.
- `ftm2mid`: Converts a module into a standard MIDI file, translating most effect commands into MIDI equivalents.
- `n163check`: Scans through the songs of a given module and reports all unique combinations of simultaneously used N163 instruments.
- `obfusc`: Shuffles all the rows of a given module, while placing Dxx commands throughout the module to maintain the row ordering.

All these scripts are licensed with the MIT License where unspecified otherwise.