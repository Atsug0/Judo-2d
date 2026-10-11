extends Node
## Son du jeu (autoload « Sound ») : bus Musique / Bruitages, lecteurs de bruitages
## en pool, musique en fondu enchaîné, ambiance de foule pilotée par l'intensité.
## Tous les fichiers sont générés par tools/audio/gen_audio.py.
## Rien ici ne touche à la simulation : le son est purement cosmétique (et donc
## sans effet sur le déterminisme ni sur le futur rollback en ligne).

const Settings := preload("res://scripts/settings.gd")

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const POOL_SIZE := 24
const LOOPING_MUSIC := ["menu", "match", "dojo"]

var _cache := {}            # nom → AudioStream (ou null si absent)
var _variants := {}         # nom → nombre de variantes nom_0, nom_1…
var _pool: Array = []
var _next := 0
var _music: Array = []      # deux lecteurs pour le fondu enchaîné
var _music_idx := 0
var _music_name := ""
var _crowd: AudioStreamPlayer
var _crowd_on := false
var _crowd_level := 0.3
var _rng := RandomNumberGenerator.new()
var muted := false          # coupe les bruitages (avance rapide des vidéos)
var _fades := []            # [lecteur, de_db, vers_db, durée, t, arrêter_à_la_fin]


func _ready() -> void:
	_rng.seed = 1964
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("Music")
	_make_bus("SFX")
	# limiteur sur le master : plus de présence sans saturer quand tout tombe en même temps
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.pre_gain_db = 6.0
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_crowd = AudioStreamPlayer.new()
	_crowd.bus = "SFX"
	_crowd.volume_db = -80.0
	add_child(_crowd)
	apply_volumes()


func _make_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


## Volumes des options (0..10) → bus.
func apply_volumes() -> void:
	for pair in [["Master", "volume_master"], ["Music", "volume_music"], ["SFX", "volume_sfx"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx < 0:
			continue
		var v := float(Settings.value(pair[1])) / 10.0
		AudioServer.set_bus_mute(idx, v <= 0.0)
		# courbe perceptive : 10 → 0 dB, 5 → env. -12 dB, 1 → env. -40 dB
		AudioServer.set_bus_volume_db(idx, linear_to_db(pow(maxf(v, 0.001), 2.0)))


# --- Chargement ------------------------------------------------------------------

func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	_cache[path] = s
	return s


func _count_variants(sound_name: String) -> int:
	if not _variants.has(sound_name):
		var n := 0
		while ResourceLoader.exists("%s%s_%d.wav" % [SFX_DIR, sound_name, n]):
			n += 1
		_variants[sound_name] = n
	return _variants[sound_name]


## Joue un bruitage. « sound_name » peut désigner une famille de variantes
## (grip → grip_0..grip_3, tirée au hasard).
func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_var: float = 0.04) -> void:
	if muted:
		return
	var path := SFX_DIR + sound_name + ".wav"
	if not ResourceLoader.exists(path):
		var n := _count_variants(sound_name)
		if n == 0:
			return
		path = "%s%s_%d.wav" % [SFX_DIR, sound_name, _rng.randi_range(0, n - 1)]
	var s := _stream(path)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-pitch_var, pitch_var)))
	p.play()


## Bruit de navigation dans les menus.
func ui(action: String) -> void:
	match action:
		"up", "down", "left", "right":
			play("ui_move", -4.0, 1.0, 0.02)
		"accept", "start":
			play("ui_accept", -3.0, 1.0, 0.0)
		"back":
			play("ui_back", -4.0, 1.0, 0.0)
		"next", "prev":
			play("ui_tab", -4.0, 1.0, 0.0)


# --- Musique ---------------------------------------------------------------------

func music(track: String, fade: float = 0.8) -> void:
	if track == _music_name:
		return
	_music_name = track
	var old: AudioStreamPlayer = _music[_music_idx]
	if old.playing:
		_fade(old, old.volume_db, -60.0, fade, true)
	if track == "":
		return
	var s := _stream(MUSIC_DIR + track + ".ogg")
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = track in LOOPING_MUSIC
	_music_idx = 1 - _music_idx
	var p: AudioStreamPlayer = _music[_music_idx]
	p.stream = s
	p.volume_db = -60.0
	p.play()
	_fade(p, -60.0, 0.0, fade, false)


func current_music() -> String:
	return _music_name


# --- Foule -----------------------------------------------------------------------

## Active ou coupe l'ambiance de salle (combats).
func crowd(on: bool) -> void:
	if on == _crowd_on:
		return
	_crowd_on = on
	if on:
		var s := _stream(SFX_DIR + "crowd_loop.wav")
		if s == null:
			return
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		_crowd.stream = s
		_crowd.volume_db = -60.0
		_crowd.play()


## Intensité de la foule (0 calme … 1 en délire), lissée image par image.
func crowd_level(x: float) -> void:
	_crowd_level = clampf(x, 0.0, 1.0)


func _process(delta: float) -> void:
	if _crowd.playing:
		var target := -60.0
		if _crowd_on:
			target = lerpf(-16.0, -4.0, _crowd_level)
		_crowd.volume_db = move_toward(_crowd.volume_db, target, 40.0 * delta)
		if not _crowd_on and _crowd.volume_db <= -59.0:
			_crowd.stop()
	for f in _fades.duplicate():
		var p: AudioStreamPlayer = f[0]
		f[4] += delta
		var k := clampf(f[4] / maxf(f[3], 0.001), 0.0, 1.0)
		p.volume_db = lerpf(f[1], f[2], k)
		if k >= 1.0:
			_fades.erase(f)
			if f[5]:
				p.stop()


func _fade(p: AudioStreamPlayer, from_db: float, to_db: float, dur: float, stop_after: bool) -> void:
	for f in _fades.duplicate():
		if f[0] == p:
			_fades.erase(f)
	_fades.append([p, from_db, to_db, dur, 0.0, stop_after])
