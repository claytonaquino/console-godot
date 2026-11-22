extends Node3D
## Terra de Blocos — Capítulo 1 (fatia vertical).
## Estados: title -> village <-> mission -> results -> village.
## Também é o "mundo" que heróis e máquinas consultam (inimigos, projéteis,
## explosões, saque, falas).
##
## Teste automático: TDB_TEST=bot (joga sozinho as duas missões) ou
## TDB_TEST=shots:/pasta (idem, salvando capturas de tela).

const SAVE_PATH := "user://save.json"
const UP_DIR := Vector3(0.70710678, 0, -0.70710678)   # "para cima" na tela
const CAM_PITCH := 52.0

var sfx: Sfx
var fx: Fx
var hud: Hud
var cam: Camera3D
var sun: DirectionalLight3D
var level: Level
var paused := false
var state := "title"
var mission_id := ""
var heroes: Array[Hero] = []
var machines: Array[Machine] = []
var boss: Machine
var save := {}

# Missão em andamento
var m_coins := 0
var m_blocks := 0
var m_kills := 0
var m_time := 0.0
var m_downs := 0
var m_secret := false
var phase := ""
var checkpoint := Vector3.ZERO
var wave := 0
var pending_spawns := 0
var events := {}
var dormant: Array[Dictionary] = []
var arrows: Array[Dictionary] = []
var bolts: Array[Dictionary] = []
var rain: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var timers: Array[Dictionary] = []
var npcs: Array[Dictionary] = []
var all_down_t := 0.0
var switch_cd := 0.0
var solo_kind := "iara"
var npc_line := 0

# Câmera
var cam_focus := Vector3.ZERO
var cam_dist := 30.0
var shake_amt := 0.0
var _title_t := 0.0

# Entrada
var _inp: Array[Dictionary] = [{}, {}]
var _prev: Array[Dictionary] = [{}, {}]
var _menu_cb: Callable
var _menu_cancel: Callable
var _dlg_cb: Callable
var _interact := ""

# Teste
var test_mode := ""
var shots_dir := ""
var _shot_n := 0
var _shot_t := 0.0
var _bot_path: Array[Vector2i] = []
var _bot_path_t := 0.0
var _bot_last_pos := Vector3.ZERO
var _bot_stuck := 0.0
var _bot_dlg_t := 0.0
var _test_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	var t := OS.get_environment("TDB_TEST")
	if t.begins_with("shots:"):
		test_mode = "bot"
		shots_dir = t.substr(6)
		DirAccess.make_dir_recursive_absolute(shots_dir)
	elif t != "":
		test_mode = t
	_setup_world()
	_load_save()
	if test_mode == "bot":
		save = _default_save()
	if t.begins_with("view:"):
		test_mode = "view"
		_view(t.substr(5))
		return
	go_title()


func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.78, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.95)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.fog_enabled = true
	e.fog_light_color = Color(0.62, 0.78, 0.92)
	e.fog_density = 0.0009
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.7
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 32.0
	cam.near = 1.0
	cam.far = 300.0
	add_child(cam)
	cam.make_current()
	sfx = Sfx.new()
	add_child(sfx)
	fx = Fx.new()
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.main = self
	layer.add_child(hud)


# ---------------------------------------------------------------- salvar

func _default_save() -> Dictionary:
	return {"coins": 0, "blocks": 0, "up_hearts": 0, "up_damage": 0, "up_cooldown": 0, "done": [], "collect": []}


func _load_save() -> void:
	save = _default_save()
	if FileAccess.file_exists(SAVE_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if data is Dictionary:
			for k in data:
				save[k] = data[k]


func _write_save() -> void:
	if test_mode == "bot":
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


func coins_total() -> int:
	return int(save.coins) + m_coins


func blocks_total() -> int:
	return int(save.blocks) + m_blocks


func _done(id: String) -> bool:
	return (save.done as Array).has(id)


# ---------------------------------------------------------------- fases

func _clear_level() -> void:
	for h in heroes:
		if is_instance_valid(h):
			h.queue_free()
	heroes.clear()
	machines.clear()
	boss = null
	arrows.clear()
	bolts.clear()
	rain.clear()
	pickups.clear()
	timers.clear()
	dormant.clear()
	npcs.clear()
	events.clear()
	if level:
		level.queue_free()
		level = null


func _load_level(id: String) -> void:
	_clear_level()
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)
	level.build(id)
	level.lever_pulled.connect(_on_lever)
	level.wall_broken.connect(_on_wall_broken)
	level.chest_opened.connect(_on_chest)
	checkpoint = level.start_pos
	cam_focus = level.start_pos
	hud.fade = 1.0
	for p in level.cells("c"):
		_add_pickup("coin", p + Vector3(0, 0.6, 0), 5, Vector3.ZERO, true)


func go_title() -> void:
	state = "title"
	hud.prompt = ""
	_load_level("vila")
	_build_npcs()
	hud.title_active = true
	hud.results = {}
	hud.objective = ""
	var items := []
	var has_progress := not (save.done as Array).is_empty() or int(save.coins) > 0
	if has_progress:
		items.append({"label": "Continuar", "desc": "Voltar para a vila com seu progresso", "id": "continue"})
	items.append({"label": "Novo jogo", "desc": "Começar o Capítulo 1 do início", "id": "new", "bot": true})
	items.append({"label": "Como jogar", "desc": "Controles e dicas", "id": "help"})
	items.append({"label": "Sair", "desc": "Voltar para o console", "id": "quit"})
	_menu("", items, func(it: Dictionary) -> void:
		match it.id:
			"continue":
				hud.title_active = false
				start_village()
			"new":
				save = _default_save()
				_write_save()
				hud.title_active = false
				start_village(true)
			"help":
				_talk(_help_lines(), go_title)
			"quit":
				get_tree().quit()
		, Callable())
	hud.menu_title = ""


func _help_lines() -> Array:
	return [
		["Placa", "Mover: analógico esquerdo (ou WASD). Ataque: X (ou J). Rolamento: A (ou Espaço)."],
		["Placa", "Especial: Y (ou K). Habilidade: B (ou L). Trocar herói: LB (ou Tab). Pausa: Start (ou Esc)."],
		["Placa", "Iara atira flechas e congela inimigos. Bento usa lança, onda de choque e escudo."],
		["Placa", "Congele uma máquina com a flecha de gelo e acerte com a lança para DESPEDAÇAR (dano triplo)!"],
		["Placa", "Peças brilhantes são pontos fracos: destrua-as e a máquina perde aquele ataque."],
		["Placa", "Com dois controles, o Jogador 2 entra apertando Start. Fique perto de um amigo caído para reanimá-lo."],
	]


func start_village(intro := false) -> void:
	state = "village"
	mission_id = ""
	_load_level("vila")
	_build_npcs()
	_spawn_party()
	level.set_exit_active(false)
	hud.objective = "Vá ao quadro de Missões" if not _done("m2") else "Capítulo 1 concluído! Explore a vila ou repita as missões."
	if intro:
		_talk([["Zuza", "Iara! Bento! Venham aqui. O quadro de missões tem trabalho para vocês."],
			["Bento", "Trabalho? Eu achei que era hora do lanche."]], Callable())


