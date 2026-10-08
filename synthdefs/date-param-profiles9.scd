// ---------------------------------------------------------------
// date-param-profiles9.scd. for barosim project, ST + claude Oct '26
//
// GUI-based tuning rig for barosimPlayer's damage-chain parameters —
// RING-MOD + DUST distortion version, simplified to mirror
// make_synthdef.scd exactly (one SynthDef, one lpfOrder, no solo/mute/
// bypass scaffolding). Run this in the SuperCollider IDE. It loads 4
// sound samples and has a slider for every synth arg that
// exists in production.
//
// WORKFLOW (assessment sessions, maybe every few months or years):
//   1. Run this, which reads date-profiles.json from the project
//      and STARTS FROM THE MOST RECENT SNAPSHOT. The "Start from snapshot"
//      menu loads other dates so you can A/B old vs. new.
//   2. Adjust sliders until sound matches patient's perception.
//   3. Set the date field (defaults to today) and click "export JSON
//      entry". A complete, paste-ready snapshot is printed to the post
//      window (and copied to the clipboard on macOS).
//   4. Paste it into the "dates" array of date-profiles.json (add a comma
//      after the previous entry's closing brace), save, reload the page.
//      No recompile needed. Recompile make_synthdef.scd only if the DSP
//      graph itself changed.
//
// MATCHES PRODUCTION: as of v9, make_synthdef.scd has the identical
// graph and the same arg defaults (including distortionAmt, distortionLpf
// and dustAttack), and index.html reads its numbers from
// date-profiles.json. If you change the DSP graph here, mirror it in
// make_synthdef.scd and recompile; if you only retune values, paste
// them into date-profiles.json (no recompile needed).
//
// LAYOUT: the main window shows only the controls that matter most.
// The "advanced" button reveals a third column (wobble, dust decay,
// envelope timing). Hidden (working) sliders keep working at their
// defaults and are more advanced parameters.
//
// DEVICE: output follows the macOS system default (wired headphones).
// For Bluetooth, set ~bluetoothDevice near the top of the main block.
// The whole file now runs w a single Cmd+Enter inside outer parens.
//
// IMPORTANT: the DSP graph inside the tuning SynthDef below is a hand-
// kept copy of the real barosimPlayer graph in make_synthdef.scd.
// If you change algorithm in make_synthdef.scd, mirror that change here too!
// ---------------------------------------------------------------

