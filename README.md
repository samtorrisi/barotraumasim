# barosim

A simulation of a single patient's hearing damage.
Designed to let others to hear what the patient hears.
Built on SuperCollider's engine, compiled to WebAssembly 
by [SuperSonic].
**Use good headphones.**

**[Try it in your browser →](https://samtorrisi.github.io/barotraumasim/)**

by Salvatore (Sam) Torrisi + Claude Sonnet, July, Aug and Oct 2026

## What you hear

The **right ear is normal**. The **left ear** is damaged. The left's
simulation consists of three layers:

1. **Muffling.** A low-pass filter (three in a row for a steep drop) removes
   the high frequencies.
2. **Distortion.** The sound is ring-modulated (multiplied by a ~9 kHz sine),
   which makes harsh, metallic tones that follow the original sound's
   rhythm but aren't in tune with it. Random crunchy bursts add granularity on top, 
   and the result is confined to a high band.
3. **Tinnitus.** A steady, faint 4 kHz sine. It ignores the
   loudness slider on purpose: the patient notices it when all else is quiet.

The **loudness** slider is volume but also scales the sound *before* the filters, 
so it changes how much distortion you get and how much the filter rings. 
For the right ear it's simply volume.

The **response graph** shows the left ear's filter shapes: teal is the
muffling, orange is the distortion band, grey dashed line is the clean right ear.
It shows shape only, not level; the distortion's quieter than its curve suggests.

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
    ├── date-param-profiles9.scd
    ├── date-profiles.json
    ├── engine
    ├── index.html
    └── make_synthdef.scd
```

`index.html` sits in `synthdefs/`, so its paths are `./` (synth, engine, JSON)
and `../sounds/samples/` (audio).

## Settings: `date-profiles.json`

All the numbers that define the damage are there, one entry per assessment
date. The page reads them at startup, sorts oldest to newest, and opens on the
newest. Switching dates restarts playback with that date's sound.

```json
{ "value": "2026-10-04", "label": "Oct 4, 2026", "params": { "cutoff": 2886, "rq": 0.90, ... } }
```

| Parameter | What it does |
|---|---|
| `cutoff` | where the muffling starts (Hz) |
| `rq` | resonance at that corner; lower rings more |
| `hpfCutoff`, `distortionLpf` | bottom and top edge of the distortion band (Hz) |
| `carrierFreq` | pitch center of the metallic distortion (Hz) |
| `distortionAmt` | overall distortion level |
| `dustDensity`, `dustAmt` | how often the crunchy bursts occur, how strong they are |
| `dustDecay`, `dustAttack` | how long a burst fades, how softly it starts |
| `envSense`, `envCurve` | how strongly the distortion follows loudness |
| `envAttack`, `envRelease` | how fast that tracking reacts |
| `wobbleRate`, `wobbleDepth` | how fast and how far the distortion's pitch drifts |
| `toneFreq`, `toneAmp` | tinnitus pitch and level |
| `loudnessAmt` | where the loudness slider starts (the slider shows half this value, so 0.5 reads as 0.25) |

Ear, tinnitus on/off, sound choice and output level are controlled by the page,
not the file. Keep every entry complete: anything left out is inherited from
the *oldest* entry, so retuning that one would silently change the others.
`lpfOrder` (number of filters in a row) is only listed so the graph matches the synth.

## Workflow: when patient wants a new assessment: use date-param-profiles9.scd

0. The purpose of a new assessment is to document potential healing across time.
1. In the SuperCollider IDE, open `date-param-profiles9.scd` and run it.
   It boots the server and opens a GUI of sliders, starting from the
   **newest** snapshot. The "Start from snapshot" menu loads any older one, 
   so you can compare them by ear.
2. Adjust the sliders until it matches how the patient hears now. Sliders in
   the "advanced" panel can usually stay put.
3. Check the date field (defaults to today) and click **export JSON entry**.
   A complete entry is printed in the post window and, on a Mac, copied to
   the clipboard.
4. Paste it into the `dates` list in `date-profiles.json` (add a comma after
   the previous entry), save, and reload the page. No recompiling make_synthdef.scd.

Audio output follows the macOS default device (wired headphones). For Bluetooth,
set `~bluetoothDevice` near the top of the file, then `s.quit` and re-run.

## Changing the sound design itself

If you change the simulation's *structure* (new controls, different filters)
you do need to recompile:

1. Edit the signal chain in `make_synthdef.scd` **and** make the same change in
   `date-param-profiles9.scd`. The two must stay yoked, or you'll tune
   something the webpage doesn't play!
2. Run `make_synthdef.scd` from `synthdefs/` which will compile `barosimPlayer.scsyndef`
3. `lpfOrder` is fixed at compile time. If you change it, update it in all
   three places: `make_synthdef.scd`, the tuning GUI (`~lpfOrder`), and
   `date-profiles.json`.

## To run it locally (e.g. testing)

From the project root:
```
python3 -m http.server 8000
```
Then point a browser to `http://localhost:8000/synthdefs/`. If it says the port is
in use, try something like 8001. If edits don't show, hard-reload (Cmd+Shift+R) or use
a private window; the plain server lets browsers cache files. Tested in Firefox,
Chrome, Safari and iOS.

## Known issues

- **No output limiter.** Loud material plus the filter's resonance can clip on
  headphones. Keep loudness moderate; adding a limiter is recommended.

## About SuperSonic

[SuperSonic](https://github.com/samaaron/supersonic) is Sam Aaron's
(Sonic Pi, Overtone) port of `scsynth` to a Web AudioWorklet, with full OSC
compatibility, so synths compiled in the desktop IDE run as-is. It is 
alpha software and changes quickly.
