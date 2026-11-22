extends Node
## Ponte entre o launcher e o Linux do console.
## Os comandos de sistema ficam em scripts shell em /opt/console/bin
## (ou em CONSOLE_BIN_DIR, para testes),
## assim o launcher não precisa saber detalhes de nmcli, bluetoothctl etc.

signal stick_moved(direction: Vector2i)

const DEFAULT_BIN_DIR := "/opt/console/bin"
const STICK_DEADZONE := 0.6
const STICK_FIRST_DELAY := 0.38
const STICK_REPEAT := 0.13

var is_console := false
var bin_dir := DEFAULT_BIN_DIR
var input_blocked := false

var _tasks: Array[int] = []
var _stick_dir := Vector2i.ZERO
var _stick_timer := 0.0


func _ready() -> void:
	if OS.get_environment("CONSOLE_BIN_DIR") != "":
		bin_dir = OS.get_environment("CONSOLE_BIN_DIR")
	is_console = OS.get_name() == "Linux" and DirAccess.dir_exists_absolute(bin_dir)
	_setup_input()


# ---------------------------------------------------------------- pastas

## Pastas onde o launcher procura jogos (cada jogo é uma subpasta com game.json).
func games_dirs() -> PackedStringArray:
	var env := OS.get_environment("CONSOLE_GAMES_DIRS")
	if env != "":
		return env.split(":", false)
	var dirs := PackedStringArray(["/opt/console/games"])
	var home := OS.get_environment("HOME")
	if home != "":
		dirs.append(home.path_join("games"))
	# Modo desenvolvimento: pasta "games" ao lado do executável.
	dirs.append(OS.get_executable_path().get_base_dir().path_join("games"))
	return dirs


func config_dir() -> String:
	var home := OS.get_environment("HOME")
	return home.path_join(".config/console") if home != "" else OS.get_user_data_dir()


# ---------------------------------------------------------------- comandos

## Executa um comando e devolve {code, out}. Bloqueia; use run_async na interface.
func run(cmd: String, args: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := []
	var code := OS.execute(cmd, args, out, true)
	var text := ""
	for chunk in out:
		text += str(chunk)
	return {"code": code, "out": text.strip_edges()}


## Executa em segundo plano e chama callback(resultado) na thread principal.
func run_async(cmd: String, args: PackedStringArray, callback: Callable) -> void:
	var id := WorkerThreadPool.add_task(func() -> void:
		var r := run(cmd, args)
		callback.call_deferred(r))
	_tasks.append(id)


## Chama uma ferramenta de /opt/console/bin em segundo plano.
func call_tool(name: String, args: PackedStringArray, callback: Callable) -> void:
	if not is_console:
		callback.call_deferred({"code": -1, "out": "Disponível só no console (Linux)."})
		return
	run_async(bin_dir.path_join(name), args, callback)


## Lê saída em TSV (uma linha por item, campos separados por TAB).
func parse_tsv(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line in text.split("\n", false):
		rows.append(line.split("\t"))
	return rows


# ---------------------------------------------------------------- entrada

func _process(delta: float) -> void:
	# Libera as tarefas concluídas para não vazarem threads.
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	_update_stick(delta)


## O analógico esquerdo navega nos menus com repetição controlada
## (o mapeamento direto de eixo pula vários itens de uma vez).
func _update_stick(delta: float) -> void:
	if input_blocked:
		_stick_dir = Vector2i.ZERO
		return
	var v := Vector2.ZERO
	for d in Input.get_connected_joypads():
		var a := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if a.length() > v.length():
			v = a
	var dir := Vector2i.ZERO
	if v.length() > STICK_DEADZONE:
		if absf(v.x) > absf(v.y):
			dir.x = int(signf(v.x))
		else:
			dir.y = int(signf(v.y))
	if dir != _stick_dir:
		_stick_dir = dir
		_stick_timer = STICK_FIRST_DELAY
		if dir != Vector2i.ZERO:
			_emit_dir(dir)
	elif dir != Vector2i.ZERO:
		_stick_timer -= delta
		if _stick_timer <= 0.0:
			_stick_timer = STICK_REPEAT
			_emit_dir(dir)


func _emit_dir(dir: Vector2i) -> void:
	var action := "ui_right"
	if dir.x < 0:
		action = "ui_left"
	elif dir.y < 0:
		action = "ui_up"
	elif dir.y > 0:
		action = "ui_down"
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
	stick_moved.emit(dir)


func _setup_input() -> void:
	_add_joy_button("ui_accept", JOY_BUTTON_A)
	_add_joy_button("ui_cancel", JOY_BUTTON_B)
	_add_joy_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("console_menu", JOY_BUTTON_START)
	_add_key("console_menu", KEY_F1)
	_add_joy_button("console_home", JOY_BUTTON_GUIDE)
	_add_key("console_home", KEY_F12)
	_add_joy_button("console_delete", JOY_BUTTON_X)
	_add_joy_button("console_space", JOY_BUTTON_Y)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)


func _add_joy_button(action: String, button: JoyButton) -> void:
	_ensure_action(action)
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	if not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)


func _add_key(action: String, key: Key) -> void:
	_ensure_action(action)
	var e := InputEventKey.new()
	e.physical_keycode = key
	if not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)
