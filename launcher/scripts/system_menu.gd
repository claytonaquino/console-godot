extends Control
## Menu de sistema (Start): volume, Wi-Fi, Bluetooth, vídeo, informações e energia.

signal closed
signal launch_requested(path: String, args: PackedStringArray, title: String)
signal reload_games_requested
signal toast(text: String)

const OskScript := preload("res://scripts/osk.gd")

var _panel: PanelContainer
var _content: VBoxContainer
var _osk: VBoxContainer
var _page := ""
var _token := 0
var _volume_timer: Timer
var _pending_volume := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(1100, 0)
	center.add_child(_panel)
	var stack := VBoxContainer.new()
	_panel.add_child(stack)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	stack.add_child(_content)
	_osk = OskScript.new()
	_osk.hide()
	stack.add_child(_osk)

	_volume_timer = Timer.new()
	_volume_timer.one_shot = true
	_volume_timer.wait_time = 0.15
	_volume_timer.timeout.connect(_apply_volume)
	add_child(_volume_timer)
	hide()


func open() -> void:
	show()
	_page_main()


func close() -> void:
	hide()
	_osk.hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _osk.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _page == "main":
			close()
		else:
			_page_main()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("console_menu"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- utilidades

func _clear(page: String, title: String) -> int:
	_page = page
	_token += 1
	_osk.hide()
	_content.show()
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_content.add_child(UiTheme.label(title, 46))
	return _token


func _button(text: String, cb: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	(parent if parent else _content).add_child(b)
	return b


func _status(text: String) -> Label:
	var l := UiTheme.label(text, 26, UiTheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1000, 0)
	_content.add_child(l)
	return l


func _scroll_list() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1000, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	_content.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	return list


func _focus_first() -> void:
	var b := _find_focusable(_content)
	if b:
		b.grab_focus()


func _find_focusable(node: Node) -> Control:
	for c in node.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).visible:
			return c
		var inner := _find_focusable(c)
		if inner:
			return inner
	return null


func _first_line(text: String) -> String:
	var lines := text.strip_edges().split("\n", false)
	return lines[lines.size() - 1] if lines.size() > 0 else ""


# ---------------------------------------------------------------- página inicial

func _page_main() -> void:
	var tk := _clear("main", "Sistema")

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 24)
	vol_row.add_child(UiTheme.label("Volume", 30))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.custom_minimum_size = Vector2(640, 48)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_row.add_child(slider)
	var vol_label := UiTheme.label("--", 30)
	vol_row.add_child(vol_label)
	_content.add_child(vol_row)
	slider.value_changed.connect(func(v: float) -> void:
		vol_label.text = "%d%%" % int(v)
		_pending_volume = int(v)
		_volume_timer.start())
	Sys.call_tool("console-volume", PackedStringArray(["get"]), func(r: Dictionary) -> void:
		if tk != _token:
			return
		if r.code == 0 and str(r.out).is_valid_int():
			slider.set_value_no_signal(int(r.out))
			vol_label.text = "%s%%" % r.out
		else:
			vol_label.text = "n/d")

	var wifi_btn := _button("Wi-Fi", _page_wifi)
	_button("Controles Bluetooth", _page_bt)
	var gpu_btn := Button.new()
	gpu_btn.text = _gpu_label()
	gpu_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content.add_child(gpu_btn)
	gpu_btn.pressed.connect(func() -> void:
		_set_gpu_pref("nouveau" if _gpu_pref() == "auto" else "auto")
		gpu_btn.text = _gpu_label()
		toast.emit("Driver de vídeo muda na próxima inicialização."))
	_button("Informações do sistema", _page_info)
	_button("Recarregar biblioteca de jogos", func() -> void:
		reload_games_requested.emit()
		close())
	_button("Terminal (avançado)", func() -> void:
		close()
		launch_requested.emit("/usr/bin/xterm", PackedStringArray(["-fa", "Monospace", "-fs", "14", "-maximized"]), "Terminal"))
	_button("Reiniciar", _confirm.bind("Reiniciar o console?", "reboot"))
	_button("Desligar", _confirm.bind("Desligar o console?", "off"))
	_button("Fechar menu", close)
	wifi_btn.grab_focus.call_deferred()


