extends Node3D
## Simulador de Carro: monta o mundo, liga controles, câmeras, voltas,
## piloto automático (modo demonstração) e os testes automáticos.
##
## Controle: RT acelera, LT freia, analógico esquerdo esterça, B freio de mão,
##           RB/LB sobe/desce marcha, Y câmera, X recoloca na pista,
##           direcional: cima telemetria, baixo câmbio auto/manual,
##           esquerda piloto automático, direita qualidade. Select sai.
## Teclado:  W/S ou setas, A/D, Espaço, E/Q, C, R, T, M, P, G, Esc.

const QUALITY := [
	{"name": "Baixa", "shadows": false, "scale": 0.7, "msaa": Viewport.MSAA_DISABLED, "trees": 250},
	{"name": "Média", "shadows": true, "scale": 1.0, "msaa": Viewport.MSAA_DISABLED, "trees": 600},
	{"name": "Alta", "shadows": true, "scale": 1.0, "msaa": Viewport.MSAA_2X, "trees": 1000},
]
const CAMERAS := ["Perseguição", "Capô", "Cockpit", "TV"]

var track: Track
var car: Car
var hud: Hud
var cam: Camera3D
var sun: DirectionalLight3D
var audio: EngineAudio

var quality := 1
var cam_mode := 0
var autopilot := false
var _cam_pos := Vector3.ZERO
var _kb_steer := 0.0
var _last_idx := 0
var _lap_time := 0.0
var _lap_running := false
var _sectors := [false, false]
var _test_mode := ""
var _force_asphalt := false


func _ready() -> void:
	_test_mode = OS.get_environment("SIMCAR_TEST")
	_setup_input()
	_make_environment()
	track = Track.new()
	add_child(track)
	track.build(1000 if _test_mode == "" else 300)

	car = Car.new()
	add_child(car)
	_place_at_start()
	car.gear_changed.connect(func(_g: int) -> void: pass)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	_cam_pos = car.global_position + Vector3(0, 3, 8)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.car = car
	layer.add_child(hud)

	if _test_mode == "":
		audio = EngineAudio.new()
		audio.car = car
		add_child(audio)

	_apply_quality()
	hud.flash("Simulador de Carro — RT acelera, LT freia", 4.0)
	if _test_mode != "":
		_run_tests.call_deferred()


func _place_at_start() -> void:
	var i := track.points.size() - 12  # um pouco antes da linha de largada
	var p := track.points[i] + Vector3(0, 0.75, 0)
	car.reset_to(p, track.tangents[i])
	_last_idx = i
	_lap_running = false
	_sectors = [false, false]


func _reset_on_track() -> void:
	var l := track.lookup(car.global_position)
	var i: int = l.idx if l.idx >= 0 else _last_idx
	car.reset_to(track.points[i] + Vector3(0, 0.75, 0), track.tangents[i])
	hud.flash("Carro recolocado na pista")


# ---------------------------------------------------------------- mundo

func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.36, 0.74)
	sky_mat.sky_horizon_color = Color(0.58, 0.69, 0.84)
	sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.5)
	sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0006
	env.fog_light_color = Color(0.75, 0.82, 0.9)
	env.glow_enabled = true
	env.glow_intensity = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _apply_quality() -> void:
	var q: Dictionary = QUALITY[quality]
	sun.shadow_enabled = q.shadows
	get_viewport().scaling_3d_scale = q.scale
	get_viewport().msaa_3d = q.msaa
	for c in track.get_children():
		if c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			mm.visible_instance_count = mini(q.trees, mm.instance_count)


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if _test_mode == "":
		_read_controls(delta)
	# Aderência de cada roda conforme o piso (asfalto, zebra, grama).
	var xf := car.global_transform
	for i in 4:
		var s := Vector2(Track.MU_ASPHALT, 1.0) if _force_asphalt else track.surface_at(xf * (car.wheels[i].mount as Vector3))
		car.surface_mu[i] = s.x
		car.surface_roll[i] = s.y
	if autopilot:
		_drive_autopilot()
	_update_lap(delta)


