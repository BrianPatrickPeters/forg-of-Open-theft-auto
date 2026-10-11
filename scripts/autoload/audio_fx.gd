extends Node
## Sound effects. Combat reports (guns + Iron Man repulsor) load recorded
## CC0 banks from assets/audio/; everything else is still synthesized at
## load time into AudioStreamWAV buffers.

const MIX_RATE := 22050

var _muted: bool = false
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _ambient_player: AudioStreamPlayer
var _radio_player: AudioStreamPlayer
var _rocket_player: AudioStreamPlayer   # continuous ascent engine loop
var _wind_player: AudioStreamPlayer     # continuous re-entry wind roar loop
var _spacecraft_player: AudioStreamPlayer   # continuous spacecraft engine loop
var _jet_player: AudioStreamPlayer          # continuous plane turbofan loop

# Pre-baked streams
var _s_hit: AudioStreamWAV
var _s_coin_a: AudioStreamWAV
var _s_coin_b: AudioStreamWAV
var _s_explode_noise: AudioStreamWAV
var _s_explode_low: AudioStreamWAV
var _s_siren_a: AudioStreamWAV
var _s_siren_b: AudioStreamWAV
var _s_gun: AudioStream          # recorded generic report (cops / fallback)
var _s_gun_sniper: AudioStream   # recorded sniper boom (legacy fallback)
var _s_sniper_tail: AudioStreamWAV  # synthesized deep sub-boom layered under it
# Distinct per-weapon reports. Baked recorded banks first (see tools/bake_combat_sfx.py);
# the old sine-crack synth is only a fallback if a bank fails to load.
var _bank_pistol: Array = []
var _bank_revolver: Array = []
var _bank_smg: Array = []
var _bank_rifle: Array = []
var _bank_shotgun: Array = []
var _bank_sniper: Array = []
var _bank_repulsor: Array = []
var _s_gun_pistol: AudioStreamWAV
var _s_gun_revolver: AudioStreamWAV
var _s_gun_smg: AudioStreamWAV
var _s_gun_rifle: AudioStreamWAV
var _s_gun_shotgun: AudioStreamWAV
var _s_gun_rpg: AudioStreamWAV
var _s_repulsor: AudioStreamWAV     # synth fallback if the baked bank is missing
var _s_missile: AudioStreamWAV      # Iron Man shoulder missile launch
var _s_rocket_ignite: AudioStreamWAV
var _s_rocket_loop: AudioStreamWAV
var _s_wind_loop: AudioStreamWAV
var _s_spacecraft_loop: AudioStreamWAV
var _s_jet_loop: AudioStreamWAV     # turbofan whine + roar (see _jet_loop)
var _s_crash: AudioStreamWAV        # heavy airframe impact / scrape
var _s_gear: AudioStreamWAV         # landing-gear servo whirr + clunk

