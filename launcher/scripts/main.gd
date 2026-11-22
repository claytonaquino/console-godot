extends Control
## Tela principal do console: biblioteca de jogos, relógio, status e
## controle do jogo em execução.

const GameCard := preload("res://scripts/game_card.gd")
const SystemMenu := preload("res://scripts/system_menu.gd")
const BG_SHADER := preload("res://shaders/background.gdshader")
const SETTINGS_PATH := "user://launcher.cfg"
const HOME_HOLD_SECONDS := 2.0
const WEEKDAYS := ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
const MONTHS := ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

var games: Array[Dictionary] = []
var cards: Array[Button] = []
var current: Dictionary = {}

var running_pid := -1
var running_title := ""
var _check_timer := 0.0
var _home_hold := 0.0

var _bg_mat: ShaderMaterial
var _bg_tween: Tween
var _row: HBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _desc: Label
var _empty: Label
var _clock: Label
var _date: Label
var _status: Label
var _toast: Label
var _toast_tween: Tween
var _overlay: Control
var _overlay_title: Label
var _overlay_hint: Label
var _menu: Control
var _settings := ConfigFile.new()


func _ready() -> void:
	theme = UiTheme.build()
	_settings.load(SETTINGS_PATH)
	_build_ui()
	_load_games()
	Input.joy_connection_changed.connect(_on_joy_changed)
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)
	_tick()
	_refresh_status()
	var st := Timer.new()
	st.wait_time = 15.0
	st.autostart = true
	st.timeout.connect(_refresh_status)
	add_child(st)
	if OS.get_environment("CONSOLE_SELFTEST") != "":
		_selftest.call_deferred(OS.get_environment("CONSOLE_SELFTEST"))


# ---------------------------------------------------------------- interface

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BG_SHADER
	_bg_mat.set_shader_parameter("accent", Color(0.16, 0.45, 0.65))
	bg.material = _bg_mat
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)

	# Barra superior
	var top := HBoxContainer.new()
	col.add_child(top)
	top.add_child(UiTheme.label("CONSOLE", 40))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_status = UiTheme.label("", 26, UiTheme.TEXT_DIM)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_status)
	var clock_box := VBoxContainer.new()
	clock_box.add_theme_constant_override("separation", -6)
	clock_box.custom_minimum_size = Vector2(230, 0)
	_clock = UiTheme.label("--:--", 44)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_date = UiTheme.label("", 22, UiTheme.TEXT_DIM)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_box.add_child(_clock)
	clock_box.add_child(_date)
	top.add_child(clock_box)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 50)
	col.add_child(gap)
	col.add_child(UiTheme.label("Biblioteca", 30, UiTheme.TEXT_DIM))

	# Fileira de jogos
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 560)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = true
	col.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 40)
	pad.add_theme_constant_override("margin_bottom", 40)
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 60)
	_scroll.add_child(pad)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 44)
	pad.add_child(_row)
	_empty = UiTheme.label("", 30, UiTheme.TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(1400, 0)
	_empty.hide()
	pad.add_child(_empty)

	# Informações do jogo selecionado
	_title = UiTheme.label("", 56)
	col.add_child(_title)
	_desc = UiTheme.label("", 27, UiTheme.TEXT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.max_lines_visible = 2
	_desc.custom_minimum_size = Vector2(1300, 0)
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_desc)

	# Dicas dos botões
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 48)
	hints.add_child(UiTheme.hint("A", "Jogar"))
	hints.add_child(UiTheme.hint("Start", "Sistema"))
	hints.add_child(UiTheme.hint("Home", "Segure para fechar o jogo"))
	col.add_child(hints)

	# Tela "jogo em execução" (fica atrás da janela do jogo)
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.02, 0.03, 0.06, 1.0)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ov_box := VBoxContainer.new()
	ov_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ov_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ov_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	ov_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_title = UiTheme.label("", 52)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_hint = UiTheme.label("Segure Home (ou Select + Start) por 2 segundos para fechar.", 28, UiTheme.TEXT_DIM)
	_overlay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_box.add_child(_overlay_title)
	ov_box.add_child(_overlay_hint)
	_overlay.add_child(ov_box)
	_overlay.hide()
	add_child(_overlay)

	_menu = SystemMenu.new()
	add_child(_menu)
	_menu.closed.connect(_on_menu_closed)
	_menu.launch_requested.connect(_launch_path)
	_menu.reload_games_requested.connect(_load_games)
	_menu.toast.connect(show_toast)

	# Aviso flutuante
	_toast = UiTheme.label("", 28)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 150
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tsb := UiTheme.box(Color(0.1, 0.13, 0.2, 0.95), 22, 2, Color(1, 1, 1, 0.15))
	_toast.add_theme_stylebox_override("normal", tsb)
	_toast.modulate.a = 0.0
	add_child(_toast)