func _read_controls(delta: float) -> void:
	var thr := maxf(Input.get_action_strength("throttle"), 0.0)
	var brk := maxf(Input.get_action_strength("brake"), 0.0)
	var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	# Teclado: rampa suave (no controle o analógico já é proporcional).
	var kb := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb += 1.0
	if kb != 0.0 or _kb_steer != 0.0:
		_kb_steer = move_toward(_kb_steer, kb, delta * (3.0 if kb != 0.0 else 5.0))
		if absf(steer) < absf(_kb_steer) or kb != 0.0:
			steer = _kb_steer
	if autopilot and (thr > 0.1 or brk > 0.1 or absf(steer) > 0.2):
		autopilot = false
		hud.flash("Piloto automático desligado")
	if not autopilot:
		car.throttle_in = thr
		car.brake_in = brk
		car.steer_input = clampf(steer, -1.0, 1.0)
	car.handbrake = Input.get_action_strength("handbrake")


func _drive_autopilot() -> void:
	var l := track.lookup(car.global_position)
	var i: int = l.idx if l.idx >= 0 else _last_idx
	var v := absf(car.speed)
	var target := track.points[track.index_ahead(i, 7.0 + v * 0.55)]
	var local := car.global_transform.affine_inverse() * target
	var angle := atan2(local.x, -local.z)
	var max_angle := Car.MAX_STEER / (1.0 + v / 22.0)
	car.steer_input = clampf(angle / max_angle, -1.0, 1.0)
	var v_target := track.speed_profile[track.index_ahead(i, 6.0 + v * 0.35)]
	var err := v_target - v
	car.throttle_in = clampf(err * 0.35, 0.0, 1.0)
	car.brake_in = clampf(-err * 0.25, 0.0, 1.0)


func _update_lap(delta: float) -> void:
	var l := track.lookup(car.global_position)
	if l.idx < 0:
		return
	var n := track.points.size()
	var idx: int = l.idx
	if _lap_running:
		_lap_time += delta
		if idx > n / 3 and idx < n / 2:
			_sectors[0] = true
		if idx > 2 * n / 3 and idx < 5 * n / 6:
			_sectors[1] = true
	# Cruzou a linha de largada (índice volta do fim para o começo)
	if _last_idx > n * 0.9 and idx < n * 0.1:
		if _lap_running and _sectors[0] and _sectors[1]:
			hud.lap_info.last = _lap_time
			if hud.lap_info.best < 0.0 or _lap_time < hud.lap_info.best:
				hud.lap_info.best = _lap_time
				hud.flash("Melhor volta! " + hud._fmt_time(_lap_time), 3.0)
			hud.lap_info.lap += 1
		_lap_running = true
		_lap_time = 0.0
		_sectors = [false, false]
	_last_idx = idx
	hud.lap_info.current = _lap_time if _lap_running else 0.0


func _process(delta: float) -> void:
	_update_camera(delta)
	hud.extra_line = "FPS %d   |   Qualidade: %s   |   Câmera: %s%s" % [
		Engine.get_frames_per_second(), QUALITY[quality].name, CAMERAS[cam_mode],
		"   |   PILOTO AUTOMÁTICO" if autopilot else ""]


