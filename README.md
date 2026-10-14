# barosim

A simulation of a single patient's sudden sensorineural hearing loss (SSNHL). 
Designed to let others to hear what the patient hears.
The distortion is slightly exaggerated at lower LOUDNESS levels, but less exaggerated when LOUDNESS 
is high. The simulation is compiled to one's browser and actively runs on the user's system, e.g.,
there are no modified sound sample files but rather samples played through a processing 
chain in real-time in a browser. Built with SuperCollider, compiled to WebAssembly using SuperSonic.
**Use good headphones.**

**[Try it in your browser →](https://samtorrisi.github.io/barotraumasim/)**

by Salvatore (Sam) Torrisi + Claude Sonnet, July, Aug and Oct 2026

## What you hear

The **right ear** is normal. The **left ear** is damaged. The left's
simulation consists of three layers:

1. **Muffling.** A low-pass filter removes the high frequencies.
2. **Distortion.** The sound is ring-modulated, which makes harsh,
   metallic tones that follow the original sound's profile
   but aren't in tune. There's a layer of random granularity on top, 
   confined to a high band.
3. **Tinnitus.** A steady, faint 4 kHz sine wave. Ignores the loudness slider on purpose: 
   the patient notices it most in a quiet environment.

The **loudness** slider is volume but also scales the sound *before* the filters, 
so it changes how much distortion you get and how much the filter rings. 
For the right ear LOUDNESS is simply volume.

The **response graph** shows the left ear's filter shapes: teal is the
muffling, orange is the distortion band, grey dashed line is the clean right ear.
The graph illustrates shapes only, not levels.

## Project layout

```
barosim
├── index.html
├── LICENSE
├── README.md
├── sounds
│   └── samples
└── synthdefs
    ├── barosimPlayer.scsyndef
    ├── date-param-profiles10.scd
    ├── date-profiles.json
    ├── engine
    ├── index.html
    └── make_synthdef.scd
```

## Settings: `date-profiles.json`

All the numbers that define the damage are there, one entry per assessment
date. The page reads them at startup, sorts oldest to newest, and opens on the
newest.

| Parameter | What it does |
|---|---|
| `cutoff` | where the muffling starts (Hz) |
| `rq` | resonance at that corner; lower rings more |
| `hpfCutoff`, `distortionLpf` | bottom and top edge of the distortion band (Hz) |
| `carrierFreq` | pitch center of the metallic distortion (Hz) |
| `distortionAmt` | overall distortion level |
| `dustDensity`, `dustAmt` | how often crunchy bursts occur, and how strong |
| `dustDecay`, `dustAttack` | how long a burst fades, how softly it starts |
| `envSense`, `envCurve` | how strongly the distortion follows loudness |
| `envAttack`, `envRelease` | how fast that tracking reacts |
| `wobbleRate`, `wobbleDepth` | how fast and how far the distortion's pitch drifts |
| `toneFreq`, `toneAmp` | tinnitus pitch and level |
| `loudnessAmt` | where the loudness slider starts |

Ear, tinnitus on/off, sound choice and output level are controlled by the page,
not the file. Keep every entry complete: anything left out is inherited from
the *oldest* entry, so retuning that one would silently change the others.
`lpfOrder` (number of filters in a row) is only listed so the graph matches the synth.

## Changing the sound parameters if patient documents a new assessment of their perception

1. The purpose of a new assessment is to document potential healing across time.
2. In the SuperCollider IDE, run `date-param-profiles10.scd`, which
   boots the server and opens a GUI of sliders, starting from the
   **newest** snapshot. The "Start from snapshot" menu loads any older one, 
   so you can compare them by ear.
3. Adjust sliders until they matche how the patient now hears. Sliders in
   the "advanced" panel are probably optional.
4. Check the date field (defaults to today) and click **export JSON entry**.
   A complete entry is printed in the post window and, on a Mac, copied to
   the clipboard.
5. Paste it into the `dates` list in `date-profiles.json` (add a comma after
   the previous entry), save, and reload the page. No recompiling make_synthdef.scd.

Audio output follows the macOS default device (wired headphones). For Bluetooth,
set `~bluetoothDevice` near the top of the file, then `s.quit` and re-run.

## Changing the sound design itself

If you change the simulation's *structure* (new controls, different filters)
you do need to recompile:

1. Edit the signal chain in `make_synthdef.scd` **and** make the same change in
   `date-param-profiles10.scd`. The two must stay yoked or you'll tune
   something the webpage doesn't play.
2. Run `make_synthdef.scd` which will compile `barosimPlayer.scsyndef`

## To run this locally (testing)

From the project root, at the command line:
```
python3 -m http.server 8000
```
Then point a browser to `http://localhost:8000/synthdefs/`. If it says the port is
in use, try another number like 8001. If edits don't show, hard-reload (Cmd+Shift+R)
or use a private window; the plain server lets browsers cache files. 
Tested in Firefox, Chrome, Safari and iOS on Mac and Windows.

## Limitations

- **No output limiter.** Loud material plus the filter's resonance can clip on
  headphones. Keep loudness moderate; adding a limiter is recommended.

- **Not perfectly realistic.** This is essentially a cartoon of what the patient
  actually experiences. There are many subtleties, in both the quality of the 
  distortion, the tinnitus, and how both behave in various contexts that can't be
  captured here. The purpose, therefore, is illustrative and educational.

## About SuperCollider and SuperSonic

[SuperCollider](https://supercollider.github.io) is an environment and audio programming language 
originally released in 1996 for real-time audio synthesis and algorithmic composition. It has
evolved into a system used and further developed by both scientists and artists working with sound.
[SuperSonic](https://github.com/samaaron/supersonic) is Sam Aaron's port of SuperCollider's 
`scsynth` to a Web AudioWorklet, so synths compiled in the desktop IDE run as-is. 
It is alpha software and changes quickly.