func _tick() -> void:
	var t := Time.get_datetime_dict_from_system()
	_clock.text = "%02d:%02d" % [t.hour, t.minute]
	_date.text = "%s, %d %s" % [WEEKDAYS[t.weekday], t.day, MONTHS[t.month - 1]]


func _refresh_status() -> void:
	var pads := Input.get_connected_joypads().size()
	var pads_txt := "Sem controle" if pads == 0 else ("1 controle" if pads == 1 else "%d controles" % pads)
	Sys.call_tool("console-wifi", PackedStringArray(["status"]), func(r: Dictionary) -> void:
		var net := ""
		if r.code == 0:
			var f := str(r.out).split("\t")
			net = ("Rede: " + f[1]) if f.size() > 1 and f[0] == "connected" and f[1] != "" else "Sem rede"
		_status.text = (net + "     " if net != "" else "") + pads_txt + "     ")


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_joy_changed(device: int, connected: bool) -> void:
	var joy_name := Input.get_joy_name(device)
	show_toast(("Controle conectado: " if connected else "Controle desconectado: ") + joy_name)
	_refresh_status()


# ---------------------------------------------------------------- biblioteca

func _load_games() -> void:
	games.clear()
	var seen := {}
	for dir_path in Sys.games_dirs():
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		for sub in da.get_directories():
			var gdir := dir_path.path_join(sub)
			var manifest := gdir.path_join("game.json")
			if not FileAccess.file_exists(manifest):
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(manifest))
			if typeof(data) != TYPE_DICTIONARY or not data.has("exec"):
				push_warning("game.json inválido: " + manifest)
				continue
			var id := str(data.get("id", sub))
			if seen.has(id):
				continue
			seen[id] = true
			data["id"] = id
			data["dir"] = gdir
			games.append(data)
	games.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0)
	_rebuild_cards()


func _rebuild_cards() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	cards.clear()
	_empty.visible = games.is_empty()
	if games.is_empty():
		_empty.text = "Nenhum jogo encontrado.\nCopie jogos (pasta com game.json) para:\n" + "\n".join(Sys.games_dirs())
		_title.text = ""
		_desc.text = "Aperte Start para abrir o menu do sistema."
		return
	for g in games:
		var card := GameCard.new()
		card.setup(g)
		card.selected.connect(_on_card_selected)
		card.pressed.connect(_launch.bind(g))
		_row.add_child(card)
		cards.append(card)
	var last := str(_settings.get_value("launcher", "last_game", ""))
	var target: Button = cards[0]
	for c in cards:
		if c.game.get("id", "") == last:
			target = c
	target.grab_focus.call_deferred()


func _on_card_selected(card: Button) -> void:
	current = card.game
	_title.text = str(current.get("title", ""))
	_desc.text = str(current.get("description", ""))
	if _bg_tween:
		_bg_tween.kill()
	_bg_tween = create_tween()
	var from: Color = _bg_mat.get_shader_parameter("accent")
	_bg_tween.tween_method(func(c: Color) -> void: _bg_mat.set_shader_parameter("accent", c), from, card.accent, 0.5)


# ---------------------------------------------------------------- execução