func _update_camera(delta: float) -> void:
	cam.cull_mask = 0xFFFFF & ~2 if cam_mode == 2 else 0xFFFFF
	var xf := car.global_transform
	var fwd := -xf.basis.z
	match cam_mode:
		0:  # perseguição suave
			var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
			var desired := car.global_position - flat_fwd * 7.5 + Vector3(0, 2.6, 0)
			_cam_pos = _cam_pos.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
			cam.global_position = _cam_pos
			cam.look_at(car.global_position + flat_fwd * 4.0 + Vector3(0, 0.8, 0), Vector3.UP)
			cam.fov = 68.0 + clampf(car.speed_kmh() / 12.0, 0.0, 10.0)
		1:  # capô
			cam.global_transform = xf * Transform3D(Basis(), Vector3(0, 0.75, -0.9))
			cam.fov = 75.0
		2:  # cockpit (sem cabine/teto, camada 2)
			cam.global_transform = xf * Transform3D(Basis.from_euler(Vector3(-0.06, 0, 0)), Vector3(-0.35, 0.58, -0.05))
			cam.fov = 72.0
		3:  # câmera de TV: ponto fixo perto da pista, segue o carro
			var l := track.lookup(car.global_position)
			var i: int = (l.idx if l.idx >= 0 else 0) / 40 * 40
			var p := track.points[(i + 20) % track.points.size()] + track.rights[i] * 16.0 + Vector3(0, 5, 0)
			cam.global_position = p
			cam.look_at(car.global_position, Vector3.UP)
			cam.fov = clampf(30.0 + p.distance_to(car.global_position) * 0.25, 20.0, 60.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	elif event.is_action_pressed("shift_up"):
		car.shift_up()
	elif event.is_action_pressed("shift_down"):
		car.shift_down()
	elif event.is_action_pressed("camera"):
		cam_mode = (cam_mode + 1) % CAMERAS.size()
		_cam_pos = car.global_position + Vector3(0, 3, 0)
	elif event.is_action_pressed("reset_car"):
		_reset_on_track()
	elif event.is_action_pressed("telemetry"):
		hud.show_telemetry = not hud.show_telemetry
	elif event.is_action_pressed("gearbox_mode"):
		car.auto_gearbox = not car.auto_gearbox
		hud.flash("Câmbio " + ("automático" if car.auto_gearbox else "manual (LB/RB)"))
	elif event.is_action_pressed("autopilot"):
		autopilot = not autopilot
		hud.flash("Piloto automático " + ("ligado" if autopilot else "desligado"))
	elif event.is_action_pressed("cycle_quality"):
		quality = (quality + 1) % QUALITY.size()
		_apply_quality()
		hud.flash("Qualidade: " + QUALITY[quality].name)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_L:
		car.lsd_enabled = not car.lsd_enabled
		hud.flash("Diferencial " + ("autoblocante" if car.lsd_enabled else "aberto"))


# ---------------------------------------------------------------- controles

func _setup_input() -> void:
	_axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0, [KEY_W, KEY_UP])
	_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0, [KEY_S, KEY_DOWN])
	_axis("steer_left", JOY_AXIS_LEFT_X, -1.0, [])
	_axis("steer_right", JOY_AXIS_LEFT_X, 1.0, [])
	_button("handbrake", JOY_BUTTON_B, [KEY_SPACE])
	_button("shift_up", JOY_BUTTON_RIGHT_SHOULDER, [KEY_E])
	_button("shift_down", JOY_BUTTON_LEFT_SHOULDER, [KEY_Q])
	_button("camera", JOY_BUTTON_Y, [KEY_C])
	_button("reset_car", JOY_BUTTON_X, [KEY_R])
	_button("telemetry", JOY_BUTTON_DPAD_UP, [KEY_T])
	_button("gearbox_mode", JOY_BUTTON_DPAD_DOWN, [KEY_M])
	_button("autopilot", JOY_BUTTON_DPAD_LEFT, [KEY_P])
	_button("cycle_quality", JOY_BUTTON_DPAD_RIGHT, [KEY_G])
	_button("quit_game", JOY_BUTTON_BACK, [KEY_ESCAPE])


func _ensure(action: String, deadzone: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)


func _axis(action: String, axis: JoyAxis, value: float, keys: Array) -> void:
	_ensure(action, 0.08)
	var j := InputEventJoypadMotion.new()
	j.axis = axis
	j.axis_value = value
	j.device = -1
	InputMap.action_add_event(action, j)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _button(action: String, button: JoyButton, keys: Array) -> void:
	_ensure(action, 0.5)
	var j := InputEventJoypadButton.new()
	j.button_index = button
	j.device = -1
	InputMap.action_add_event(action, j)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


# ---------------------------------------------------------------- testes
# SIMCAR_TEST=physics  -> testes de física (rode com --headless --fixed-fps 60)
# SIMCAR_TEST=shots:/pasta -> capturas de tela

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _place_test(pos: Vector3) -> void:
	car.reset_to(pos + Vector3(0, 0.75, 0), Vector3(0, 0, -1))
	await _wait(1.0)


func _run_tests() -> void:
	if _test_mode == "physics":
		await _physics_tests()
	elif _test_mode.begins_with("shots:"):
		await _screenshot_tests(_test_mode.substr(6))
	get_tree().quit()


