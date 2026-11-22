class_name EngineAudio
extends AudioStreamPlayer
## Som do motor sintetizado na hora: harmônicos da frequência de explosão
## (motor de 4 cilindros = 2 explosões por volta) + chiado dos pneus.

const RATE := 22050.0

var car: Car
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _rng := RandomNumberGenerator.new()
var _noise_lp := 0.0
var _smooth_rpm := 900.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -6.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(delta: float) -> void:
	if _playback == null or car == null:
		return
	_smooth_rpm = lerpf(_smooth_rpm, car.engine_rpm, clampf(delta * 12.0, 0.0, 1.0))
	var f0 := _smooth_rpm / 30.0
	var load := 0.35 + 0.65 * car.throttle
	var slip := 0.0
	for w in car.wheels:
		var lim: float = maxf(1.0, (w.mu as float) * (w.fz as float))
		var used := Vector2(w.fx as float, w.fy as float).length() / lim
		slip = maxf(slip, clampf((used - 0.85) * 4.0, 0.0, 1.0) * clampf(absf(car.speed) / 5.0, 0.0, 1.0))
	var frames := _playback.get_frames_available()
	var step := f0 / RATE
	for i in frames:
		_phase = fmod(_phase + step, 1.0)
		var p := _phase * TAU
		var s := sin(p) * 0.45 + sin(2.0 * p) * 0.25 * load + sin(3.0 * p) * 0.12 + sin(0.5 * p) * 0.18
		s *= 0.22 + 0.25 * load
		# Chiado: ruído filtrado
		_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.35)
		s += _noise_lp * slip * 0.25
		_playback.push_frame(Vector2(s, s))
