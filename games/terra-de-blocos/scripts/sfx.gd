class_name Sfx
extends Node
## Efeitos sonoros sintetizados na inicialização (nenhum arquivo de áudio).

const RATE := 22050

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 3
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_sounds["shoot"] = _make(0.16, func(t: float, k: float) -> float: return _sq(900.0 - 500.0 * k, t) * (1.0 - k) * 0.5)
	_sounds["hit"] = _make(0.12, func(t: float, k: float) -> float: return (_noise() * 0.7 + _sq(180.0, t) * 0.3) * (1.0 - k))
	_sounds["crit"] = _make(0.25, func(t: float, k: float) -> float: return (_sq(660.0, t) * 0.4 + _sq(990.0, t) * 0.3 + _noise() * 0.3 * (1.0 - k)) * (1.0 - k))
	_sounds["boom"] = _make(0.6, func(t: float, k: float) -> float: return (_noise() * 0.8 + sin(TAU * (70.0 - 40.0 * k) * t) * 0.6) * pow(1.0 - k, 2.0))
	_sounds["coin"] = _make(0.18, func(t: float, k: float) -> float: return _sq(1320.0 if k > 0.35 else 990.0, t) * (1.0 - k) * 0.35)
	_sounds["freeze"] = _make(0.4, func(t: float, k: float) -> float: return sin(TAU * (1800.0 + 900.0 * sin(t * 60.0)) * t) * (1.0 - k) * 0.35)
	_sounds["shatter"] = _make(0.45, func(t: float, k: float) -> float: return (_noise() * 0.7 + sin(TAU * 2400.0 * t) * 0.3 * (1.0 - k)) * pow(1.0 - k, 1.5))
	_sounds["roll"] = _make(0.15, func(t: float, k: float) -> float: return _noise() * 0.35 * sin(k * PI))
	_sounds["hurt"] = _make(0.25, func(t: float, k: float) -> float: return _sq(300.0 - 180.0 * k, t) * (1.0 - k) * 0.45)
	_sounds["swing"] = _make(0.14, func(t: float, k: float) -> float: return _noise() * 0.4 * sin(k * PI) * (0.5 + 0.5 * k))
	_sounds["jingle"] = _make(0.9, func(t: float, k: float) -> float:
		var notes := [523.0, 659.0, 784.0, 1047.0]
		var n: float = notes[mini(int(k * 4.0), 3)]
		return _sq(n, t) * 0.3 * (1.0 - fmod(k * 4.0, 1.0) * 0.6))


func play(name: String, pitch_jitter := 0.08) -> void:
	if not _sounds.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[name]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _sq(freq: float, t: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _make(seconds: float, gen: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(gen.call(t, float(i) / n), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 22000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