func _ready() -> void:
	for i in 20:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_s_hit = _tone(180.0, 0.08, "sawtooth", 0.6)
	_s_coin_a = _tone(880.0, 0.06, "square", 0.45)
	_s_coin_b = _tone(1320.0, 0.09, "square", 0.45)
	_s_explode_noise = _noise(0.5, 0.9)
	_s_explode_low = _tone(80.0, 0.4, "sawtooth", 0.85)
	_s_siren_a = _tone(700.0, 0.15, "sine", 0.4)
	_s_siren_b = _tone(500.0, 0.15, "sine", 0.4)
	_s_rocket_ignite = _rocket_ignition(1.1, 0.95)
	_s_rocket_loop = _rocket_rumble(1.4, 0.85)
	_s_wind_loop = _wind_noise(1.0, 0.8)
	_s_spacecraft_loop = _spacecraft_hum(1.3, 0.8)
	_s_jet_loop = _jet_loop(1.2, 0.82)
	_s_crash = _metal_crash(0.9, 0.95)
	_s_gear = _gear_whirr(1.0, 0.6)
	_s_repulsor = _repulsor(0.36, 0.85)
	_s_missile = _missile_launch(0.5, 0.9)

	# Recorded / baked gunfire. Banks are 2–3 takes each so rapid fire does
	# not machine-gun the same sample. CC0 sources, see assets/audio/CREDITS.md.
	_s_gun = _load_stream("res://assets/audio/gun_generic.wav")
	if _s_gun == null:
		_s_gun = _load_stream("res://assets/audio/gunshot.wav")
	_s_gun_sniper = _load_stream("res://assets/audio/gunshot_sniper.wav")
	_s_sniper_tail = _sniper_tail(0.65, 0.85)
	_bank_pistol = _load_bank("gun_pistol", 3)
	_bank_revolver = _load_bank("gun_revolver", 3)
	_bank_smg = _load_bank("gun_smg", 3)
	_bank_rifle = _load_bank("gun_rifle", 3)
	_bank_shotgun = _load_bank("gun_shotgun", 3)
	_bank_sniper = _load_bank("gun_sniper", 2)
	_bank_repulsor = _load_bank("repulsor", 3)

	# Synth fallbacks — used only if a baked bank is missing (headless / first
	# import). These are noise-based now; the old sine-crack is gone.
	_s_gun_pistol = _gunshot(0.16, 0.85, 0.22, 110.0, 0.35, 0.42)
	_s_gun_revolver = _gunshot(0.24, 0.7, 0.40, 78.0, 0.55, 0.55)
	_s_gun_smg = _gunshot(0.08, 0.95, 0.10, 160.0, 0.18, 0.14)
	_s_gun_rifle = _gunshot(0.18, 0.8, 0.28, 90.0, 0.45, 0.48)
	_s_gun_shotgun = _gunshot(0.40, 0.65, 0.55, 62.0, 0.75, 0.80)
	_s_gun_rpg = _rpg_launch(0.55, 0.95)

	# Looping background tracks on their own dedicated players.
	_ambient_player = AudioStreamPlayer.new()
	add_child(_ambient_player)
	_ambient_player.stream = _drone([55.0, 82.5], 2.0, 0.5)
	_ambient_player.volume_db = -23.0
	_radio_player = AudioStreamPlayer.new()
	add_child(_radio_player)
	_radio_player.stream = _melody(
		[220.0, 277.0, 330.0, 440.0, 392.0, 330.0, 277.0, 220.0], 0.26, "sine", 0.5)
	_radio_player.volume_db = -13.0
	_rocket_player = AudioStreamPlayer.new()
	add_child(_rocket_player)
	_rocket_player.stream = _s_rocket_loop
	_wind_player = AudioStreamPlayer.new()
	add_child(_wind_player)
	_wind_player.stream = _s_wind_loop
	_spacecraft_player = AudioStreamPlayer.new()
	add_child(_spacecraft_player)
	_spacecraft_player.stream = _s_spacecraft_loop
	_jet_player = AudioStreamPlayer.new()
	add_child(_jet_player)
	_jet_player.stream = _s_jet_loop


## A WAV that loops forward forever — for ambience and the radio.
func _loop_wav(data: PackedByteArray) -> AudioStreamWAV:
	var st := _wav(data)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = data.size() / 2 - 1
	return st