func start_mission(id: String) -> void:
	state = "mission"
	hud.prompt = ""
	mission_id = id
	_load_level(id)
	_spawn_party()
	m_coins = 0
	m_blocks = 0
	m_kills = 0
	m_time = 0.0
	m_downs = 0
	m_secret = false
	wave = 0
	pending_spawns = 0
	for ch in ["e", "z", "h"]:
		var type: String = {"e": "rastejante", "z": "zumbidor", "h": "chifrudo"}[ch]
		for p in level.cells(ch):
			dormant.append({"type": type, "pos": p})
	_log("missão %s iniciada" % id)
	if id == "m1":
		phase = "levers"
		hud.objective = "Siga a trilha para o norte"
		_talk(Levels.TALK.m1_start, Callable())
	else:
		phase = "waves"
		hud.objective = "Proteja a vila!"
		_talk(Levels.TALK.m2_start, func() -> void: schedule(1.0, _next_wave))


func _spawn_party() -> void:
	var kinds := [solo_kind, "bento" if solo_kind == "iara" else "iara"]
	var n := 2 if heroes.size() >= 2 or _p2_joined else 1
	heroes.clear()
	for i in n:
		_make_hero(kinds[i], i, level.start_pos + Vector3(1.5 * i, 0, 0))


var _p2_joined := false


func _make_hero(kind: String, index: int, pos: Vector3) -> Hero:
	var h := Hero.new()
	h.setup(kind, self, index)
	h.apply_upgrades(save)
	h.position = pos + Vector3(0, 0.1, 0)
	level.add_child(h)
	h.downed.connect(_on_downed)
	if index < heroes.size():
		heroes[index] = h
	else:
		heroes.append(h)
	return h


func p2_available() -> bool:
	return Input.get_connected_joypads().size() >= 2


func _build_npcs() -> void:
	var names := ["Zuza", "Tico"]
	var k := 0
	for p in level.cells("N"):
		var root := Node3D.new()
		root.position = p
		level.add_child(root)
		var shirt := Color(0.55, 0.3, 0.6) if k == 0 else Color(0.3, 0.6, 0.4)
		Bricks.piece(root, Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 0.36), Color(0.3, 0.25, 0.2))
		Bricks.piece(root, Vector3(0, 1.15, 0), Vector3(0.8, 0.7, 0.44), shirt)
		Bricks.piece(root, Vector3(0, 1.78, 0), Vector3(0.5, 0.5, 0.48), Color(0.95, 0.78, 0.6), true)
		Bricks.piece(root, Vector3(0, 2.08, 0), Vector3(0.56, 0.14, 0.54), Color(0.85, 0.85, 0.85) if k == 0 else Color(0.25, 0.15, 0.1))
		var l := Label3D.new()
		l.text = names[k % 2]
		l.font_size = 56
		l.pixel_size = 0.01
		l.outline_size = 12
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, 2.7, 0)
		root.add_child(l)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.9, 2.0, 0.9)
		cs.shape = bs
		cs.position.y = 1.0
		body.add_child(cs)
		root.add_child(body)
		npcs.append({"pos": p, "name": names[k % 2], "node": root})
		k += 1


# ---------------------------------------------------------------- diálogos e menus

func _talk(lines: Array, done: Callable) -> void:
	if lines.is_empty():
		if done.is_valid():
			done.call()
		return
	_dlg_cb = done
	hud.start_dialogue(lines)
	_set_paused(true)
	_bot_dlg_t = 0.0
	for l in lines:
		_log("fala %s: %s" % [l[0], l[1]])


func _menu(title: String, items: Array, cb: Callable, cancel: Callable) -> void:
	_menu_cb = cb
	_menu_cancel = cancel
	hud.open_menu(title, items)
	_set_paused(true)
	_bot_dlg_t = 0.0


func _close_menu() -> void:
	hud.menu_active = false
	_set_paused(false)


func _set_paused(p: bool) -> void:
	paused = p
	get_tree().paused = p


func dialogue_bark(speaker: String, text: String) -> void:
	hud.bark(speaker, text)
	_log("bark %s: %s" % [speaker, text])


# ---------------------------------------------------------------- entrada

func _read(idx: int) -> Dictionary:
	var pads := Input.get_connected_joypads()
	var d := {"move": Vector2.ZERO, "attack": false, "special": false, "alt": false, "dodge": false, "switch": false,
		"start": false, "confirm": false, "cancel": false, "up": false, "down": false}
	var dev := -1
	if idx < pads.size():
		dev = pads[idx]
	var mv := Vector2.ZERO
	if dev >= 0:
		mv = Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if mv.length() < 0.2:
			mv = Vector2.ZERO
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT): mv.x = -1
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT): mv.x = 1
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP): mv.y = -1
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN): mv.y = 1
		d.attack = Input.is_joy_button_pressed(dev, JOY_BUTTON_X) or Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		d.special = Input.is_joy_button_pressed(dev, JOY_BUTTON_Y)
		d.alt = Input.is_joy_button_pressed(dev, JOY_BUTTON_B)
		d.dodge = Input.is_joy_button_pressed(dev, JOY_BUTTON_A)
		d.switch = Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_SHOULDER)
		d.start = Input.is_joy_button_pressed(dev, JOY_BUTTON_START) or Input.is_joy_button_pressed(dev, JOY_BUTTON_BACK)
		d.confirm = Input.is_joy_button_pressed(dev, JOY_BUTTON_A)
		d.cancel = Input.is_joy_button_pressed(dev, JOY_BUTTON_B)
	if idx == 0:
		var k := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if k != Vector2.ZERO:
			mv = k.normalized()
		d.attack = d.attack or Input.is_physical_key_pressed(KEY_J)
		d.special = d.special or Input.is_physical_key_pressed(KEY_K)
		d.alt = d.alt or Input.is_physical_key_pressed(KEY_L)
		d.dodge = d.dodge or Input.is_physical_key_pressed(KEY_SPACE)
		d.switch = d.switch or Input.is_physical_key_pressed(KEY_TAB)
		d.start = d.start or Input.is_physical_key_pressed(KEY_ESCAPE)
		d.confirm = d.confirm or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E)
		d.cancel = d.cancel or Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_BACKSPACE)
	d.move = mv
	d.up = mv.y < -0.6
	d.down = mv.y > 0.6
	return d


func _edge(idx: int, key: String) -> bool:
	return bool(_inp[idx].get(key, false)) and not bool(_prev[idx].get(key, false))


func _any_edge(key: String) -> bool:
	return _edge(0, key) or _edge(1, key)


# ---------------------------------------------------------------- laço principal

