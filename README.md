A directory of all the miscellaneous Lua scripts I wrote for various FamiTracker / 0CC-FamiTracker utilities.

Some of the scripts will only run on Lua 5.3. Most of them are originally for personal use only, and may differ largely in style; in particular do not expect any comments or help text in them.

### Generator

Scripts that generate new files for use in the tracker.


- `bpm_custom`: Approximates a given BPM value with a groove, that does not exceed a given size or fits into a pattern evenly.
- `bpm_default`: Represents a module's BPM configuration as a ticks-per-row sequence.
- `bpm_dyadic`: Approximates a given BPM value with a groove, where each first half of the groove sequence is at least as long as the second half, to simplify Gxx use.
- `dpcm_mixer`: Creates a new DPCM sample from the sum of two DPCM samples.
- `organ`: Generates drawbar organ instruments for the N163.
- `raw2fti`: Converts a raw unsigned 8-bit mono PCM stream into N163 instruments without resampling.
- `wavegen`: N163 instrument sampler for loopable WAV files.

### Info

Scripts that only display technical information and do not process files.

- `dpcm_loop`: For a given frequency and machine setting, finds the number of WAV samples and the number of wave cycles required to produce a looped DPCM sample at the same pitch.
- `lfo`: Generates instrument sequences that emulate the 4xy and 7xy effects.
- `tuplet`: Calculates the delay effects required for tuplets in any tempo or groove setting.
- `vol_factor`: Given a number of 16-step instrument volume sequences, attempts to find a single sequence that can produce all of them under different channel volumes.

### Modules

Scripts that read or write 0CC or FTM modules. They require [this](https://github.com/HertzDevil/luaFTM) fairly incomplete Lua library I made.

- `0cc_0xy`: Converts instruments using arpeggio schemes into individual instruments and arpeggio sequences. The actual 0xy commands themselves are unaffected.
- `0cc_inst`: Clones instruments as necessary such that each channel only uses instruments for the sound chip it belongs to.
- `0cc_Lxx`: Converts delayed note release effect commands into note releases plus Gxx commands.
- `ftm2mid`: Converts a module into a standard MIDI file, translating most effect commands into MIDI equivalents.
- `n163check`: Scans through the songs of a given module and reports all unique combinations of simultaneously used N163 instruments.
- `obfusc`: Shuffles all the rows of a given module, and places Dxx effects throughout the module so that thw rows will play in the correct order nonetheless.

All these scripts are licensed with the MIT License where unspecified otherwise.