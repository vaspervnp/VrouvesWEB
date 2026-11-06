extends Node
## Music and sound effects (art/audio, made by tools/make_audio.py from the CPC tables).

const NAMES := ["rifle", "pistol", "laser", "throw", "bash", "puff", "die", "hurt", "build",
	"error", "sell", "wave", "crush", "move"]
## like the AY channel on the CPC: a sound only cuts in over one of lower or equal priority
const PRIO := {"move": 0, "pistol": 1, "rifle": 1, "laser": 1, "throw": 1, "puff": 2, "bash": 2,
	"die": 3, "sell": 4, "build": 4, "error": 4, "crush": 5, "hurt": 6, "wave": 7}
const VOICES := 6

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _last := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		_streams[n] = load("res://art/audio/sfx_%s.wav" % n)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	var m: AudioStreamWAV = load("res://art/audio/music.wav")
	m.loop_mode = AudioStreamWAV.LOOP_FORWARD
	m.loop_begin = 0
	m.loop_end = int(m.get_length() * m.mix_rate)
	_music.stream = m
	_music.volume_db = -9.0
	add_child(_music)


func play(name: String) -> void:
	if not _streams.has(name):
		return
	var now := Time.get_ticks_msec()
	# the same shot from a dozen towers in one tick is one shot
	if _last.get(name, -1000) > now - 45:
		return
	_last[name] = now
	var best: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			best = p
			break
	if best == null:
		# take over the one playing the least important sound, if this one matters as much
		var lo := 99
		for p in _players:
			var pr: int = PRIO.get(p.get_meta("name", ""), 0)
			if pr < lo:
				lo = pr
				best = p
		if lo > PRIO.get(name, 0):
			return
	best.stream = _streams[name]
	best.set_meta("name", name)
	best.play()


func music(on: bool) -> void:
	if on and Data.music_on:
		if not _music.playing:
			_music.play()
	else:
		_music.stop()


func toggle_music() -> void:
	Data.music_on = not Data.music_on
	Data.save_settings()
	music(Data.music_on)