func _launch(g: Dictionary) -> void:
	var exe := str(g.dir).path_join(str(g.exec))
	if not FileAccess.file_exists(exe):
		show_toast("Executável não encontrado: " + str(g.exec))
		return
	_settings.set_value("launcher", "last_game", g.get("id", ""))
	_settings.save(SETTINGS_PATH)
	var args := PackedStringArray()
	for a in g.get("args", []):
		args.append(str(a))
	_launch_path(exe, args, str(g.get("title", "Jogo")))


func _launch_path(path: String, args: PackedStringArray, title: String) -> void:
	if OS.get_name() != "Windows":
		OS.execute("chmod", PackedStringArray(["+x", path]))
	var pid := OS.create_process(path, args)
	if pid <= 0:
		show_toast("Não foi possível abrir " + title)
		return
	running_pid = pid
	running_title = title
	_overlay_title.text = "Jogando: " + title
	_overlay.show()
	_set_background_mode(true)


func _set_background_mode(on: bool) -> void:
	# Enquanto o jogo roda, o launcher fica quase parado para não roubar GPU/CPU.
	Sys.input_blocked = on
	get_viewport().gui_disable_input = on
	OS.low_processor_usage_mode = on
	Engine.max_fps = 5 if on else 0


func _on_game_exited() -> void:
	running_pid = -1
	_home_hold = 0.0
	_overlay.hide()
	_set_background_mode(false)
	_refresh_status()
	for c in cards:
		if c.game.get("id", "") == current.get("id", ""):
			c.grab_focus.call_deferred()
			return
	if cards.size():
		cards[0].grab_focus.call_deferred()


func _process(delta: float) -> void:
	if running_pid <= 0:
		return
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.5
		if not OS.is_process_running(running_pid):
			_on_game_exited()
			return
	if _home_pressed():
		_home_hold += delta
		if _home_hold >= HOME_HOLD_SECONDS:
			OS.kill(running_pid)
			_home_hold = -10.0  # evita matar duas vezes
	else:
		_home_hold = 0.0


func _home_pressed() -> bool:
	if Input.is_action_pressed("console_home"):
		return true
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_BACK) and Input.is_joy_button_pressed(d, JOY_BUTTON_START):
			return true
	return false


# ---------------------------------------------------------------- menu

func _unhandled_input(event: InputEvent) -> void:
	if running_pid > 0 or _menu.visible:
		return
	if event.is_action_pressed("console_menu"):
		_set_cards_focus(false)
		_menu.open()
		get_viewport().set_input_as_handled()


func _on_menu_closed() -> void:
	_set_cards_focus(true)
	_on_game_exited_focus_only()


## Com o menu aberto, os cartões saem da navegação para o foco não "vazar".
func _set_cards_focus(enabled: bool) -> void:
	for c in cards:
		c.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


func _on_game_exited_focus_only() -> void:
	for c in cards:
		if c.game.get("id", "") == current.get("id", ""):
			c.grab_focus.call_deferred()
			return
	if cards.size():
		cards[0].grab_focus.call_deferred()


# ---------------------------------------------------------------- autoteste
# CONSOLE_SELFTEST=/pasta/para/capturas roda um roteiro automático e fecha.

func _shot(dir: String, name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SELFTEST shot ", name)


func _press(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
	await get_tree().process_frame


func _selftest(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	print("SELFTEST games=", games.size())
	await _shot(dir, "01_inicio")
	await _press("ui_right")
	await _shot(dir, "02_segundo_jogo")
	await _press("console_menu")
	await _shot(dir, "03_menu")
	_menu._page_wifi()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "04_wifi")
	_menu._wifi_pick("Casa Clayton", true)
	await _press("ui_accept")
	await _press("ui_right")
	await _press("ui_accept")
	await _shot(dir, "05_teclado")
	_menu._osk._submit()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "06_wifi_conectado")
	_menu._page_bt()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "07_bluetooth")
	_menu._page_info()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "08_info")
	_menu.close()
	await get_tree().process_frame
	_launch(games[0])
	print("SELFTEST running=", running_pid > 0)
	await _shot(dir, "09_jogando")
	await get_tree().create_timer(3.0).timeout
	print("SELFTEST exited=", running_pid == -1)
	await _shot(dir, "10_voltou")
	get_tree().quit()