## A soft sustained drone — the freqs must complete whole cycles over `dur`
## so the buffer loops seamlessly.
func _drone(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := 0.0
		for f in freqs:
			s += sin(float(i) / MIX_RATE * float(f) * TAU)
		s /= float(freqs.size())
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _loop_wav(data)


## A looping chiptune riff — one note per entry in `freqs`.
func _melody(freqs: Array, note_dur: float, wave: String, vol: float) -> AudioStreamWAV:
	var per := int(MIX_RATE * note_dur)
	var data := PackedByteArray()
	data.resize(per * freqs.size() * 2)
	var idx := 0
	for f in freqs:
		var phase := 0.0
		var inc: float = float(f) / MIX_RATE
		for i in per:
			var t := float(i) / float(per)
			var env := clampf(minf(t * 8.0, (1.0 - t) * 8.0), 0.0, 1.0)
			var s := 0.0
			match wave:
				"square":
					s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				"sawtooth":
					s = fmod(phase, 1.0) * 2.0 - 1.0
				_:
					s = sin(phase * TAU)
			phase += inc
			data.encode_s16(idx * 2, int(clamp(s * env * vol, -1.0, 1.0) * 32767.0))
			idx += 1
	return _loop_wav(data)

func _tone(freq: float, dur: float, wave: String, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var inc := freq / MIX_RATE
	for i in n:
		var t := float(i) / float(n)
		var env: float = pow(0.0002, t)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"sawtooth":
				s = fmod(phase, 1.0) * 2.0 - 1.0
			_:
				s = sin(phase * TAU)
		phase += inc
		var v := int(clamp(s * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data)

## The rocket ignition swell — a deep sub tone plus brown-noise rumble that
## builds in over the first third of a second, with a sparse crackle layer
## (short random impulses) riding on top. The real signature of a rocket
## launch is that crackle — many small sharp pops rather than one smooth
## roar — so it's approximated here with randomised impulse bursts instead of
## a single tone.
func _rocket_ignition(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var brown := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env: float = clampf(t / 0.3, 0.0, 1.0)
		var white := randf() * 2.0 - 1.0
		brown = (brown + white * 0.02) / 1.02
		var crackle := 0.0
		if randf() < 0.006:
			crackle = (randf() * 2.0 - 1.0) * (0.5 + env * 0.6)
		var sub: float = sin(TAU * 46.0 * (t * dur)) * 0.5
		var s := (brown * 3.0 + crackle + sub) * env
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Continuous rocket-engine loop: brown noise (a leaky integrator over white
## noise, so it's weighted low like a real engine roar) plus the same sparse
## crackle layer as the ignition swell. Volume/pitch are driven live by
## rocket_engine_set() as thrust and altitude change.
func _rocket_rumble(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var brown := 0.0
	for i in n:
		var white := randf() * 2.0 - 1.0
		brown = (brown + white * 0.02) / 1.02
		var crackle := 0.0
		if randf() < 0.0035:
			crackle = (randf() * 2.0 - 1.0) * 0.9
		var s := brown * 3.2 + crackle
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _loop_wav(data)


## A soft, airy noise loop for the re-entry wind roar — lightly smoothed white
## noise, brighter/hissier than the rocket's brown-noise rumble so the two
## never get mistaken for each other.
func _wind_noise(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i in n:
		var white := randf() * 2.0 - 1.0
		prev = prev * 0.55 + white * 0.45
		data.encode_s16(i * 2, int(clamp(prev * vol, -1.0, 1.0) * 32767.0))
	return _loop_wav(data)


## A smooth sci-fi engine whine for the spacecraft — two slightly detuned
## sine layers (a slow shimmering beat) plus a soft filtered-noise breath,
## brighter and more electric than the rocket's brown-noise rumble so the two
## engines never get mistaken for one another.
func _spacecraft_hum(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var phase_a := 0.0
	var phase_b := 0.0
	var f_a := 140.0
	var f_b := 141.6   # detuned a couple Hz sharp — a slow shimmering beat
	for i in n:
		phase_a += f_a / MIX_RATE
		phase_b += f_b / MIX_RATE
		var tone := (sin(phase_a * TAU) + sin(phase_b * TAU)) * 0.5
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.08
		var s := tone * 0.75 + lp * 0.5
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _loop_wav(data)


## A turbofan loop for the plane — a detuned high turbine whine over a fan
## fundamental and a deep low-passed roar. Unmistakably a JET: the whine is
## what a rocket rumble and the sci-fi spacecraft hum both lack, and
## jet_engine_set() pitch-sweeps the whole loop so spool-up sounds like a
## real N1 climb. Tone frequencies complete whole cycles over `dur` so the
## buffer loops without a click.
func _jet_loop(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var hiss := 0.0
	var roar := 0.0
	var pa := 0.0
	var pb := 0.0
	var pc := 0.0
	for i in n:
		pa += 620.0 / MIX_RATE          # turbine whine...
		pb += 630.0 / MIX_RATE          # ...detuned pair, slow shimmer
		pc += 210.0 / MIX_RATE          # fan fundamental
		var whine := (sin(pa * TAU) + sin(pb * TAU)) * 0.5
		var fan := sin(pc * TAU)
		var white := randf() * 2.0 - 1.0
		hiss += (white - hiss) * 0.16   # bright compressor hiss
		roar += (white - roar) * 0.035  # deep combustor roar
		var s := whine * 0.28 + fan * 0.16 + hiss * 0.2 + roar * 0.66
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _loop_wav(data)


## A heavy airframe crash — a falling impact thump under a juddering
## metal-scrape layer with a debris tail. Nothing tonal or beepy about it.
func _metal_crash(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := 28.0 + 120.0 * pow(1.0 - t, 1.6)     # impact pitch falls fast
		phase += f / MIX_RATE
		var thump := sin(phase * TAU) * pow(1.0 - t, 2.2)
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.3
		var judder := 0.55 + 0.45 * sin(t * 90.0)     # tearing-metal stutter
		var scrape := lp * pow(1.0 - t, 1.2) * judder
		var s := thump * 0.95 + scrape * 0.6
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Landing-gear cycle — a steady hydraulic motor whirr that ends in a solid
## lock clunk over the last tenth of the buffer.
func _gear_whirr(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var phase := 0.0
	var clunk_phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += 84.0 / MIX_RATE
		var motor := (2.0 * fmod(phase, 1.0) - 1.0) * 0.4      # saw motor buzz
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.12
		var s := (motor + lp * 0.35) * minf(t * 8.0, 1.0)      # soft attack
		if t > 0.88:
			clunk_phase += 62.0 / MIX_RATE
			s += sin(clunk_phase * TAU) * (1.0 - t) * 8.0 * 0.9  # lock thud
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / float(n)
		var s := (randf() * 2.0 - 1.0) * env * vol
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Fallback Iron Man palm-blast if the baked bank is missing. A capacitor
## snap + air whomp + band-limited plasma hiss — no musical sine sweep.
## The real takes live in assets/audio/repulsor_*.wav.
func _repulsor(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var brown := 0.0
	var plasma_lp := 0.0
	for i in n:
		var tsec := float(i) / MIX_RATE
		var snap := 0.0
		if i == 3:
			snap = 0.9
		elif i == 4:
			snap = -0.7
		var whomp_env: float = exp(-tsec / 0.05) * clampf(tsec / 0.004, 0.0, 1.0)
		var whomp_f := 62.0 * (1.0 - 0.3 * clampf(tsec / 0.12, 0.0, 1.0))
		var whomp: float = sin(TAU * whomp_f * tsec) * whomp_env
		var white := randf() * 2.0 - 1.0
		brown = (brown + white * 0.03) / 1.03
		plasma_lp += (white - plasma_lp) * 0.22
		var plasma_env: float = (1.0 - exp(-tsec / 0.006)) * exp(-tsec / 0.07)
		var hiss_env: float = exp(-tsec / 0.04) * clampf(tsec / 0.003, 0.0, 1.0)
		var s := snap + whomp * 0.9 + brown * 0.45 * whomp_env + plasma_lp * plasma_env * 0.55 + white * hiss_env * 0.12
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


## The shoulder missile launch — a low ignition "thunk" under a rising
## filtered-noise whoosh as the round clears the rail. Airier and lower than
## the repulsor's tight pew so the two suit weapons stay distinct.
func _missile_launch(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var white := randf() * 2.0 - 1.0
		lp = lp + (white - lp) * (0.05 + 0.5 * t)            # low-pass opens up
		var whoosh := lp * clampf(t / 0.05, 0.0, 1.0) * (1.0 - t)
		var thump: float = sin(TAU * (70.0 + 40.0 * (1.0 - t)) * (t * dur)) * pow(0.0004, t) * 0.8
		var s := whoosh * 1.5 + thump
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Noise-only gunshot fallback (no sine crack — that was the plastic "pew").
## Real reports come from the baked banks; this is only used if they fail to
## load. Layers: impulse snap, band-limited noise crack, damped body, room tail.
func _gunshot(dur: float, snap_amt: float, boom: float, body_freq: float,
		body_amt: float, tail_amt: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var crack_lp := 0.0
	var tail_lp := 0.0
	var brown := 0.0
	for i in n:
		var tsec := float(i) / MIX_RATE
		var t := float(i) / float(n)
		var snap := 0.0
		if i == 2:
			snap = snap_amt
		elif i == 3:
			snap = -snap_amt * 0.8
		var white := randf() * 2.0 - 1.0
		crack_lp += (white - crack_lp) * 0.45
		var crack := (white - crack_lp) * exp(-tsec / 0.008) * 0.7
		var body_env: float = exp(-tsec / 0.045)
		var body: float = sin(TAU * body_freq * tsec) * body_env * body_amt
		brown = (brown + white * 0.02) / 1.02
		tail_lp += (white - tail_lp) * 0.12
		var tail := (tail_lp * 0.7 + brown * 0.4) * (1.0 - t) * (1.0 - t) * tail_amt
		var s := snap + crack + body * boom + tail
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0))
	return _wav(data)


## The RPG's launch — a heavier, more mechanical cousin of the suit's
## _missile_launch: a lower ignition thump under a bigger, slower-opening
## noise whoosh, sized for a shoulder-fired rocket rather than a wrist-mounted
## repeater.
func _rpg_launch(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var thump_env: float = pow(0.0008, t / 0.1)
		var thump: float = sin(TAU * 58.0 * (t * dur)) * thump_env * 0.9
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.32
		var whoosh := lp * clampf(t / 0.08, 0.0, 1.0) * pow(1.0 - t, 1.5) * 1.2
		var s := thump + whoosh
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


## A deep sub-bass boom + soft low-pass'd noise tail, layered under the
## recorded sniper sample (see shoot_sniper()) to give it more weight without
## touching the recording itself.
func _sniper_tail(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env: float = pow(0.002, t / 0.6)
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.15
		var sub := sin(TAU * 52.0 * (t * dur)) * env * 0.65
		var s := (lp * 0.8 + sub) * env
		data.encode_s16(i * 2, int(clamp(s * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = MIX_RATE
	st.stereo = false
	st.data = data
	return st

## Load a 16-bit PCM WAV from disk (mono or stereo). Bypasses the importer
## so newly-baked combat takes work on the first run, before Godot has
## written .godot/imported hashes.
func _load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var off := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var pcm := PackedByteArray()
	while off + 8 <= bytes.size():
		var chunk := bytes.slice(off, off + 4).get_string_from_ascii()
		var size := bytes.decode_u32(off + 4)
		var start := off + 8
		if chunk == "fmt ":
			channels = bytes.decode_u16(start + 2)
			rate = bytes.decode_u32(start + 4)
			bits = bytes.decode_u16(start + 14)
		elif chunk == "data":
			pcm = bytes.slice(start, start + size)
			break
		off = start + size + (size & 1)
	if pcm.is_empty() or bits != 16:
		return null
	if channels == 2:
		var mono := PackedByteArray()
		mono.resize(pcm.size() / 2)
		var o := 0
		for i in range(0, pcm.size() - 3, 4):
			var l := pcm.decode_s16(i)
			var r := pcm.decode_s16(i + 2)
			mono.encode_s16(o, int((l + r) / 2))
			o += 2
		pcm = mono
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = pcm
	return st


func _load_bank(prefix: String, count: int) -> Array:
	var bank: Array = []
	for i in count:
		var s := _load_stream("res://assets/audio/%s_%d.wav" % [prefix, i])
		if s != null:
			bank.append(s)
	return bank


func _play(stream: AudioStream, db := 0.0, pitch := 1.0) -> void:
	if _muted or stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## Pick a random take from a recorded bank and nudge pitch/level so repeated
## shots don't sound like one sample on a loop. Empty bank → synth fallback.
func _play_bank(bank: Array, fallback: AudioStream, db: float, pitch_var := 0.035, db_var := 1.1) -> void:
	var stream: AudioStream = fallback
	if not bank.is_empty():
		stream = bank[randi() % bank.size()]
	var pitch := 1.0 + randf_range(-pitch_var, pitch_var)
	var vol := db + randf_range(-db_var, db_var * 0.35)
	_play(stream, vol, pitch)


## Generic fallback report (the real recorded sample) — used by cops, guards
## and any caller that just wants "a gunshot" without picking a specific
## weapon (see gunshot() for the full per-weapon dispatch).
func shoot() -> void:
	_play(_s_gun, -2.0 + randf_range(-0.8, 0.4), 1.0 + randf_range(-0.03, 0.03))


## The sniper's report — baked recorded boom with a dark room tail.
func shoot_sniper() -> void:
	if _bank_sniper.is_empty():
		_play(_s_gun_sniper, -1.0)
		_play(_s_sniper_tail, -6.0)
	else:
		_play_bank(_bank_sniper, _s_gun_sniper, -1.0, 0.02, 0.7)


## Per-weapon firing report — dispatches on WeaponDB.LIST's "name" field so
## every gun (PISTOL/REVOLVER/SMG/RIFLE/SHOTGUN/SNIPER/RPG) gets its own
## recorded bank instead of one shared beep. Melee weapons (FISTS/KNIFE)
## have no report and should never reach this — see _fire_weapon()'s
## `if w.sound:` guard in game.gd. Anything unrecognised falls back to shoot().
func gunshot(weapon_name: String) -> void:
	match weapon_name:
		"PISTOL":
			_play_bank(_bank_pistol, _s_gun_pistol, -2.5)
		"REVOLVER":
			_play_bank(_bank_revolver, _s_gun_revolver, -1.5, 0.028)
		"SMG":
			_play_bank(_bank_smg, _s_gun_smg, -7.5, 0.05, 1.4)
		"RIFLE":
			_play_bank(_bank_rifle, _s_gun_rifle, -1.8)
		"SHOTGUN":
			_play_bank(_bank_shotgun, _s_gun_shotgun, -0.8, 0.025, 0.8)
		"SNIPER":
			shoot_sniper()
		"RPG":
			_play(_s_gun_rpg, -2.0, 1.0 + randf_range(-0.04, 0.04))
		_:
			shoot()


func repulsor() -> void:
	_play_bank(_bank_repulsor, _s_repulsor, -3.5, 0.045, 1.0)


func missile() -> void:
	_play(_s_missile, -2.0)

func hit() -> void:
	_play(_s_hit, -6.0)

func coin() -> void:
	_play(_s_coin_a)
	await get_tree().create_timer(0.05).timeout
	_play(_s_coin_b)

func explode() -> void:
	_play(_s_explode_noise, 2.0)
	_play(_s_explode_low, 0.0)

func siren() -> void:
	_play(_s_siren_a, -10.0)
	await get_tree().create_timer(0.15).timeout
	_play(_s_siren_b, -10.0)

func engine() -> void:
	_play(_tone(60.0 + randf() * 40.0, 0.05, "sawtooth", 0.25), -14.0)

## Engine note pitched by how fast the vehicle is going (0..1).
func engine_rev(frac: float) -> void:
	_play(_tone(72.0 + clampf(frac, 0.0, 1.0) * 205.0, 0.1, "sawtooth", 0.3), -13.0)

## One-shot deep-rumble-plus-crackle swell for the instant of liftoff.
func rocket_ignite() -> void:
	_play(_s_rocket_ignite, -2.0)

## Start the continuous ascent engine loop (idempotent — safe to call every
## frame while it should be running).
func rocket_engine_start() -> void:
	if not _muted and not _rocket_player.playing:
		_rocket_player.volume_db = -60.0
		_rocket_player.pitch_scale = 0.85
		_rocket_player.play()

## Track thrust (0..1) and an altitude fade (1 low down, fading to 0 in the
## thin/vacuum upper atmosphere) onto the running loop's volume and pitch.
func rocket_engine_set(thrust: float, fade: float) -> void:
	if not _rocket_player.playing:
		return
	var base_db: float = lerp(-34.0, -6.0, clampf(thrust, 0.0, 1.0))
	_rocket_player.volume_db = base_db - (1.0 - clampf(fade, 0.0, 1.0)) * 50.0
	_rocket_player.pitch_scale = 0.85 + thrust * 0.5

## Stop the engine loop — idempotent, so callers can invoke it every frame the
## engine should be silent without worrying about double-stopping.
func rocket_engine_stop() -> void:
	if _rocket_player.playing:
		_rocket_player.stop()

## Short hissy burst — the lunar lander's vernier thrusters (descent/ascent).
func thruster() -> void:
	_play(_noise(0.16, 0.55), -8.0)
	_play(_tone(360.0, 0.14, "sawtooth", 0.3), -14.0)

## Start the re-entry wind-roar loop (idempotent).
func wind_start() -> void:
	if not _muted and not _wind_player.playing:
		_wind_player.volume_db = -36.0
		_wind_player.pitch_scale = 0.8
		_wind_player.play()

## Track re-entry progress (0 at interface, 1 deep into the burn) onto the
## wind loop so it rises the way a real re-entry roar builds.
func wind_set(intensity: float) -> void:
	if not _wind_player.playing:
		return
	_wind_player.volume_db = lerp(-36.0, -3.0, clampf(intensity, 0.0, 1.0))
	_wind_player.pitch_scale = 0.8 + intensity * 0.6

## Stop the wind loop — idempotent.
func wind_stop() -> void:
	if _wind_player.playing:
		_wind_player.stop()

## Start the spacecraft's continuous engine loop (idempotent — safe to call
## every frame while it should be running, same convention as
## rocket_engine_start()).
func spacecraft_engine_start() -> void:
	if not _muted and not _spacecraft_player.playing:
		_spacecraft_player.volume_db = -60.0
		_spacecraft_player.pitch_scale = 0.9
		_spacecraft_player.play()

## Track thrust (0..1) and a fade (1 audible, fading to 0) onto the loop.
func spacecraft_engine_set(thrust: float, fade: float) -> void:
	if not _spacecraft_player.playing:
		return
	var base_db: float = lerp(-30.0, -6.0, clampf(thrust, 0.0, 1.0))
	_spacecraft_player.volume_db = base_db - (1.0 - clampf(fade, 0.0, 1.0)) * 50.0
	_spacecraft_player.pitch_scale = 0.9 + thrust * 0.8

## Stop the spacecraft's engine loop — idempotent.
func spacecraft_engine_stop() -> void:
	if _spacecraft_player.playing:
		_spacecraft_player.stop()


## Drive the plane's turbofan loop — auto-starts on first call, so callers
## just feed it throttle (0..1) and speed fraction (0..1) every frame. The
## pitch sweep with throttle is the spool-up; speed adds a little airflow
## brightness on top.
func jet_engine_set(throttle: float, speed_frac: float) -> void:
	if _muted:
		jet_engine_stop()
		return
	if not _jet_player.playing:
		_jet_player.volume_db = -60.0
		_jet_player.play()
	var t := clampf(throttle, 0.0, 1.0)
	var s := clampf(speed_frac, 0.0, 1.0)
	_jet_player.volume_db = lerpf(-38.0, -5.0, maxf(t, s * 0.45))
	_jet_player.pitch_scale = 0.55 + t * 0.85 + s * 0.15

## Stop the turbofan loop — idempotent.
func jet_engine_stop() -> void:
	if _jet_player.playing:
		_jet_player.stop()

## Heavy airframe impact — plane collisions and belly landings.
func crash_metal() -> void:
	_play(_s_crash, -2.0)

## Landing-gear servo cycle (retract or extend).
func gear_whirr() -> void:
	_play(_s_gear, -9.0)

## Splashdown — a splash plus a low thump as the capsule settles.
func splash() -> void:
	_play(_noise(0.5, 0.75), -3.0)
	_play(_tone(200.0, 0.3, "sine", 0.4), -10.0)

## Start the looping city ambience (call once at game start).
func start_ambient() -> void:
	if not _ambient_player.playing:
		_ambient_player.play()

## Toggle the in-car radio loop.
func set_radio(on: bool) -> void:
	if on and not _radio_player.playing:
		_radio_player.play()
	elif not on and _radio_player.playing:
		_radio_player.stop()

func set_muted(v: bool) -> void:
	_muted = v
	if _ambient_player != null:
		_ambient_player.stream_paused = v
	if _radio_player != null:
		_radio_player.stream_paused = v
	if _rocket_player != null:
		_rocket_player.stream_paused = v
	if _wind_player != null:
		_wind_player.stream_paused = v
	if _spacecraft_player != null:
		_spacecraft_player.stream_paused = v

func is_muted() -> bool:
	return _muted
