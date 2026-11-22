class_name Hud
extends Control
## Painel do carro: velocidade, marcha, conta-giros, tempos de volta e,
## opcionalmente, a telemetria de cada pneu (círculo de atrito, carga,
## escorregamento longitudinal e ângulo de deriva).

var car: Car
var show_telemetry := false
var lap_info := {"current": 0.0, "last": -1.0, "best": -1.0, "lap": 1}
var message := ""
var message_timer := 0.0
var extra_line := ""

var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func flash(text: String, seconds := 2.0) -> void:
	message = text
	message_timer = seconds


func _process(delta: float) -> void:
	message_timer = maxf(0.0, message_timer - delta)
	queue_redraw()


func _fmt_time(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%06.3f" % [m, s]


func _text(pos: Vector2, text: String, size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, pos, text, align, width, size, 6, Color(0, 0, 0, 0.75))
	draw_string(_font, pos, text, align, width, size, color)


func _draw() -> void:
	if car == null:
		return
	var vs := get_viewport_rect().size
	# ---- velocímetro e marcha (canto inferior direito)
	var base := Vector2(vs.x - 330, vs.y - 60)
	_text(base + Vector2(0, -70), "%3d" % int(round(car.speed_kmh())), 110, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 220)
	_text(base + Vector2(228, -70), "km/h", 30, Color(0.8, 0.85, 0.9))
	_text(base + Vector2(228, -132), car.gear_label(), 64, Color(1.0, 0.85, 0.3))
	# Conta-giros em barra
	var bar_pos := base + Vector2(-60, -30)
	var bar_w := 360.0
	draw_rect(Rect2(bar_pos, Vector2(bar_w, 16)), Color(0, 0, 0, 0.5))
	var frac := clampf(car.engine_rpm / 7500.0, 0.0, 1.0)
	var col := Color(0.3, 0.8, 1.0) if car.engine_rpm < 6200.0 else Color(1.0, 0.3, 0.2)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * frac, 16)), col)
	draw_rect(Rect2(bar_pos + Vector2(bar_w * 7000.0 / 7500.0, 0), Vector2(2, 16)), Color.RED)
	_text(bar_pos + Vector2(0, 44), "%d rpm   %s   %s" % [int(car.engine_rpm),
		"AUTO" if car.auto_gearbox else "MANUAL", "autoblocante" if car.lsd_enabled else "dif. aberto"], 22, Color(0.85, 0.9, 0.95))
	# Pedais
	_pedal(Vector2(vs.x - 400, vs.y - 160), car.throttle, Color(0.3, 0.9, 0.4))
	_pedal(Vector2(vs.x - 380, vs.y - 160), car.brake, Color(1.0, 0.35, 0.3))

	# ---- tempos (canto superior direito)
	var tx := vs.x - 420
	_text(Vector2(tx, 60), "Volta %d" % lap_info.lap, 30)
	_text(Vector2(tx, 100), "Atual   " + _fmt_time(lap_info.current), 28)
	_text(Vector2(tx, 136), "Última  " + _fmt_time(lap_info.last), 28, Color(0.85, 0.9, 0.95))
	_text(Vector2(tx, 172), "Melhor  " + _fmt_time(lap_info.best), 28, Color(0.6, 1.0, 0.6))

	# ---- linha extra (FPS, qualidade, câmera)
	_text(Vector2(28, 44), extra_line, 22, Color(0.9, 0.93, 0.97))

	if message_timer > 0.0:
		_text(Vector2(0, vs.y * 0.3), message, 44, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	if show_telemetry:
		_draw_telemetry(Vector2(28, 90))


func _pedal(pos: Vector2, value: float, color: Color) -> void:
	draw_rect(Rect2(pos, Vector2(12, 80)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(pos + Vector2(0, 80 * (1.0 - value)), Vector2(12, 80 * value)), color)


func _draw_telemetry(origin: Vector2) -> void:
	var names := ["DE", "DD", "TE", "TD"]
	var panel := Rect2(origin, Vector2(640, 470))
	draw_rect(panel, Color(0, 0, 0, 0.55))
	_text(origin + Vector2(16, 34), "Telemetria dos pneus", 26)
	for i in 4:
		var w: Dictionary = car.wheels[i]
		var cell := origin + Vector2(16 + (i % 2) * 310, 60 + (i / 2) * 200)
		# Círculo de atrito: ponto = (Fy, Fx) / (μ·Fz)
		var c := cell + Vector2(70, 80)
		var r := 62.0
		draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.2))
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(1, 1, 1, 0.2))
		var lim: float = maxf(1.0, (w.mu as float) * (w.fz as float))
		var p := Vector2((w.fy as float) / lim, -(w.fx as float) / lim)
		var used := p.length()
		var dot_col := Color(0.3, 1.0, 0.4) if used < 0.85 else (Color(1.0, 0.85, 0.2) if used < 0.98 else Color(1.0, 0.3, 0.2))
		draw_circle(c + p.limit_length(1.2) * r, 7.0, dot_col)
		_text(cell + Vector2(0, 14), names[i], 22, Color(1, 0.85, 0.3))
		var tx := cell + Vector2(150, 30)
		_text(tx, "carga %.2f kN" % ((w.fz as float) / 1000.0), 20)
		_text(tx + Vector2(0, 28), "κ %+.3f" % (w.kappa as float), 20)
		_text(tx + Vector2(0, 56), "α %+.1f°" % rad_to_deg(w.alpha as float), 20)
		_text(tx + Vector2(0, 84), "μ %.2f" % (w.mu as float), 20, Color(0.8, 0.85, 0.9))
		_text(tx + Vector2(0, 112), "uso %3d%%" % int(used * 100.0), 20, dot_col)