func _physics_process(delta: float) -> void:
	for i in 2:
		_prev[i] = _inp[i]
		_inp[i] = _read(i)
	if test_mode == "bot":
		_bot(delta)
	_test_t += delta

	if hud.dlg_active:
		_bot_dlg_t += delta
		if _any_edge("confirm") or _any_edge("attack") or (test_mode == "bot" and _bot_dlg_t > 0.25):
			_bot_dlg_t = 0.0
			if not hud.advance_dialogue():
				_set_paused(false)
				var cb := _dlg_cb
				_dlg_cb = Callable()
				if cb.is_valid():
					cb.call()
		return
	if hud.menu_active:
		_menu_input(delta)
		return
	if not hud.results.is_empty():
		if _any_edge("confirm") or _any_edge("attack") or test_mode == "bot":
			hud.results = {}
			start_village()
		return
	if state == "title":
		return

	if _any_edge("start"):
		_pause_menu()
		return
	_control_heroes(delta)
	_update_projectiles(delta)
	_update_pickups(delta)
	_update_timers(delta)
	_update_downed(delta)
	_update_flow(delta)
	if state == "mission":
		m_time += delta
		_update_mission(delta)
	elif state == "village":
		_update_village()


func _menu_input(delta: float) -> void:
	var bot_pick := -1
	if test_mode == "bot":
		_bot_dlg_t += delta
		if _bot_dlg_t > 0.3:
			for i in hud.menu_items.size():
				if hud.menu_items[i].get("bot", false) and hud.menu_items[i].get("enabled", true):
					bot_pick = i
					break
			if bot_pick < 0:
				bot_pick = hud.menu_items.size() - 1
	if _any_edge("up"):
		hud.move_menu(-1)
	elif _any_edge("down"):
		hud.move_menu(1)
	elif _any_edge("confirm") or bot_pick >= 0:
		if bot_pick >= 0:
			hud.menu_index = bot_pick
		var it: Dictionary = hud.menu_items[hud.menu_index]
		if not it.get("enabled", true):
			return
		if it.get("keep_open", false):
			_menu_cb.call(it)
			return
		_close_menu()
		_menu_cb.call(it)
	elif _any_edge("cancel") or _any_edge("start"):
		if _menu_cancel.is_valid() or state != "title":
			_close_menu()
			if _menu_cancel.is_valid():
				_menu_cancel.call()


func _pause_menu() -> void:
	var items := [{"label": "Continuar", "id": "resume"}]
	if state == "mission":
		items.append({"label": "Desistir e voltar para a vila", "desc": "As moedas desta missão serão perdidas", "id": "abandon"})
	items.append({"label": "Como jogar", "id": "help"})
	items.append({"label": "Menu inicial", "id": "title"})
	items.append({"label": "Sair do jogo", "id": "quit"})
	_menu("Pausado", items, func(it: Dictionary) -> void:
		match it.id:
			"abandon":
				m_coins = 0
				m_blocks = 0
				start_village()
			"help":
				_talk(_help_lines(), Callable())
			"title":
				go_title()
			"quit":
				get_tree().quit()
		, func() -> void: pass)


func _control_heroes(delta: float) -> void:
	switch_cd = maxf(0.0, switch_cd - delta)
	# Jogador 2 entra
	if heroes.size() < 2 and p2_available() and _edge(1, "start"):
		pass
	if heroes.size() < 2 and _edge(1, "start") and p2_available():
		_p2_joined = true
		var other := "bento" if heroes[0].kind == "iara" else "iara"
		var h := _make_hero(other, 1, heroes[0].global_position + Vector3(1.5, 0, 0))
		fx.ring(h.global_position, 2.0, Color(0.5, 1, 0.6))
		hud.toast("Jogador 2 entrou: " + h.display_name + "!")
		_prev[1]["start"] = true
	for i in heroes.size():
		var h := heroes[i]
		if not is_instance_valid(h):
			continue
		var d: Dictionary = _inp[i]
		h.in_move = d.move
		h.in_attack = d.attack
		h.in_special = _edge(i, "special")
		h.in_alt = _edge(i, "alt")
		h.in_dodge = _edge(i, "dodge")
		if state == "village" and _interact != "" and i == 0 and _edge(0, "dodge"):
			h.in_dodge = false
			_do_interact()
	if heroes.size() == 1 and _edge(0, "switch") and switch_cd <= 0.0 and not heroes[0].down:
		_switch_hero()


func _switch_hero() -> void:
	var old := heroes[0]
	var frac := float(old.hearts) / float(old.max_hearts)
	solo_kind = "bento" if old.kind == "iara" else "iara"
	var pos := old.global_position
	var face := old.facing
	old.queue_free()
	var h := _make_hero(solo_kind, 0, pos - Vector3(0, 0.1, 0))
	h.hearts = maxi(1, int(ceil(frac * h.max_hearts)))
	h.facing = face
	switch_cd = 0.8
	fx.ring(pos, 1.8, Color(1, 0.9, 0.4))
	fx.popup(pos + Vector3(0, 2.6, 0), h.display_name + "!", Color(1, 0.9, 0.4), 80)
	sfx.play("jingle", 0.0)


func _process(delta: float) -> void:
	hud.fade = maxf(0.0, hud.fade - delta * 2.0)
	_update_camera(delta)
	if shots_dir != "":
		_shot_t += delta
		if _shot_t > 9.0 and _shot_n < 24:
			_shot_t = 0.0
			_shot()


func _update_camera(delta: float) -> void:
	if state == "title" or level == null:
		_title_t += delta * 0.08
		var c := level.center() if level else Vector3.ZERO
		var dir := Vector3(sin(_title_t), 0, cos(_title_t))
		cam.global_position = c + dir * 34.0 + Vector3(0, 26, 0)
		cam.look_at(c + Vector3(0, 0, 0), Vector3.UP)
		return
	var pts: Array[Vector3] = []
	for h in heroes:
		if is_instance_valid(h):
			pts.append(h.global_position)
	if pts.is_empty():
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var spread := 0.0
	for p in pts:
		spread = maxf(spread, p.distance_to(c))
	if boss and is_instance_valid(boss) and not boss.dead:
		c = c.lerp(boss.global_position, 0.25)
		spread = maxf(spread, 8.0)
	cam_focus = cam_focus.lerp(c, clampf(delta * 4.0, 0.0, 1.0))
	var want_d := clampf(30.0 + spread * 1.2, 30.0, 48.0)
	cam_dist = lerpf(cam_dist, want_d, clampf(delta * 2.0, 0.0, 1.0))
	var pitch := deg_to_rad(CAM_PITCH)
	var off := -UP_DIR * cos(pitch) * cam_dist + Vector3.UP * sin(pitch) * cam_dist
	shake_amt = maxf(0.0, shake_amt - delta * 1.6)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake_amt * 0.6
	cam.global_position = cam_focus + off + sh
	cam.look_at(cam_focus + Vector3(0, 0.8, 0) + sh, Vector3.UP)
	# Sombra acompanha os heróis
	sun.directional_shadow_max_distance = cam_dist + 30.0


func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)


# ---------------------------------------------------------------- mundo (API usada por heróis/máquinas)

