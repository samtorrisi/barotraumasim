// ---------------------------------------------------------------
// make_synthdef.scd
//
// Run in the SuperCollider IDE to compile + save barosimPlayer.scsyndef.
// SuperSonic loads that file in the browser, without need to boot the server.
// For barotrauma simulation project, ST 2026.
//
// MATCHES date-param-profiles10.scd (the tuning GUI): same graph, same
// args, and the arg defaults below are the values tuned there. If you
// change the DSP graph in one file, mirror the change in the other.
//
// The browser (index.html) also sends these values from
// date-profiles.json at note-on, so the defaults below only matter as
// a fallback for any arg a date profile leaves out.
// ---------------------------------------------------------------

(
// Write next to this file when run from the IDE on a saved document;
// fall back to the project path if the document hasn't been saved.
~barosimOutDir = if (thisProcess.nowExecutingPath.notNil) {
	thisProcess.nowExecutingPath.dirname
} {
	"/Users/torrisi/Desktop/artProjects/ear/barosim/synthdefs"
};

SynthDef(\barosimPlayer, {
	|buf = 0, panMode = 2, cutoff = 2886.0881216287, rq = 0.90452261306533,
	loudnessAmt = 0.5,
	amp = 0.7, gate = 1, out = 0,
	toneFreq = 4000, toneAmp = 0.0027638190954774, toneOn = 0,
	carrierFreq = 9060.4303406228, wobbleRate = 0.3, wobbleDepth = 150,
	dustDensity = 0.65843185309129, dustDecay = 0.0088953315534101,
	dustAmt = 2.5326633165829, hpfCutoff = 4127.3795995172,
	distortionAmt = 0.030150753768844, distortionLpf = 10282.181649775,
	dustAttack = 0.001, earLpf = 20000,
	envAttack = 0.01, envRelease = 0.25,
	envSense = 2.05, envCurve = 1.4120603015075|

	// Number of cascaded 2-pole (RLPF) stages making up the L-channel
	// lowpass. Compile-time, not a synth arg: SynthDef topology (how
	// many UGens exist) is fixed at compile time, so "order" can't be
	// a live knob the way cutoff/rq are. Each stage adds ~12dB/oct.
	// Keep in sync with `lpfOrder` in date-profiles.json (used only to
	// draw the response graph) and ~lpfOrder in the tuning GUI.
	var lpfOrder = 3;

	var raw, rawL, rawR, drivenRaw, leftSig, rightSig, lAmp, rAmp,
		env, sig, tone, distortion, crunchEnv, loudness, lpfSig;

	// Stereo sample playback. Buffer must be genuine 2-channel.
	raw = PlayBuf.ar(2, buf, BufRateScale.kr(buf), loop: 1);
	rawL = raw[0];
	rawR = raw[1];

	// loudnessAmt is a single master gain doing 3 coupled jobs:
	//   1. scales the L channel's source signal BEFORE the filter /
	//      distortion stages (L gets louder);
	//   2. via `loudness` below (which tracks this boosted signal),
	//      makes L more distorted as the knob rises;
	//   3. scales R as a plain linear volume (see rightSig below).
	// At loudnessAmt = 0 BOTH channels are silent.
	drivenRaw = rawL * loudnessAmt;

	// Faint single-frequency tone (tinnitus), toggled by toneOn and
	// smoothed so flipping it doesn't click. Lives on the L path, so it
	// follows the L/both/R routing below. Deliberately NOT scaled by
	// loudnessAmt: a steady reference tone, not part of the distortion.
	tone = SinOsc.ar(toneFreq) * toneAmp * Lag.kr(toneOn, 0.05);

	// Ring-mod distortion bed: drivenRaw x a sine wobbling around
	// carrierFreq. Multiplying by a sine creates sum/difference
	// sidebands around the carrier: inharmonic, metallic, TONAL (unlike
	// bit-crushing, which is noise). The carrier drifts via a slow
	// LFNoise1 (wobbleRate Hz, +/- wobbleDepth Hz) so it reads as an
	// unstable damage artifact, not a second steady pitch like `tone`.
	distortion = drivenRaw * SinOsc.ar(
		carrierFreq + LFNoise1.kr(wobbleRate).range(wobbleDepth.neg, wobbleDepth)
	);

	// Dust-triggered crunch accents on top of the steady bed: sparse,
	// randomly timed bursts (Poisson-distributed, ~dustDensity per
	// second) that give the layer its granularity. dustAmt = how much
	// louder a crunch burst is than the bed,
	// dustDecay = fade time, dustAttack = onset time (longer = softer).
	// dustAttack is capped at half of dustDecay: Decay2's output
	// collapses (and flips sign) if attack >= decay.
	crunchEnv = Decay2.ar(Dust.ar(dustDensity), dustAttack.min(dustDecay * 0.5), dustDecay);
	distortion = distortion * (1 + (crunchEnv * dustAmt));

	// HPF at hpfCutoff, deliberately INDEPENDENT of the LPF's `cutoff`:
	// the LPF removes the highs on its own curve, nothing lives in the
	// gap, then the distortion re-enters higher up as an isolated band.
	distortion = HPF.ar(distortion, hpfCutoff);

	// LPF AFTER the HPF: together they make the distortion a bounded band
	// instead of "everything above hpfCutoff", and tame the aliasing the
	// ring-mod creates near Nyquist. Clipped below Nyquist so the filter
	// stays stable at any value.
	distortion = LPF.ar(distortion, distortionLpf.clip(200, SampleRate.ir * 0.45));

	// Loudness follower: the distortion's level rides on how loud THIS
	// MOMENT of drivenRaw is (quiet passages are barely distorted, loud ones
	// are distorted more). envSense lifts quiet-to-mid levels toward 1 before
	// clipping; envCurve (>1) then suppresses quiet/mid levels again
	// while still reaching full strength at real peaks.
	loudness = Amplitude.kr(drivenRaw, envAttack, envRelease);
	loudness = (loudness * envSense).clip(0, 1) ** envCurve;

	// L lowpass: `lpfOrder` cascaded RLPF stages. `rq` is the
	// reciprocal of Q: lower = a resonant peak right at the corner
	// (three stages at rq 0.5 stack to about +17dB, which clips easily).
	lpfSig = drivenRaw;
	lpfOrder.do { lpfSig = RLPF.ar(lpfSig, cutoff, rq) };

	// Left channel: cascaded-lowpass signal + distortion + tone.
	// distortionAmt is the master level of the whole distortion layer,
	// independent of the loudness follower (which only shapes dynamics).
	leftSig = lpfSig + (distortion * loudness * distortionAmt) + tone;

	// Final lowpass over the whole left-ear mix (muffling + distortion +
	// tone). Set very high so it only shaves the extreme top, the
	// near-Nyquist edge the ring-mod and crunch bursts can leave behind.
	// 20000 is effectively off. Clipped below Nyquist so it stays stable.
	leftSig = LPF.ar(leftSig, earLpf.clip(200, SampleRate.ir * 0.45));

	// Right channel stays clean (no filter, no distortion, no tone) but
	// tracks loudnessAmt as a plain linear volume scale.
	rightSig = rawR * loudnessAmt;

	// panMode: 0 = left only, 1 = right only, 2 = both
	lAmp = Select.kr(panMode, [1, 0, 1]);
	rAmp = Select.kr(panMode, [0, 1, 1]);

	// gate lets us fade out cleanly on stop instead of clicking
	env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);

	sig = [leftSig * lAmp, rightSig * rAmp] * amp * env;
	Out.ar(out, sig);
}).writeDefFile(~barosimOutDir);

("wrote barosimPlayer.scsyndef to " ++ ~barosimOutDir).postln;
)

// WORKFLOW: tune in date-param-profiles10.scd (or newer). The browser
// reads its numbers from date-profiles.json, so for everyday tuning you
// only need to paste the new values into the JSON. Recompile THIS file
// only when the DSP graph itself changes (new args, new stages,
// lpfOrder), and keep the arg defaults above in sync with the tuning
// GUI's.
//
// FUTURE: "healing" snapshots, i.e. periodic reassessment sessions,
// each written as a new dated entry in the "dates" array of
// date-profiles.json. index.html's date dropdown already reads that
// array; entries only need to list the params that differ from the
// default date.