func _physics_tests() -> void:
	var area := Vector3(-900, 0, 900)  # campo aberto, longe da pista
	_force_asphalt = true  # testes como se fosse asfalto
	# 1) 0-100 km/h
	await _place_test(area)
	print("TEST repouso: altura=%.3f m, cargas=%s" % [car.global_position.y,
		str(car.wheels.map(func(w: Dictionary) -> int: return int(w.fz)))])
	var t := 0.0
	car.throttle_in = 1.0
	var next_print := 0.0
	while car.speed_kmh() < 100.0 and t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if OS.get_environment("SIMCAR_DEBUG") != "" and t >= next_print:
			next_print += 1.0
			var w2: Dictionary = car.wheels[2]
			var w0: Dictionary = car.wheels[0]
			print("DBG t=%.0f v=%.1f rpm=%d g=%s drv=%.0f k=%.3f fxR=%.0f fxF=%.0f fzR=%.0f omegaR=%.1f lin=%.2f" % [t, car.speed_kmh(), car.engine_rpm, car.gear_label(), w2.drive, w2.kappa, w2.fx, w0.fx, w2.fz, w2.omega, car.linear_velocity.length()])
	print("TEST 0-100 km/h: %.2f s (marcha %s)" % [t, car.gear_label()])
	# 2) frenagem 100-0
	var start := car.global_position
	car.throttle_in = 0.0
	car.brake_in = 1.0
	t = 0.0
	var v0 := car.speed
	while car.speed > 0.3 and t < 15.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	var dist := start.distance_to(car.global_position)
	print("TEST frenagem %.0f-0 km/h (ABS): %.1f m em %.2f s (média %.2f g)" % [v0 * 3.6, dist, t, v0 * v0 / (2.0 * dist) / 9.81])
	car.brake_in = 0.0
	# 3) skidpad: círculo de 40 m, velocidade subindo até o carro sair do raio
	var center := area + Vector3(300, 0, 0)
	var radius := 40.0
	await _place_test(center + Vector3(radius, 0, 0))
	t = 0.0
	var lat_max := 0.0
	var v_at := 0.0
	var v_target := 30.0 / 3.6
	while t < 90.0:
		await get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		var pos := car.global_position
		var rel := Vector3(pos.x - center.x, 0, pos.z - center.z)
		var ang := atan2(rel.z, rel.x)
		var look := center + Vector3(cos(ang - 0.25), 0, sin(ang - 0.25)) * radius
		var local := car.global_transform.affine_inverse() * look
		var max_angle := Car.MAX_STEER / (1.0 + absf(car.speed) / 22.0)
		car.steer_input = clampf(atan2(local.x, -local.z) / max_angle, -1.0, 1.0)
		if t > 6.0:
			v_target += dt * 0.4 / 3.6 * 3.0
		var err := v_target - car.speed
		car.throttle_in = clampf(err * 0.8, 0.0, 1.0)
		car.brake_in = 0.0
		var dev := absf(rel.length() - radius)
		if t > 8.0 and dev < 1.0 and absf(err) < 0.6:
			var a := car.speed * car.speed / radius
			if a > lat_max:
				lat_max = a
				v_at = car.speed_kmh()
		if t > 8.0 and dev > 4.0:
			break
	print("TEST skidpad R=40 m: %.2f g a %.0f km/h" % [lat_max / 9.81, v_at])
	car.steer_input = 0.0
	car.throttle_in = 0.0
	# 4) volta com piloto automático
	_force_asphalt = false
	_place_at_start()
	await _wait(0.5)
	autopilot = true
	t = 0.0
	var laps_start: int = hud.lap_info.lap
	var off := 0.0
	while t < 240.0 and hud.lap_info.lap < laps_start + 2:
		await get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		if track.lookup(car.global_position).dist > Track.HALF_WIDTH + 1.0:
			off += dt
	print("TEST volta piloto automático: última %s, melhor %s, fora da pista %.1f s, pista %.0f m" % [
		hud._fmt_time(hud.lap_info.last), hud._fmt_time(hud.lap_info.best), off, track.length])
	print("TEST fim")


func _screenshot_tests(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	autopilot = true
	await _wait(6.0)
	var shots := [[0, false, "perseguicao"], [1, false, "capo"], [2, false, "cockpit"], [3, false, "tv"], [0, true, "telemetria"]]
	for s in shots:
		cam_mode = s[0]
		hud.show_telemetry = s[1]
		_cam_pos = car.global_position - (-car.global_transform.basis.z) * 7.5 + Vector3(0, 2.6, 0)
		await _wait(1.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(s[2] + ".png"))
		print("TEST shot ", s[2], " v=", int(car.speed_kmh()))