func _apply_volume() -> void:
	if _pending_volume >= 0:
		Sys.call_tool("console-volume", PackedStringArray(["set", str(_pending_volume)]), func(_r: Dictionary) -> void: pass)


func _confirm(question: String, action: String) -> void:
	_clear("confirm", question)
	_button("Sim", func() -> void:
		_status("Até logo!")
		Sys.call_tool("console-power", PackedStringArray([action]), func(r: Dictionary) -> void:
			if r.code != 0:
				toast.emit("Não foi possível: " + _first_line(r.out))))
	_button("Não", _page_main)
	_focus_first.call_deferred()


# ---------------------------------------------------------------- vídeo

func _gpu_pref_path() -> String:
	return Sys.config_dir().path_join("gpu")


func _gpu_pref() -> String:
	if FileAccess.file_exists(_gpu_pref_path()):
		var v := FileAccess.get_file_as_string(_gpu_pref_path()).strip_edges()
		if v != "":
			return v
	return "auto"


func _set_gpu_pref(value: String) -> void:
	DirAccess.make_dir_recursive_absolute(Sys.config_dir())
	var f := FileAccess.open(_gpu_pref_path(), FileAccess.WRITE)
	if f:
		f.store_line(value)


func _gpu_label() -> String:
	return "Placa NVIDIA antiga: " + ("driver aberto (nouveau)" if _gpu_pref() == "nouveau" else "automático (driver 470)")


# ---------------------------------------------------------------- Wi-Fi

func _page_wifi() -> void:
	var tk := _clear("wifi", "Wi-Fi")
	var status := _status("Procurando redes...")
	var list := _scroll_list()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_content.add_child(row)
	_button("Procurar de novo", _page_wifi, row)
	_button("Voltar", _page_main, row)
	_focus_first.call_deferred()

	Sys.call_tool("console-wifi", PackedStringArray(["list"]), func(r: Dictionary) -> void:
		if tk != _token:
			return
		if r.code != 0:
			status.text = "Wi-Fi indisponível: " + _first_line(r.out)
			return
		var rows := Sys.parse_tsv(r.out)
		status.text = "%d redes encontradas. Escolha uma para conectar." % rows.size() if rows.size() else "Nenhuma rede encontrada."
		for f in rows:
			if f.size() < 5 or f[4] == "":
				continue
			var inuse := f[0] == "*"
			var secured := f[2] != "" and f[2] != "--"
			var known := f[3] == "1"
			var txt := "%s   %s%%%s%s" % [f[4], f[1], "   protegida" if secured else "   aberta", "   [conectado]" if inuse else ""]
			var ssid := f[4]
			_button(txt, func() -> void: _wifi_pick(ssid, secured and not known), list)
		_focus_first.call_deferred())


func _wifi_pick(ssid: String, needs_password: bool) -> void:
	if not needs_password:
		_wifi_connect(ssid, "")
		return
	_content.hide()
	_osk.open("Senha da rede \"%s\"" % ssid, true)
	_disconnect_osk()
	_osk.submitted.connect(func(pw: String) -> void:
		_disconnect_osk()
		_wifi_connect(ssid, pw))
	_osk.cancelled.connect(func() -> void:
		_disconnect_osk()
		_page_wifi())


func _disconnect_osk() -> void:
	for c in _osk.submitted.get_connections():
		_osk.submitted.disconnect(c.callable)
	for c in _osk.cancelled.get_connections():
		_osk.cancelled.disconnect(c.callable)


func _wifi_connect(ssid: String, password: String) -> void:
	var tk := _clear("wifi_connect", "Wi-Fi")
	var status := _status("Conectando a \"%s\"..." % ssid)
	var args := PackedStringArray(["connect", ssid])
	if password != "":
		args.append(password)
	Sys.call_tool("console-wifi", args, func(r: Dictionary) -> void:
		if tk != _token:
			return
		if r.code == 0:
			status.text = "Conectado a \"%s\"." % ssid
			toast.emit("Wi-Fi conectado: " + ssid)
		else:
			status.text = "Não conectou: " + _first_line(r.out)
		_button("Voltar", _page_wifi)
		_focus_first.call_deferred())