func living_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	for h in heroes:
		if is_instance_valid(h) and not h.down and h.active:
			out.append(h)
	return out


func nearest_hero(pos: Vector3) -> Hero:
	var best: Hero = null
	var bd := 1e9
	for h in living_heroes():
		var d := h.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = h
	return best


func _aim_part(m: Machine) -> Dictionary:
	for p in m.parts:
		if p.alive and p.weak and (p.name != "nucleo" or m.flags.has("core_open")):
			return p
	return m.body_part()


func nearest_enemy(pos: Vector3, max_range: float, facing: Vector3, cone: float) -> Variant:
	var best: Variant = null
	var bs := -1e9
	for m in machines:
		if not is_instance_valid(m) or m.dead:
			continue
		var d := m.global_position - pos
		d.y = 0
		var dist := d.length()
		if dist > max_range + m.radius:
			continue
		var dot := d.normalized().dot(facing) if dist > 0.1 else 1.0
		if dot < cone and dist > 3.0:
			continue
		var score := dot * 6.0 - dist
		if score > bs:
			bs = score
			best = m.part_pos(_aim_part(m))
	return best


func spawn_arrow(owner: Hero, pos: Vector3, dir: Vector3, dmg: float, ice: bool) -> void:
	# Mira em 3D (máquinas altas têm pontos fracos lá em cima)
	var t: Variant = nearest_enemy(pos, 18.0, dir, 0.85)
	if t != null:
		var tp: Vector3 = t
		dir = (tp - pos).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = Bricks.box_mesh()
	mi.material_override = Bricks.plastic(Color(0.4, 0.9, 1.0) if ice else Color(0.95, 0.85, 0.6), true)
	mi.scale = Vector3(0.1, 0.1, 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mi)
	mi.global_position = pos
	mi.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	arrows.append({"node": mi, "pos": pos, "dir": dir, "speed": 34.0, "dmg": dmg, "ice": ice, "owner": owner, "life": 0.65})


func spawn_bolt(owner: Machine, from: Vector3, dir: Vector3, speed: float, hearts: int, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Bricks.box_mesh()
	mi.material_override = Bricks.plastic(color, true)
	mi.scale = Vector3(0.35, 0.35, 0.35)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mi)
	mi.global_position = from
	bolts.append({"node": mi, "pos": from, "dir": dir, "speed": speed, "hearts": hearts, "life": 3.0})


func melee(hero: Hero, center: Vector3, r: float, dmg: float, heavy: bool) -> void:
	var hit := false
	for m in machines.duplicate():
		if not is_instance_valid(m) or m.dead:
			continue
		var ps: Array = m.parts_in_sphere(center, r)
		var p := {}
		for q in ps:
			if q.weak and (q.name != "nucleo" or m.flags.has("core_open")):
				p = q
				break
		if p.is_empty() and not ps.is_empty():
			p = ps[0]
		if p.is_empty():
			var d: Vector3 = m.global_position - center
			d.y = 0
			if d.length() <= r + m.radius:
				p = m.body_part()
		if not p.is_empty():
			m.take(p, dmg, "melee", hero.global_position)
			hit = true
			if heavy and not m.dead and m.type in ["rastejante", "zumbidor"]:
				m.stun_t = maxf(m.stun_t, 0.4)
	if level.hit_props(center, r, dmg):
		hit = true
	if hit:
		shake(0.12)


func _area(center: Vector3, r: float, dmg: float, from: Vector3, exclude: Node = null) -> void:
	for m in machines.duplicate():
		if not is_instance_valid(m) or m.dead or m == exclude:
			continue
		var d: Vector3 = m.global_position - center
		d.y = 0
		if d.length() <= r + m.radius * 0.7:
			m.take(m.body_part(), dmg, "area", from)
	level.hit_props(center, r, dmg)


func arrow_rain(hero: Hero, center: Vector3, r: float, dmg: float) -> void:
	fx.ring(center, r, Color(0.4, 0.9, 1.0))
	for k in 14:
		var a := randf() * TAU
		var p := center + Vector3(cos(a), 0, sin(a)) * sqrt(randf()) * r
		var mi := MeshInstance3D.new()
		mi.mesh = Bricks.box_mesh()
		mi.material_override = Bricks.plastic(Color(0.95, 0.85, 0.6), true)
		mi.scale = Vector3(0.1, 0.9, 0.1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
		var h0 := 9.0 + randf() * 4.0
		mi.global_position = p + Vector3(0, h0, 0)
		rain.append({"node": mi, "y": h0, "p": p})
	var from := hero.global_position
	schedule(0.4, func() -> void:
		_area(center, r, dmg, from)
		fx.debris(center, Color(0.95, 0.85, 0.6), 10, 5.0)
		sfx.play("hit"))


func shockwave(hero: Hero, pos: Vector3, r: float, dmg: float) -> void:
	fx.ring(pos, r, Color(0.4, 0.8, 1.0))
	fx.debris(pos, Color(0.45, 0.35, 0.25), 12, 6.0)
	shake(0.35)
	_area(pos, r, dmg, pos)


func explosion(pos: Vector3, r: float, hearts: int, source: Node) -> void:
	fx.ring(pos, r, Color(1.0, 0.55, 0.15))
	fx.debris(pos + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.2), 12, 7.0)
	sfx.play("boom")
	shake(0.25)
	hit_heroes(pos, r, hearts, pos)
	_area(pos, r, 20.0, pos, source)


func hit_heroes(center: Vector3, r: float, hearts: int, from: Vector3) -> void:
	for h in living_heroes():
		var d := h.global_position - center
		if absf(d.y) > 3.0:
			continue
		d.y = 0
		if d.length() <= r + 0.45:
			h.hurt(hearts, from)


func drop_loot(pos: Vector3, coins: int, blocks: int) -> void:
	if state != "mission":
		return
	var n := clampi(coins / 3, 1, 10)
	for i in n:
		var v := coins / n + (1 if i < coins % n else 0)
		_add_pickup("coin", pos + Vector3(0, 1.0, 0), v, Vector3(randf_range(-4, 4), randf_range(5, 8), randf_range(-4, 4)))
	var nb := mini(blocks, 6)
	for i in nb:
		var v := blocks / nb + (1 if i < blocks % nb else 0)
		_add_pickup("block", pos + Vector3(0, 1.0, 0), v, Vector3(randf_range(-4, 4), randf_range(5, 8), randf_range(-4, 4)))


func spawn_machine(type: String, pos: Vector3) -> Machine:
	var m := Machine.new()
	m.setup(type, self)
	m.position = pos + Vector3(0, 2.6 if type == "zumbidor" else 0.2, 0)
	level.add_child(m)
	m.died.connect(_on_machine_died)
	machines.append(m)
	fx.debris(pos + Vector3(0, 1, 0), Color(0.6, 0.6, 0.65), 6, 4.0)
	return m


## Campo de fluxo: distância (em casas) até o herói mais próximo, para as
## máquinas contornarem casas e muros.
var _flow := {}
var _flow_t := 0.0