(
// --- audio device ---------------------------------------------
// Device options only take effect at boot.
~bluetoothDevice = nil;

s.options.numInputBusChannels = 0;   // playback only, never opens a mic
s.options.numOutputBusChannels = 2;
s.options.sampleRate = nil;          // follow the device's own rate

if (~bluetoothDevice.notNil) {
	// Setting both disambiguates same-named in/out entries on macOS.
	s.options.inDevice = ~bluetoothDevice;
	s.options.outDevice = ~bluetoothDevice;
} {
	s.options.device = nil;          // system default output
};

~sampleFiles = [
	"sound1_gynt_trim.flac",
	"sound2_poem.flac",
	"sound3_peruvian_city-ambience_trim.flac",
	"sound4_tlalocs_sky.wav"
];

// --- project paths ----------------------------------------------
// This file is meant to live in synthdefs/ next to date-profiles.json,
// so the project root is one level up from wherever it was run.
~scriptDir = thisProcess.nowExecutingPath !? { |p| p.dirname };
~candidateRoots = List.new;
if (~scriptDir.notNil) { ~candidateRoots.add(PathName(~scriptDir).parentPath) };
~candidateRoots.add("/Users/torrisi/Desktop/artProjects/ear/barosim/");
~projectRoot = ~candidateRoots.detect { |r|
	File.exists(r +/+ "synthdefs" +/+ "date-profiles.json")
};
if (~projectRoot.isNil) {
	~projectRoot = ~candidateRoots.last;
	"!! couldn't find synthdefs/date-profiles.json; using built-in starting values.".postln;
};
~samplesDir = ~projectRoot +/+ "sounds" +/+ "samples" ++ "/";
~profilesPath = ~projectRoot +/+ "synthdefs" +/+ "date-profiles.json";

// --- snapshots from date-profiles.json ---------------------------
// ~snapshots: oldest -> newest, each (date:, label:, params:), where
// params are Floats with missing keys inherited from the OLDEST entry
// (same rule as index.html). Use snap[\date] etc. rather than
// snap.date: Event's built-in methods (e.g. .value) can shadow keys.
~loadSnapshots = {
	var data, list = List.new, base;
	if (File.exists(~profilesPath)) {
		try {
			data = File.readAllString(~profilesPath).parseYAML;
			data["dates"].do { |entry|
				var params = ();
				entry["params"].keysValuesDo { |k, v| params[k.asSymbol] = v.asFloat };
				list.add((date: entry["value"], label: entry["label"] ? entry["value"], params: params));
			};
			list = list.asArray.sort { |a, b| a[\date] < b[\date] }.asList;
			if (list.size > 0) {
				base = list[0][\params];
				list.do { |sn| sn[\params] = base.copy.putAll(sn[\params]) };
			};
		} { |err|
			("!! couldn't parse date-profiles.json: " ++ err.errorString).postln;
			list = List.new;
		};
	};
	~snapshots = list;
};
~loadSnapshots.value;

s.waitForBoot({
	~bufs = ~sampleFiles.collect { |fn| Buffer.read(s, ~samplesDir +/+ fn) };
	s.sync;

	// confirm every buffer actually loaded (numFrames > 0) — if
	// ~samplesDir or a filename is wrong, Buffer.read fails silently
	// server-side (numFrames comes back nil, not 0, when the file
	// couldn't be opened at all) and you won't find out until PlayBuf
	// errors with "no buffer data" later. Catch it here instead.
	// isNil-checked first since nil <= 0 crashes with a doesNotUnderstand
	// error rather than failing cleanly.
	~bufs.do { |buf, i|
		if (buf.numFrames.isNil or: { buf.numFrames <= 0 }) {
			("!! FAILED TO LOAD: " ++ ~samplesDir +/+ ~sampleFiles[i]
				++ " — check the path/filename.").postln;
		} {
			("loaded ok: " ++ ~sampleFiles[i] ++ " ("
				++ buf.numFrames ++ " frames, "
				++ buf.numChannels ++ "ch)").postln;
		}
	};

	// ---- tuning SynthDef: exact mirror of make_synthdef.scd's
	// barosimPlayer graph, one lpfOrder (compile-time, same
	// restriction as production — see make_synthdef.scd's comment).
	~lpfOrder = 3;

	SynthDef(\tuneDistortion, {
		|buf = 0, panMode = 2, cutoff = 2886.0881216287, rq = 0.90452261306533,
		loudnessAmt = 0.5,
		amp = 0.7, gate = 1, out = 0,
		toneFreq = 4000, toneAmp = 0.0027638190954774, toneOn = 0,
		carrierFreq = 9060.4303406228, wobbleRate = 0.3, wobbleDepth = 150,
		dustDensity = 0.65843185309129, dustDecay = 0.0088953315534101,
		dustAmt = 2.5326633165829, hpfCutoff = 4127.3795995172,
		distortionAmt = 0.030150753768844, distortionLpf = 10282.181649775,
		dustAttack = 0.001,
		envAttack = 0.01, envRelease = 0.25,
		envSense = 2.05, envCurve = 1.4120603015075|

		var raw, rawL, rawR, drivenRaw, leftSig, rightSig, lAmp, rAmp,
			env, sig, tone, distortion, crunchEnv, loudness, lpfSig;

		raw = PlayBuf.ar(2, buf, BufRateScale.kr(buf), loop: 1);
		rawL = raw[0];
		rawR = raw[1];
		drivenRaw = rawL * loudnessAmt;

		tone = SinOsc.ar(toneFreq) * toneAmp * Lag.kr(toneOn, 0.05);

		// ring-mod distortion bed: drivenRaw x a sine wobbling around
		// carrierFreq (see make_synthdef.scd for full rationale).
		distortion = drivenRaw * SinOsc.ar(
			carrierFreq + LFNoise1.kr(wobbleRate).range(wobbleDepth.neg, wobbleDepth)
		);

		// Dust-triggered crunch accents on top of the steady distortion bed.
		// dustAttack is capped at half of dustDecay: Decay2's output
		// collapses (and flips sign) if attack >= decay.
		crunchEnv = Decay2.ar(Dust.ar(dustDensity), dustAttack.min(dustDecay * 0.5), dustDecay);
		distortion = distortion * (1 + (crunchEnv * dustAmt));

		// HPF at hpfCutoff — this is what keeps distortion confined to
		// "very high freqs only" (4kHz+ by default), independent of
		// the LPF's cutoff below. Everything the LPF passes stays
		// completely clean; the gap between cutoff and hpfCutoff is
		// silent; distortion only exists above hpfCutoff.
		distortion = HPF.ar(distortion, hpfCutoff);

		// Low-pass AFTER the high-pass: together they make the distortion a
		// bounded band instead of "everything above hpfCutoff". Also
		// tames the aliasing the ring-mod creates near Nyquist. Clipped
		// below Nyquist so the filter stays stable at any slider value.
		distortion = LPF.ar(distortion, distortionLpf.clip(200, SampleRate.ir * 0.45));

		// loudness-tracking: distortion amount rides on how loud THIS
		// MOMENT of drivenRaw is — quiet passages are barely distorted, loud
		// ones are distorted hard. This is the mechanism behind "more of it
		// when the sounds are louder." 
		loudness = Amplitude.kr(drivenRaw, envAttack, envRelease);
		loudness = (loudness * envSense).clip(0, 1) ** envCurve;

		// LPF path: the clean lows/mids, untouched by distortion.
		lpfSig = drivenRaw;
		~lpfOrder.do { lpfSig = RLPF.ar(lpfSig, cutoff, rq) };

		// distortionAmt: master level of the whole distortion layer, independent
		// of the loudness-tracking envelope above (which only shapes dynamics).
		leftSig = lpfSig + (distortion * loudness * distortionAmt) + tone;
		rightSig = rawR * loudnessAmt;  // mirrors make_synthdef.scd

		lAmp = Select.kr(panMode, [1, 0, 1]);
		rAmp = Select.kr(panMode, [0, 1, 1]);

		env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);
		sig = [leftSig * lAmp, rightSig * rAmp] * amp * env;
		Out.ar(out, sig);
	}).add;

	s.sync;

	// ---- state ----
	~sampleIdx = 0;
	~synth = nil;
	~muted = false;
	~params = (
		cutoff: 2886.0881216287, rq: 0.90452261306533,
		hpfCutoff: 4127.3795995172, loudnessAmt: 0.5,
		carrierFreq: 9060.4303406228, wobbleRate: 0.3, wobbleDepth: 150,
		dustDensity: 0.65843185309129, dustDecay: 0.0088953315534101,
		dustAmt: 2.5326633165829, distortionAmt: 0.030150753768844,
		distortionLpf: 10282.181649775, dustAttack: 0.001,
		envAttack: 0.01, envRelease: 0.25,
		envSense: 2.05, envCurve: 1.4120603015075,
		toneFreq: 4000, toneAmp: 0.0027638190954774, toneOn: 0,
		panMode: 2, amp: 0.7
	);

	// Copies a snapshot's values into ~params (only keys that exist here;
	// panMode / toneOn / amp are never in a snapshot, so they stay put).
	~applySnapshot = { |snap|
		snap[\params].keysValuesDo { |k, v|
			if (~params.includesKey(k)) { ~params[k] = v };
		};
	};
	if (~snapshots.size > 0) {
		~applySnapshot.value(~snapshots.last);
		("starting from snapshot " ++ ~snapshots.last[\label]
			++ " (" ++ ~snapshots.last[\date] ++ "); " ++ ~snapshots.size
			++ " snapshot(s) loaded").postln;
	} {
		"no snapshots loaded; using the built-in starting values".postln;
	};

	// mute overrides amp to 0 without touching ~params.amp itself, so
	// un-muting restores exactly the level you had before — mute is a
	// separate on/off layered on top of, not a destructive edit to,
	// the amp value.
	~effectiveAmp = { if (~muted) { 0 } { ~params.amp } };

	// snapshot of the starting values above, used by the "reset" button
	// to restore both ~params and every slider's on-screen position —
	// captured once, before anything gets tweaked live.
	~origParams = ~params.copy;
	~origSampleIdx = ~sampleIdx;

	// filled in by ~addSlider below, so ~reset can move sliders back to
	// their starting positions instead of just updating ~params under
	// the hood while the widgets stay wherever you left them.
	~sliderRefs = List.new;

	~printParams = {
		("--- sample: " ++ ~sampleFiles[~sampleIdx] ++ " ---").postln;
		~params.keysValuesDo { |k, v| ("  " ++ k.asString ++ ": " ++ v).postln };
		"".postln;
	};

	// (re)starts the synth from scratch — required whenever buf changes
	// since PlayBuf doesn't reset cleanly on a buffer swap mid-flight.
	~respawn = {
		if (~synth.notNil) { ~synth.free };
		~synth = Synth(\tuneDistortion, [
			buf: ~bufs[~sampleIdx], panMode: ~params.panMode,
			cutoff: ~params.cutoff, rq: ~params.rq, hpfCutoff: ~params.hpfCutoff,
			loudnessAmt: ~params.loudnessAmt,
			carrierFreq: ~params.carrierFreq, wobbleRate: ~params.wobbleRate,
			wobbleDepth: ~params.wobbleDepth,
			dustDensity: ~params.dustDensity, dustDecay: ~params.dustDecay,
			dustAmt: ~params.dustAmt, distortionAmt: ~params.distortionAmt,
			distortionLpf: ~params.distortionLpf, dustAttack: ~params.dustAttack,
			envAttack: ~params.envAttack, envRelease: ~params.envRelease,
			envSense: ~params.envSense, envCurve: ~params.envCurve,
			toneFreq: ~params.toneFreq, toneAmp: ~params.toneAmp,
			toneOn: ~params.toneOn,
			amp: ~effectiveAmp.value
		]);
	};

	// updates a live arg on the running synth via n_set, no restart
	~setLive = { |key, val|
		~params[key] = val;
		if (~synth.notNil) { ~synth.set(key, val) };
	};

	// moves every slider (and the tone toggle) to match ~params. Setting
	// .value doesn't fire a slider's action, so ~params is untouched.
	~syncSliders = {
		~sliderRefs.do { |info|
			var v = ~params[info.key];
			info.sl.value = if (info.curve == \exp) {
				v.explin(info.lo, info.hi, 0, 1)
			} {
				v.linlin(info.lo, info.hi, 0, 1)
			};
		};
		~toneToggle.value = ~params.toneOn;
	};

	// restores every param to its opening value (the snapshot the session
	// started from), moves every slider back, and respawns on the
	// original sample. Also un-mutes, since a stuck mute after "reset"
	// would be a confusing silent-GUI surprise.
	~reset = {
		~params = ~origParams.copy;
		~sampleIdx = ~origSampleIdx;
		~muted = false;
		~syncSliders.value;
		~muteToggle.value = 0;
		~respawn.value;
		~printParams.value;
	};

	// loads snapshot number `idx` (from the menu) into all sliders and
	// restarts the synth, so you can A/B dated snapshots by ear.
	~loadSnapshot = { |idx|
		var snap = ~snapshots[idx];
		if (snap.notNil) {
			~applySnapshot.value(snap);
			~syncSliders.value;
			~respawn.value;
			("--- loaded snapshot " ++ snap[\label] ++ " (" ++ snap[\date] ++ ") ---").postln;
		};
	};

	// ---- export: print a complete, paste-ready date-profiles.json entry
	~monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	// Everything the page takes from a snapshot. panMode / toneOn / amp
	// are page-owned UI state, so they're deliberately not exported.
	~exportKeys = [
		\cutoff, \rq, \hpfCutoff, \loudnessAmt,
		\carrierFreq, \wobbleRate, \wobbleDepth,
		\dustDensity, \dustDecay, \dustAmt, \distortionAmt,
		\distortionLpf, \dustAttack,
		\envAttack, \envRelease, \envSense, \envCurve,
		\toneFreq, \toneAmp
	];
	~todayString = {
		var d = Date.getDate;
		d.year.asString ++ "-" ++ d.month.asString.padLeft(2, "0")
			++ "-" ++ d.day.asString.padLeft(2, "0")
	};
	~copyToClipboard = { |str|
		var ok = false;
		if (thisProcess.platform.name == \osx) {
			try { var p = Pipe("pbcopy", "w"); p.write(str); p.close; ok = true };
		};
		ok
	};
	~exportEntry = {
		var parts, y, m, d, valid, dateStr, label, lines, text;
		parts = ~dateField.string.stripWhiteSpace.split($-);
		valid = (parts.size == 3) and: {
			parts.every { |p| (p.size > 0) and: { p.every(_.isDecDigit) } }
		};
		if (valid) {
			y = parts[0].asInteger; m = parts[1].asInteger; d = parts[2].asInteger;
			valid = (y >= 2000) and: { (m >= 1) and: { (m <= 12) and: { (d >= 1) and: { d <= 31 } } } };
		};
		if (valid.not) {
			"!! date must look like 2027-04-12 (YYYY-MM-DD). Nothing exported.".postln;
		} {
			dateStr = y.asString ++ "-" ++ m.asString.padLeft(2, "0") ++ "-" ++ d.asString.padLeft(2, "0");
			label = ~monthNames[m - 1] ++ " " ++ d ++ ", " ++ y;
			lines = List.new;
			lines.add("    {");
			lines.add("      \"value\": \"" ++ dateStr ++ "\",");
			lines.add("      \"label\": \"" ++ label ++ "\",");
			lines.add("      \"params\": {");
			~exportKeys.do { |k, i|
				var comma = if (i < (~exportKeys.size - 1)) { "," } { "" };
				lines.add("        \"" ++ k ++ "\": " ++ ~params[k].asString ++ comma);
			};
			lines.add("      }");
			lines.add("    }");
			text = lines.asArray.join("\n");
			"".postln;
			"======== NEW SNAPSHOT ENTRY ========".postln;
			"Paste inside the \"dates\" array of date-profiles.json, after the last entry".postln;
			"(put a comma after the previous entry's closing brace).".postln;
			"".postln;
			text.postln;
			"".postln;
			if (~snapshots.any { |sn| sn[\date] == dateStr }) {
				("!! WARNING: a snapshot dated " ++ dateStr ++ " already exists; pick a different date or replace that entry.").postln;
			};
			if (~copyToClipboard.value(text)) {
				"(copied to clipboard)".postln;
			} {
				"(select the text above and copy it; clipboard copy works on macOS only)".postln;
			};
			"=====================================".postln;
		};
	};

	// Colors match index.html's response graph exactly, so a section
	// header tells you at a glance which curve its controls move:
	// teal = the blue/LPF line, orange = the dashed distortion-reentry line.
	~colorBlue = Color.new255(63, 199, 189);   // #3fc7bd, graph's L/LPF curve
	~colorCrush = Color.new255(201, 107, 75);  // #c96b4b, graph's distortion curve
	~colorDim = Color.new255(156, 157, 143);   // #9c9d8f, graph's dim/inactive text
	~colorInk = Color.new255(255, 255, 255);   // #ffffff, plain body text

	// ---- GUI ----
	// Two side-by-side columns — this is a much shorter control set
	// than the old crush-era rig (no order switcher, no solo/mute/
	// bypass scaffolding, no envelope preview graphic), so it fits
	// comfortably without needing a third column.
	~colWidth = 460;
	~colGap = 20;
	~colMargin = 20;
	~colHeight = 640;
	~winWidth = (~colMargin * 2) + (~colWidth * 2) + ~colGap;
	~winHeight = ~colHeight + 60;
	~winWidthAdv = (~colMargin * 2) + (~colWidth * 3) + (~colGap * 2);

	~win = Window("adjust barosim parameters (ring-mod + Dust distortion) v9", Rect(60, 60, ~winWidth, ~winHeight)).front;

	~col1 = View(~win, Rect(~colMargin, 20, ~colWidth, ~colHeight));
	~col1.decorator = FlowLayout(~col1.bounds);
	~col2 = View(~win, Rect(~colMargin + ~colWidth + ~colGap, 20, ~colWidth, ~colHeight));
	~col2.decorator = FlowLayout(~col2.bounds);
	// column 3: "advanced" controls, hidden until the button is pressed
	~col3 = View(~win, Rect(~colMargin + ((~colWidth + ~colGap) * 2), 20, ~colWidth, ~colHeight));
	~col3.decorator = FlowLayout(~col3.bounds);
	~col3.visible = false;

	~addSectionLabel = { |parent, text, color|
		StaticText(parent, 440@22).string_(text).stringColor_(color);
		parent.decorator.nextLine;
	};

	// ---- column 1: setup + BLUE (LPF path) ----
	// full-width, top-of-window mute.
	// Overrides amp to 0 via ~effectiveAmp without touching
	// ~params.amp, so un-muting snaps back to exactly the level you
	// had, rather than requiring you to re-set a level slider.
	~muteToggle = Button(~col1, 440@34)
		.states_([["MUTE", Color.white, ~colorCrush], ["MUTED — click to unmute", Color.white, ~colorCrush.blend(Color.black, 0.3)]])
		.action_({ |bt|
			~muted = (bt.value == 1);
			if (~synth.notNil) { ~synth.set(\amp, ~effectiveAmp.value) };
		});
	~col1.decorator.nextLine;

	StaticText(~col1, 440@20).string_("Start from snapshot (loads its values into the sliders):");
	~col1.decorator.nextLine;
	~snapMenu = PopUpMenu(~col1, 440@26)
		.items_(if (~snapshots.size > 0) {
			~snapshots.collect { |sn| sn[\label] ++ "   (" ++ sn[\date] ++ ")" }.asArray
		} {
			["(no snapshots found)"]
		})
		.action_({ |m| ~loadSnapshot.value(m.value) });
	if (~snapshots.size > 0) { ~snapMenu.value = ~snapshots.size - 1 };
	~col1.decorator.nextLine;

	StaticText(~col1, 440@20).string_("Sound source (restarts synth):");
	~col1.decorator.nextLine;
	~sampleFiles.do { |fn, i|
		Button(~col1, 145@30)
			.states_([[PathName(fn).fileNameWithoutExtension]])
			.action_({ ~sampleIdx = i; ~respawn.value; ~printParams.value; });
	};
	~col1.decorator.nextLine;

	StaticText(~col1, 440@20).string_("Pan (live):");
	~col1.decorator.nextLine;
	[["L", 0], ["both", 2], ["R", 1]].do { |pair|
		Button(~col1, 145@30)
			.states_([[pair[0]]])
			.action_({ ~setLive.value(\panMode, pair[1]); });
	};
	~col1.decorator.nextLine;

	// labeled slider helper. parent: which column View to add to.
	// curve: \exp or \lin. step: round to this increment if > 0.
	// initVal defaults to the current ~params value.
	~addSlider = { |parent, label, key, lo, hi, curve = \exp, step = 0, printPrecision = 0.001|
		var sl, initVal = ~params[key];
		StaticText(parent, 440@20).string_(label);
		parent.decorator.nextLine;
		sl = Slider(parent, 420@20);
		sl.value = if (curve == \exp) {
			initVal.explin(lo, hi, 0, 1)
		} {
			initVal.linlin(lo, hi, 0, 1)
		};
		sl.action_({ |v|
			var val = if (curve == \exp) {
				v.value.linexp(0, 1, lo, hi)
			} {
				v.value.linlin(0, 1, lo, hi)
			};
			if (step > 0) { val = (val / step).round * step };
			~setLive.value(key, val);
			("  " ++ label ++ " -> " ++ val.round(printPrecision)).postln;
		});
		~sliderRefs.add((sl: sl, key: key, lo: lo, hi: hi, curve: curve));
		parent.decorator.nextLine;
		sl;
	};

	~addSectionLabel.value(~col1, "── BLUE — LPF path (clean) ──", ~colorBlue);
	~addSlider.value(~col1, "Cutoff (Hz, exp)", \cutoff, 200, 8000, \exp);
	// Capped at 1.0, not 2.0: empirically, rq above 1 goes unstable/
	// "crazy" — notably the opposite of the usual direction (lower rq
	// = higher Q = more resonance is normally the dangerous end for a
	// single resonant filter). Possibly an interaction from cascading
	// 3 RLPF stages rather than a single one.
	~addSlider.value(~col1, "RQ (resonance, lower = sharper)", \rq, 0.05, 1.0, \lin);

	~addSectionLabel.value(~col1, "── BOTH — feeds into both paths above ──", ~colorInk);
	~addSlider.value(~col1, "Loudness", \loudnessAmt, 0, 1, \lin);

	~addSectionLabel.value(~col1, "── NOT IN THE GRAPH — tinnitus tone ──", ~colorDim);
	~addSlider.value(~col1, "Tone freq (Hz, exp)", \toneFreq, 1000, 15000, \exp);
	~addSlider.value(~col1, "Tone amp", \toneAmp, 0, 0.1, \lin, 0, 0.0001);
	~toneToggle = Button(~col1, 150@30)
		.states_([["tone: off"], ["tone: on"]])
		.action_({ |bt| ~setLive.value(\toneOn, bt.value); });
	~col1.decorator.nextLine;

	// ---- column 2: ORANGE core controls (distortion re-entry path) ----
	~addSectionLabel.value(~col2, "── ORANGE — distortion re-entry path (4kHz+ only) ──", ~colorCrush);
	// Master level of the whole distortion layer. 1.0 = the previous
	// behavior; 0 = distortion off entirely. Raise it if the distortion is
	// hard to hear; the envelope sliders only shape how it rises/falls.
	~addSlider.value(~col2, "Distortion amount (master level, lin)", \distortionAmt, 0, 1, \lin);
	// Where the distortion re-enters. Keep well above `cutoff` so the
	// effect stays confined to the very top of the spectrum.
	~addSlider.value(~col2, "HPF cutoff / gap (Hz, exp)", \hpfCutoff, 500, 8000, \exp);
	// Upper edge of the distortion band (low-pass after the high-pass).
	// 20000 = effectively off. Lower it (try 8-10k) to smooth/soften;
	// keep it above hpfCutoff or the band closes and distortion vanishes.
	~addSlider.value(~col2, "Distortion LPF (Hz, exp)", \distortionLpf, 2000, 20000, \exp);
	// Center pitch of the ring-mod. Higher = higher, glassier sidebands.
	~addSlider.value(~col2, "Carrier freq (Hz, exp)", \carrierFreq, 2000, 14000, \exp);
	// Dust: average random crunch bursts per second. Low (1-4) = isolated
	// crunches; high (20+) blurs into dense granularity.
	~addSlider.value(~col2, "Dust density (events/sec, exp)", \dustDensity, 0.5, 40, \exp);
	// How much louder each crunch burst is than the steady distortion. 0 = no crunch.
	~addSlider.value(~col2, "Dust amt (crunch boost, lin)", \dustAmt, 0, 4, \lin);
	// How strongly distortion follows the sound's loudness: sense lifts
	// quiet-to-mid levels, curve suppresses them again (higher = quiet
	// parts are distorted less, loud parts still reach full strength).
	~addSlider.value(~col2, "Env sense", \envSense, 0.1, 4, \lin);
	~addSlider.value(~col2, "Env curve", \envCurve, 0.5, 6, \lin);

	// ---- column 3: ADVANCED (hidden by default) ----
	~addSectionLabel.value(~col3, "── ADVANCED — leave at defaults unless needed ──", ~colorDim);
	// How fast the carrier wanders (LFNoise1 rate, Hz). Well under 1 =
	// slow drift; higher starts to sound like a fast warble.
	~addSlider.value(~col3, "Wobble rate (Hz, exp)", \wobbleRate, 0.02, 5, \exp);
	// How far the carrier wanders from carrierFreq, in Hz. 0 = dead still.
	~addSlider.value(~col3, "Wobble depth (Hz, lin)", \wobbleDepth, 0, 1000, \lin);
	// How long each crunch burst takes to fade: short = tight/clicky, long = smeared.
	~addSlider.value(~col3, "Dust decay (s, exp)", \dustDecay, 0.005, 0.3, \exp);
	// Crunch onset time: ~1ms = instant (clicky); 5-10ms = softer.
	// Internally capped at half of dust decay.
	~addSlider.value(~col3, "Dust attack (s, exp)", \dustAttack, 0.0005, 0.05, \exp);
	// Loudness follower timing (time-domain, so not visible on the graph).
	~addSlider.value(~col3, "Env attack (s, exp)", \envAttack, 0.001, 0.5, \exp);
	~addSlider.value(~col3, "Env release (s, exp)", \envRelease, 0.01, 1.0, \exp);

	StaticText(~col2, 440@20).string_("Snapshot date for export (YYYY-MM-DD):");
	~col2.decorator.nextLine;
	~dateField = TextField(~col2, 200@30).string_(~todayString.value);
	~exportBtn = Button(~col2, 230@30)
		.states_([["export JSON entry"]])
		.action_({ ~exportEntry.value });
	~col2.decorator.nextLine;

	~row1 = View(~col2, 440@36);
	~row1.decorator = FlowLayout(~row1.bounds, 0@0, 10@0);
	Button(~row1, 220@30)
		.states_([["print current values"]])
		.action_({ ~printParams.value; });
	~col2.decorator.nextLine;

	~advToggle = Button(~col2, 440@30)
		.states_([["advanced ▸"], ["advanced ▾  (hide)"]])
		.action_({ |bt|
			~col3.visible = (bt.value == 1);
			~win.setInnerExtent(if (bt.value == 1) { ~winWidthAdv } { ~winWidth }, ~winHeight);
		});
	~col2.decorator.nextLine;

	~row2 = View(~col2, 440@36);
	~row2.decorator = FlowLayout(~row2.bounds, 0@0, 8@0);
	Button(~row2, 140@30)
		.states_([["reset"]])
		.action_({ ~reset.value; });
	Button(~row2, 140@30)
		.states_([["stop"]])
		.action_({
			if (~synth.notNil) { ~synth.free; ~synth = nil; };
		});
	Button(~row2, 140@30)
		.states_([["close"]])
		.action_({
			if (~synth.notNil) { ~synth.free; ~synth = nil; };
			~bufs.do(_.free);
			~win.close;
		});

	~respawn.value;
	~printParams.value;
});
)

// NOTE: slider starting positions are computed from ~params'
// defaults above, but SC's Slider GUI doesn't re-fire .action on
// programmatic .value_ sets — so the post window's initial printout
// (above) reflects the true starting state even before you touch
// anything; moving sliders afterward starts live updates.