# ---------------------------------------------------------------- Bluetooth

func _page_bt() -> void:
	var tk := _clear("bt", "Controles Bluetooth")
	_status("Para parear: PlayStation — segure Share + PS até a luz piscar. Xbox — segure o botão de parear no topo. Depois escolha \"Procurar\".")
	var status := _status("Carregando dispositivos...")
	var list := _scroll_list()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_content.add_child(row)
	_button("Procurar (10 s)", _bt_scan, row)
	_button("Voltar", _page_main, row)
	_focus_first.call_deferred()
	Sys.call_tool("console-bt", PackedStringArray(["list"]), _bt_fill.bind(tk, status, list))


func _bt_scan() -> void:
	var tk := _clear("bt", "Controles Bluetooth")
	var status := _status("Procurando por 10 segundos... deixe o controle piscando.")
	var list := _scroll_list()
	_button("Voltar", _page_main)
	_focus_first.call_deferred()
	Sys.call_tool("console-bt", PackedStringArray(["scan", "10"]), _bt_fill.bind(tk, status, list))


func _bt_fill(r: Dictionary, tk: int, status: Label, list: VBoxContainer) -> void:
	if tk != _token:
		return
	if r.code != 0:
		status.text = "Bluetooth indisponível: " + _first_line(r.out)
		return
	var rows := Sys.parse_tsv(r.out)
	status.text = "Escolha um dispositivo." if rows.size() else "Nenhum dispositivo encontrado."
	for f in rows:
		if f.size() < 4:
			continue
		var mac := f[0]
		var dev_name := f[1]
		var paired := f[2] == "1"
		var connected := f[3] == "1"
		var state := "conectado" if connected else ("pareado" if paired else "novo")
		_button("%s   [%s]" % [dev_name, state], _bt_device.bind(mac, dev_name, paired), list)
	_focus_first.call_deferred()


func _bt_device(mac: String, dev_name: String, paired: bool) -> void:
	if not paired:
		_bt_action("pair", mac, dev_name, "Pareando com %s..." % dev_name)
		return
	_clear("bt_device", dev_name)
	_button("Conectar", _bt_action.bind("connect", mac, dev_name, "Conectando %s..." % dev_name))
	_button("Esquecer este dispositivo", _bt_action.bind("remove", mac, dev_name, "Removendo %s..." % dev_name))
	_button("Voltar", _page_bt)
	_focus_first.call_deferred()


func _bt_action(action: String, mac: String, dev_name: String, message: String) -> void:
	var tk := _clear("bt_action", "Controles Bluetooth")
	var status := _status(message)
	Sys.call_tool("console-bt", PackedStringArray([action, mac]), func(r: Dictionary) -> void:
		if tk != _token:
			return
		status.text = ("Pronto: " + dev_name) if r.code == 0 else ("Falhou: " + _first_line(r.out))
		_button("Voltar", _page_bt)
		_focus_first.call_deferred())


# ---------------------------------------------------------------- informações

func _page_info() -> void:
	var tk := _clear("info", "Informações do sistema")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	var add_row := func(k: String, v: String) -> void:
		grid.add_child(UiTheme.label(k, 26, UiTheme.TEXT_DIM))
		var lv := UiTheme.label(v, 26)
		lv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.custom_minimum_size = Vector2(700, 0)
		grid.add_child(lv)
	add_row.call("Placa de vídeo", RenderingServer.get_video_adapter_name())
	add_row.call("Fabricante", RenderingServer.get_video_adapter_vendor())
	add_row.call("API gráfica", RenderingServer.get_video_adapter_api_version())
	add_row.call("Launcher", "v" + str(ProjectSettings.get_setting("application/config/version", "?")) + " (Godot " + Engine.get_version_info().string + ")")
	_button("Voltar", _page_main)
	_focus_first.call_deferred()
	Sys.call_tool("console-info", PackedStringArray(), func(r: Dictionary) -> void:
		if tk != _token or r.code != 0:
			return
		for f in Sys.parse_tsv(r.out):
			if f.size() >= 2:
				add_row.call(f[0], f[1]))