func _update_flow(delta: float) -> void:
	_flow_t -= delta
	if _flow_t > 0.0 or level == null:
		return
	_flow_t = 0.4
	_flow.clear()
	var q: Array[Vector2i] = []
	for h in living_heroes():
		var c := level.pos_cell(h.global_position)
		_flow[c] = 0
		q.append(c)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		var dist: int = _flow[c]
		for dd in dirs:
			var n: Vector2i = c + dd
			if not _flow.has(n) and level.is_free(n):
				_flow[n] = dist + 1
				q.append(n)


func path_dir(pos: Vector3, fallback: Vector3) -> Vector3:
	if level == null:
		return fallback
	var c := level.pos_cell(pos)
	if not _flow.has(c) or int(_flow[c]) <= 2:
		return fallback
	var best := c
	var bd: int = _flow[c]
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var n := c + Vector2i(dx, dy)
			if n == c or not _flow.has(n):
				continue
			if dx != 0 and dy != 0 and (not _flow.has(c + Vector2i(dx, 0)) or not _flow.has(c + Vector2i(0, dy))):
				continue
			if int(_flow[n]) < bd:
				bd = _flow[n]
				best = n
	if best == c:
		return fallback
	var d := level.cell_pos(best.x, best.y) - pos
	d.y = 0
	return d.normalized() * fallback.length() if fallback.length() > 0.01 else d.normalized()


func schedule(t: float, f: Callable) -> void:
	timers.append({"t": t, "f": f})


# ---------------------------------------------------------------- atualizações

func _update_projectiles(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for a in arrows.duplicate():
		var from: Vector3 = a.pos
		var to: Vector3 = from + a.dir * a.speed * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := space.intersect_ray(q)
		var end: Vector3 = hit.position if not hit.is_empty() else to
		var done := false
		for m in machines.duplicate():
			if not is_instance_valid(m) or m.dead:
				continue
			var p: Dictionary = m.hit_segment(from, end, 0.3)
			if not p.is_empty():
				m.take(p, a.dmg, "ice" if a.ice else "arrow", (a.owner as Node3D).global_position if is_instance_valid(a.owner) else from)
				if a.ice and not m.dead:
					m.freeze(2.6)
				done = true
				break
		if not done and level.hit_props(end, 0.5, a.dmg):
			done = true
		if not done and not hit.is_empty():
			fx.debris(end, Color(0.95, 0.85, 0.6), 2, 2.0)
			done = true
		a.pos = end
		a.life -= delta
		(a.node as Node3D).global_position = end
		if done or a.life <= 0.0:
			(a.node as Node).queue_free()
			arrows.erase(a)
	for b in bolts.duplicate():
		var from: Vector3 = b.pos
		var to: Vector3 = from + b.dir * b.speed * delta
		var done := false
		for h in living_heroes():
			var c := h.global_position + Vector3(0, 1.0, 0)
			var ab := to - from
			var t := clampf((c - from).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (from + ab * t).distance_to(c) < 0.75:
				h.hurt(b.hearts, from - b.dir)
				done = true
				break
		if not done:
			var q := PhysicsRayQueryParameters3D.create(from, to, 1)
			if not space.intersect_ray(q).is_empty():
				done = true
				fx.debris(to, Color(1, 0.5, 0.2), 3, 2.0)
		b.pos = to
		b.life -= delta
		(b.node as Node3D).global_position = to
		(b.node as Node3D).rotation += Vector3(delta * 9.0, delta * 7.0, 0)
		if done or b.life <= 0.0:
			(b.node as Node).queue_free()
			bolts.erase(b)
	for r in rain.duplicate():
		r.y -= delta * 30.0
		(r.node as Node3D).global_position = r.p + Vector3(0, maxf(r.y, 0.4), 0)
		if r.y <= 0.4:
			(r.node as Node).queue_free()
			rain.erase(r)


func _add_pickup(kind: String, pos: Vector3, value: int, vel: Vector3, still := false) -> void:
	var root := Node3D.new()
	level.add_child(root)
	root.global_position = pos
	if kind == "coin":
		var c := Bricks.piece(root, Vector3.ZERO, Vector3(0.5, 0.5, 0.12), Color(1.0, 0.8, 0.2), false, true)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var c := Bricks.piece(root, Vector3.ZERO, Vector3(0.5, 0.36, 0.5), Color(0.3, 0.7, 1.0), true, true)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pickups.append({"node": root, "pos": pos, "vel": vel, "kind": kind, "value": value, "t": 0.0, "still": still})


func _update_pickups(delta: float) -> void:
	for p in pickups.duplicate():
		p.t += delta
		var node: Node3D = p.node
		if not p.still:
			p.vel.y -= 22.0 * delta
			p.pos += p.vel * delta
			if p.pos.y < 0.45:
				p.pos.y = 0.45
				p.vel = Vector3(p.vel.x * 0.5, -p.vel.y * 0.35, p.vel.z * 0.5)
		var h := nearest_hero(p.pos)
		if h and p.t > 0.5:
			var to: Vector3 = h.global_position + Vector3(0, 0.8, 0) - p.pos
			if to.length() < 4.5:
				p.still = false
				p.vel = to.normalized() * 14.0
				p.pos += p.vel * delta
			if to.length() < 0.9:
				if p.kind == "coin":
					m_coins += p.value
					sfx.play("coin")
				else:
					m_blocks += p.value
					sfx.play("coin", 0.3)
				node.queue_free()
				pickups.erase(p)
				continue
		node.global_position = p.pos
		node.rotation.y = floorf(p.t * 12.0) / 12.0 * 4.0


func _update_timers(delta: float) -> void:
	for t in timers.duplicate():
		t.t -= delta
		if t.t <= 0.0:
			timers.erase(t)
			var f: Callable = t.f
			if f.is_valid():
				f.call()


func _update_downed(delta: float) -> void:
	if heroes.is_empty():
		return
	var living := living_heroes()
	if living.is_empty():
		all_down_t += delta
		if all_down_t > 1.6:
			all_down_t = 0.0
			for i in heroes.size():
				var h := heroes[i]
				h.revive(true)
				h.global_position = checkpoint + Vector3(1.5 * i, 0.1, 0)
				h.velocity = Vector3.ZERO
			cam_focus = checkpoint
			hud.toast("Tente de novo!")
			_log("todos caídos: voltando ao ponto de controle")
		return
	all_down_t = 0.0
	for h in heroes:
		if not h.down:
			continue
		var near := false
		for o in living:
			if o.global_position.distance_to(h.global_position) < 2.4:
				near = true
		h.revive_progress = clampf(h.revive_progress + (delta / 2.0 if near else -delta), 0.0, 1.0)
		if h.revive_progress >= 1.0:
			h.revive()
			fx.ring(h.global_position, 2.0, Color(0.4, 1, 0.5))
			fx.popup(h.global_position + Vector3(0, 2.6, 0), "De pé!", Color(0.5, 1, 0.6), 80)


func _on_downed(h: Hero) -> void:
	m_downs += 1
	_log("%s caiu" % h.display_name)


func _on_machine_died(m: Machine) -> void:
	machines.erase(m)
	m_kills += 1
	if m == boss:
		_log("chefe derrotado")


# ---------------------------------------------------------------- missões

func _hero_near(p: Vector3, r: float) -> bool:
	for h in living_heroes():
		var d := h.global_position - p
		d.y = 0
		if d.length() < r:
			return true
	return false


func _once(key: String) -> bool:
	if events.has(key):
		return false
	events[key] = true
	return true


func _update_mission(_delta: float) -> void:
	# Inimigos dormentes acordam quando alguém chega perto
	for d in dormant.duplicate():
		if _hero_near(d.pos, 15.0):
			dormant.erase(d)
			spawn_machine(d.type, d.pos)
	# Baús
	for ch in level.chests:
		if not ch.opened and _hero_near(ch.pos, 1.9):
			level.open_chest(ch)
	# Placas
	var signs := level.cells("i").duplicate()
	signs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(level.start_pos) < b.distance_to(level.start_pos))
	for i in signs.size():
		if _hero_near(signs[i], 2.6) and _once("sign%d" % i):
			_talk(Levels.TALK.get("%s_sign%d" % [mission_id, i + 1], []), Callable())
			return
	if mission_id == "m1":
		_mission1()
	else:
		_mission2()


func _mission1() -> void:
	match phase:
		"levers":
			for lv in level.levers:
				if _hero_near(lv.pos, 11.0) and _once("lev_talk"):
					hud.objective = "Acerte as duas alavancas (0/2)"
					_talk(Levels.TALK.m1_levers, Callable())
					return
			for w in level.breakables:
				if w.alive and _hero_near(w.pos, 6.0) and _once("secret_bark"):
					var l: Array = Levels.TALK.m1_secret[0]
					dialogue_bark(l[0], l[1])
		"artifact":
			if level.artifact and _hero_near(level.artifact.global_position, 2.4):
				phase = "ambush"
				_talk(Levels.TALK.m1_artifact, _start_ambush)
		"ambush":
			if pending_spawns == 0 and machines.is_empty():
				phase = "exit"
				level.set_exit_active(true)
				hud.objective = "Volte para a saída ao sul"
				checkpoint = level.cells("G")[0] + Vector3(1, 0, -3)
				var l: Array = Levels.TALK.m1_exit[0]
				dialogue_bark(l[0], l[1])
				hud.toast("Emboscada vencida!")
			else:
				hud.objective = "Derrote as unidades de coleta! (%d)" % (machines.size() + pending_spawns)
		"exit":
			var xp: Vector3 = level.cells("X")[0]
			if _hero_near(xp, 1.6):
				phase = "done"
				_talk(Levels.TALK.m1_end, func() -> void: _finish_mission())


func _start_ambush() -> void:
	level.artifact.queue_free()
	level.artifact = null
	sfx.play("jingle", 0.0)
	var pts: Array = level.cells("a")
	pending_spawns = pts.size() + 2
	for i in pts.size():
		var p: Vector3 = pts[i]
		schedule(0.4 + i * 0.5, func() -> void:
			pending_spawns -= 1
			spawn_machine("rastejante", p))
	for i in 2:
		var p: Vector3 = pts[i * 2]
		schedule(2.5 + i * 0.8, func() -> void:
			pending_spawns -= 1
			spawn_machine("zumbidor", p + Vector3(2, 0, 0)))
	checkpoint = level.cells("A")[0] + Vector3(0, 0, 3)
	hud.objective = "Derrote as unidades de coleta!"
	shake(0.3)


func _on_lever(n: int, total: int) -> void:
	sfx.play("crit", 0.0)
	_once("lev_talk")
	hud.objective = "Acerte as duas alavancas (%d/%d)" % [n, total]
	_log("alavanca %d/%d" % [n, total])
	if n >= total:
		level.open_gate()
		shake(0.4)
		sfx.play("boom")
		phase = "artifact"
		checkpoint = level.cells("G")[0] + Vector3(1, 0, 3)
		hud.objective = "Descubra o que está piscando nas ruínas"
		hud.toast("O portão abriu!")
		schedule(1.2, func() -> void: _talk(Levels.TALK.m1_gate, Callable()))
	else:
		hud.toast("Falta uma alavanca!")


func _on_wall_broken() -> void:
	sfx.play("shatter")
	shake(0.3)
	hud.toast("Passagem secreta!")
	_log("parede secreta quebrada")


func _on_chest(pos: Vector3) -> void:
	m_secret = true
	sfx.play("jingle", 0.0)
	drop_loot(pos, 30, 5)
	hud.toast("Baú secreto: Engrenagem Dourada!")
	if not (save.collect as Array).has(mission_id + "_bau"):
		(save.collect as Array).append(mission_id + "_bau")
	_log("baú aberto")


const WAVES := [
	["rastejante", "rastejante", "rastejante"],
	["zumbidor", "zumbidor", "rastejante", "rastejante"],
	["chifrudo", "rastejante", "rastejante"],
]


func _mission2() -> void:
	match phase:
		"waves":
			if wave > 0 and pending_spawns == 0 and machines.is_empty() and _once("wave_end_%d" % wave):
				if wave < WAVES.size():
					hud.toast("Onda %d vencida!" % wave)
					schedule(2.5, _next_wave)
				else:
					phase = "boss_intro"
					hud.toast("A terra está tremendo...")
					shake(0.6)
					schedule(2.0, func() -> void: _talk(Levels.TALK.m2_boss, _spawn_boss))
			elif wave > 0 and not events.has("wave_end_%d" % wave):
				hud.objective = "Onda %d/%d — máquinas restantes: %d" % [wave, WAVES.size(), machines.size() + pending_spawns]
		"boss":
			if boss == null or not is_instance_valid(boss) or boss.dead:
				phase = "done"
				boss = null
				hud.toast("O Colosso desmontou!", 3.0)
				shake(0.8)
				schedule(2.5, func() -> void: _talk(Levels.TALK.m2_end, func() -> void: _finish_mission()))


func _next_wave() -> void:
	wave += 1
	var list: Array = WAVES[wave - 1]
	var spots: Array = []
	for dch in ["1", "2", "3", "4"]:
		spots.append_array(level.cells(dch))
	pending_spawns += list.size()
	hud.toast("Onda %d!" % wave)
	_log("onda %d" % wave)
	for i in list.size():
		var p: Vector3 = spots[i % spots.size()]
		var type: String = list[i]
		schedule(i * 0.7, func() -> void:
			pending_spawns -= 1
			spawn_machine(type, p))


func _spawn_boss() -> void:
	phase = "boss"
	var k: Vector3 = level.cells("K")[0]
	boss = spawn_machine("colosso", k)
	shake(0.8)
	sfx.play("boom")
	hud.objective = "Derrote o Colosso de Sucata! Mísseis e canhões primeiro."
	checkpoint = level.start_pos


func _finish_mission() -> void:
	var first := not _done(mission_id)
	if first:
		(save.done as Array).append(mission_id)
	var bonus := 40 if first else 10
	save.coins = int(save.coins) + m_coins + bonus
	save.blocks = int(save.blocks) + m_blocks
	_write_save()
	var mins := int(m_time) / 60
	var secs := int(m_time) % 60
	var title := "Missão concluída!"
	var sub: String = Levels.MISSIONS[0].title if mission_id == "m1" else Levels.MISSIONS[1].title
	if mission_id == "m2":
		title = "Capítulo 1 concluído!"
		sub = "Próximo: As Ruínas Perdidas (em breve)"
	var rows := [["Moedas coletadas", m_coins], ["Bônus da missão", bonus], ["Blocos coletados", m_blocks],
		["Máquinas desmontadas", m_kills], ["Tempo", "%d:%02d" % [mins, secs]], ["Quedas", m_downs]]
	if mission_id == "m1":
		rows.append(["Segredo (baú escondido)", "Encontrado!" if m_secret else "Não encontrado"])
	_log("missão %s concluída em %s, %d máquinas, %d moedas, quedas %d" % [mission_id, "%d:%02d" % [mins, secs], m_kills, m_coins, m_downs])
	m_coins = 0
	m_blocks = 0
	for h in heroes:
		h.active = false
	hud.objective = ""
	hud.results = {"title": title, "subtitle": sub, "rows": rows}
	sfx.play("jingle", 0.0)
	if shots_dir != "":
		_shot()
	if test_mode == "bot" and mission_id == "m2":
		_log("TESTE OK: capítulo 1 completo em %.0f s de jogo" % _test_t)
		schedule(0.0, Callable())
		await get_tree().create_timer(0.5, true, false, true).timeout
		get_tree().quit()


# ---------------------------------------------------------------- vila

func _update_village() -> void:
	_interact = ""
	hud.prompt = ""
	if heroes.is_empty():
		return
	var p := heroes[0].global_position
	var near := func(q: Vector3, r: float) -> bool:
		return Vector2(q.x - p.x, q.z - p.z).length() < r
	for m in level.cells("M"):
		if near.call(m, 3.2):
			_interact = "board"
			hud.prompt = "A / E: Quadro de missões"
	for o in level.cells("O"):
		if near.call(o, 3.2):
			_interact = "shop"
			hud.prompt = "A / E: Oficina (melhorias)"
	for n in npcs:
		if near.call(n.pos, 2.6):
			_interact = "npc"
			hud.prompt = "A / E: Conversar com " + n.name
	if level.cells("X").size() > 0 and near.call(level.cells("X")[0], 1.6):
		_interact = "board"
		hud.prompt = "A / E: Sair em missão"
	if test_mode == "bot" and _interact == "board":
		_do_interact()
	elif _interact != "" and Input.is_physical_key_pressed(KEY_E) and not bool(_prev[0].get("confirm", false)):
		_do_interact()


func _do_interact() -> void:
	match _interact:
		"board":
			_mission_menu()
		"shop":
			_shop_menu()
		"npc":
			var l: Array = Levels.NPC_LINES[npc_line % Levels.NPC_LINES.size()]
			npc_line += 1
			_talk([l], Callable())


func _mission_menu() -> void:
	var items := []
	for i in Levels.MISSIONS.size():
		var m: Dictionary = Levels.MISSIONS[i]
		var unlocked := i == 0 or _done(Levels.MISSIONS[i - 1].id)
		var done := _done(m.id)
		items.append({"label": "%d. %s" % [i + 1, m.title], "desc": m.desc if unlocked else "Complete a missão anterior para liberar",
			"right": "Concluída" if done else ("Nova!" if unlocked else "Bloqueada"), "enabled": unlocked, "id": m.id,
			"bot": unlocked and not done})
	items.append({"label": "Voltar", "id": "back"})
	_menu("Quadro de Missões", items, func(it: Dictionary) -> void:
		if it.id != "back":
			if test_mode == "bot" and it.id == "back":
				return
			start_mission(it.id)
		, func() -> void: pass)


const UPGRADES := [
	{"key": "up_hearts", "label": "Coração extra", "desc": "+1 coração para os dois heróis", "coins": 60, "blocks": 10},
	{"key": "up_damage", "label": "Pontas afiadas", "desc": "+20% de dano em todos os ataques", "coins": 80, "blocks": 15},
	{"key": "up_cooldown", "label": "Engrenagens rápidas", "desc": "Especial e habilidade recarregam 12% mais rápido", "coins": 70, "blocks": 12},
]


func _shop_menu() -> void:
	var items := []
	for u in UPGRADES:
		var lvl := int(save.get(u.key, 0))
		var c: int = u.coins * (lvl + 1)
		var b: int = u.blocks * (lvl + 1)
		var maxed := lvl >= 3
		var afford := coins_total() >= c and blocks_total() >= b
		items.append({"label": "%s  (nível %d/3)" % [u.label, lvl], "desc": u.desc,
			"right": "Máximo" if maxed else "%d moedas · %d blocos" % [c, b], "enabled": not maxed and afford, "key": u.key,
			"coins": c, "blocks": b, "keep_open": true})
	items.append({"label": "Sair da oficina", "id": "back"})
	_menu("Oficina  —  %d moedas · %d blocos" % [coins_total(), blocks_total()], items, func(it: Dictionary) -> void:
		if it.has("key"):
			save.coins = int(save.coins) - int(it.coins)
			save.blocks = int(save.blocks) - int(it.blocks)
			save[it.key] = int(save.get(it.key, 0)) + 1
			_write_save()
			sfx.play("jingle", 0.0)
			for h in heroes:
				var frac := float(h.hearts) / h.max_hearts
				h.apply_upgrades(save)
				h.hearts = maxi(1, int(ceil(frac * h.max_hearts)))
			hud.menu_active = false
			_set_paused(false)
			_shop_menu()
			hud.toast("Melhoria comprada!")
		else:
			_close_menu()
		, func() -> void: pass)


# ---------------------------------------------------------------- teste automático

## Cena fixa para captura de tela: TDB_TEST=view:<cena>  (saída em /tmp/tdbview)
func _view(scene: String) -> void:
	save = _default_save()
	match scene:
		"title":
			go_title()
		"vila":
			start_village()
		"m1":
			start_mission("m1")
			hud.dlg_active = false
			_set_paused(false)
			var h := heroes[0]
			h.global_position = level.cell_pos(18, 13)
			spawn_machine("rastejante", level.cell_pos(21, 11))
			spawn_machine("chifrudo", level.cell_pos(14, 11))
			spawn_machine("zumbidor", level.cell_pos(20, 15))
		"boss":
			start_mission("m2")
			hud.dlg_active = false
			_set_paused(false)
			phase = "boss"
			wave = 3
			events["wave_end_3"] = true
			_p2_joined = true
			_make_hero("bento", 1, level.cell_pos(18, 12))
			heroes[0].global_position = level.cell_pos(15, 12)
			boss = spawn_machine("colosso", level.cell_pos(17, 6))
			hud.objective = "Derrote o Colosso de Sucata! Mísseis e canhões primeiro."
		"dialogo":
			start_mission("m1")
		"oficina":
			start_village()
			save.coins = 200
			save.blocks = 40
			_shop_menu()
	cam_focus = heroes[0].global_position if not heroes.is_empty() else Vector3.ZERO
	for i in 90:
		await get_tree().process_frame
		if scene in ["m1", "boss"] and i == 60:
			heroes[0].in_attack = true
			if scene == "boss":
				fx.telegraph(heroes[0].global_position, 2.4, 3.0)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/tdbview")
	get_viewport().get_texture().get_image().save_png("/tmp/tdbview/%s.png" % scene)
	get_tree().quit()


func _log(s: String) -> void:
	if test_mode != "":
		print("[TDB %.1f] %s" % [_test_t, s])


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%02d_%s.png" % [shots_dir, _shot_n, state + ("_" + mission_id if mission_id != "" else "")])
		_shot_n += 1


func _bot(delta: float) -> void:
	if _test_t > 1500.0:
		print("[TDB] TESTE FALHOU: tempo esgotado na fase ", mission_id, " / ", phase)
		get_tree().quit(1)
		return
	if state == "title" or heroes.is_empty() or paused:
		return
	var h := heroes[0]
	if int(_test_t / 20.0) != int((_test_t - delta) / 20.0):
		var ms := []
		for m in machines:
			if is_instance_valid(m):
				ms.append("%s@%s hp%d st=%s" % [m.type, level.pos_cell(m.global_position), int(m.hp), m.state])
		_log("status fase=%s herói@%s hp%d máquinas=%s dormentes=%d" % [phase, level.pos_cell(h.global_position), h.hearts, ms, dormant.size()])
	var d := {"move": Vector2.ZERO, "attack": false, "special": false, "alt": false, "dodge": false, "switch": false,
		"start": false, "confirm": false, "cancel": false, "up": false, "down": false}
	var goal := Vector3.INF
	var enemy: Machine = null
	var ed := 1e9
	for m in machines:
		if is_instance_valid(m) and not m.dead:
			var dist := m.global_position.distance_to(h.global_position)
			if dist < ed:
				ed = dist
				enemy = m
	if state == "village":
		goal = level.cells("M")[0] + Vector3(0, 0, 2.0)
	elif enemy and ed < 18.0:
		goal = Vector3.INF
	elif mission_id == "m1":
		match phase:
			"levers":
				for lv in level.levers:
					if not lv.on:
						if _hero_near(lv.pos, 6.0):
							var to: Vector3 = lv.pos - h.global_position
							var w := to.normalized().rotated(Vector3.UP, deg_to_rad(45.0))
							d.move = Vector2(w.x, w.z) * 0.2
							d.attack = true
						else:
							goal = lv.pos
						break
				if goal == Vector3.INF and not d.attack:
					goal = level.cells("G")[0]
			"artifact":
				goal = level.cells("A")[0]
			"exit", "done":
				goal = level.cells("X")[0]
	elif enemy:
		goal = enemy.global_position
	else:
		goal = level.center() + Vector3(0, 0, 4)
	if enemy and ed < 18.0:
		var to := enemy.global_position - h.global_position
		to.y = 0
		var want := Vector3.ZERO
		var keep := 7.0 if h.kind == "iara" else 2.0
		if enemy.type == "colosso":
			keep = 10.0 if h.kind == "iara" else 5.0
		if to.length() > keep + 2.0:
			want = to.normalized()
		elif to.length() < keep - 1.5:
			want = -to.normalized()
		else:
			want = to.normalized().rotated(Vector3.UP, PI / 2.0) * 0.5 + to.normalized() * 0.05
		if want.length() > 0.01:
			var w := want.rotated(Vector3.UP, deg_to_rad(45.0))
			d.move = Vector2(w.x, w.z)
		d.attack = true
		d.special = h.special_cd <= 0.0
		d.alt = h.alt_cd <= 0.0 and randf() < 0.05
		if ed < 3.0 and randf() < 0.04:
			d.dodge = true
		# Se a máquina está longe do alcance direto, usa o caminho
		if to.length() > 9.0:
			goal = enemy.global_position
	if goal != Vector3.INF:
		var dir := _bot_steer(h, goal, delta)
		if dir.length() > 0.01:
			var w := dir.rotated(Vector3.UP, deg_to_rad(45.0))
			d.move = Vector2(w.x, w.z)
	# Preso? rola para o lado
	if h.global_position.distance_to(_bot_last_pos) < 0.02 and d.move.length() > 0.5:
		_bot_stuck += delta
	else:
		_bot_stuck = 0.0
	_bot_last_pos = h.global_position
	if _bot_stuck > 1.0:
		_bot_stuck = 0.0
		_bot_path_t = 0.0
		d.move = d.move.rotated(PI / 2.0 * (1 if randf() < 0.5 else -1))
		d.dodge = true
	# Simula "apertar" (borda): só verdadeiro num quadro
	for k in ["special", "alt", "dodge"]:
		if bool(_prev[0].get(k, false)):
			d[k] = false
	_inp[0] = d


func _bot_steer(h: Hero, goal: Vector3, delta: float) -> Vector3:
	_bot_path_t -= delta
	var start := level.pos_cell(h.global_position)
	var target := level.pos_cell(goal)
	if _bot_path_t <= 0.0 or _bot_path.is_empty():
		_bot_path_t = 0.6
		_bot_path = _bfs(start, target)
	while _bot_path.size() > 1 and _bot_path[0] == start:
		_bot_path.remove_at(0)
	if _bot_path.is_empty():
		var t := goal - h.global_position
		t.y = 0
		return t.normalized() if t.length() > 0.8 else Vector3.ZERO
	var next := level.cell_pos(_bot_path[0].x, _bot_path[0].y)
	var to := next - h.global_position
	to.y = 0
	if to.length() < 0.5 and _bot_path.size() > 1:
		_bot_path.remove_at(0)
	if _bot_path.size() <= 1:
		var t2 := goal - h.global_position
		t2.y = 0
		return t2.normalized() if t2.length() > 0.8 else Vector3.ZERO
	return to.normalized()


func _bfs(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var prev := {a: a}
	var q: Array[Vector2i] = [a]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var found := false
	# Alvo bloqueado (alavanca, quadro...): chega numa casa vizinha livre
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b or (c - b).length_squared() <= 1 and not level.is_free(b):
			b = c
			found = true
			break
		for dd in dirs:
			var n: Vector2i = c + dd
			if not prev.has(n) and level.is_free(n):
				prev[n] = c
				q.append(n)
	if not found:
		return out
	var cur := b
	while cur != a:
		out.push_front(cur)
		cur = prev[cur]
	return out
