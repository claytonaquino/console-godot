extends Node
## Loja de jogos: lê o catálogo publicado no GitHub, compara com o que está
## instalado e instala/atualiza/remove jogos em ~/games (área de saves).
## O trabalho pesado (download, verificação, extração) fica no script
## /opt/console/bin/console-store.

signal catalog_updated
signal install_finished(id: String, ok: bool, message: String)

const SETTINGS_PATH := "user://store.cfg"

var catalog: Array = []
var last_error := ""
var fetched := false
var busy_id := ""            # jogo sendo baixado agora
var busy_size := 0
var auto_check := true       # procurar novidades ao ligar
var auto_install := false    # instalar novidades sozinho

var _settings := ConfigFile.new()
var _queue: Array = []


func _ready() -> void:
	_settings.load(SETTINGS_PATH)
	auto_check = bool(_settings.get_value("store", "auto_check", true))
	auto_install = bool(_settings.get_value("store", "auto_install", false))


func save_settings() -> void:
	_settings.set_value("store", "auto_check", auto_check)
	_settings.set_value("store", "auto_install", auto_install)
	_settings.save(SETTINGS_PATH)


func user_games_dir() -> String:
	var home := OS.get_environment("HOME")
	return home.path_join("games") if home != "" else OS.get_user_data_dir().path_join("games")


# ---------------------------------------------------------------- versões

static func version_cmp(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## Jogos instalados: id -> {version, dir, removable}
func installed() -> Dictionary:
	var result := {}
	var user_dir := user_games_dir()
	for d in Sys.games_dirs():
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			if sub.begins_with("."):
				continue
			var manifest := d.path_join(sub).path_join("game.json")
			if not FileAccess.file_exists(manifest):
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(manifest))
			if typeof(data) != TYPE_DICTIONARY:
				continue
			var id := str(data.get("id", sub))
			var ver := str(data.get("version", "0.0.0"))
			if result.has(id) and version_cmp(result[id].version, ver) >= 0:
				continue
			result[id] = {"version": ver, "dir": d.path_join(sub), "removable": d == user_dir}
	return result


## "new" (não instalado), "update" (versão nova) ou "installed".
func status_of(entry: Dictionary) -> String:
	var inst := installed()
	var id := str(entry.get("id", ""))
	if not inst.has(id):
		return "new"
	if version_cmp(str(entry.get("version", "0")), inst[id].version) > 0:
		return "update"
	return "installed"


func pending() -> Array:
	var out := []
	for e in catalog:
		if status_of(e) != "installed":
			out.append(e)
	return out


# ---------------------------------------------------------------- ações

func fetch(callback := Callable()) -> void:
	Sys.call_tool("console-store", PackedStringArray(["catalog"]), func(r: Dictionary) -> void:
		var ok := false
		if r.code == 0:
			var data = JSON.parse_string(str(r.out))
			if typeof(data) == TYPE_DICTIONARY and data.has("games"):
				catalog = data.games
				fetched = true
				last_error = ""
				ok = true
			else:
				last_error = "Catálogo inválido."
		else:
			last_error = _last_line(str(r.out), "Sem conexão com a loja.")
		catalog_updated.emit()
		if callback.is_valid():
			callback.call(ok))


func install(entry: Dictionary) -> bool:
	if busy_id != "":
		return false
	busy_id = str(entry.id)
	busy_size = int(entry.get("size", 0))
	Sys.call_tool("console-store", PackedStringArray(["install", busy_id, str(entry.url), str(entry.sha256)]), func(r: Dictionary) -> void:
		var id := busy_id
		busy_id = ""
		var msg := _last_line(str(r.out), "")
		install_finished.emit(id, r.code == 0, msg)
		_next_in_queue())
	return true


## Instala vários, um de cada vez.
func install_all(entries: Array) -> void:
	_queue.append_array(entries)
	if busy_id == "":
		_next_in_queue()


func _next_in_queue() -> void:
	if _queue.is_empty() or busy_id != "":
		return
	install(_queue.pop_front())


func remove(id: String, callback: Callable) -> void:
	Sys.call_tool("console-store", PackedStringArray(["remove", id]), callback)


## Progresso do download atual (0..1), pelo tamanho do arquivo parcial.
func progress() -> float:
	if busy_id == "" or busy_size <= 0:
		return 0.0
	var path := user_games_dir().path_join(".download").path_join(busy_id + ".tar.gz")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0.0
	return clampf(float(f.get_length()) / busy_size, 0.0, 1.0)


func size_mb(entry: Dictionary) -> String:
	return "%d MB" % int(ceil(int(entry.get("size", 0)) / 1048576.0))


static func _last_line(text: String, fallback: String) -> String:
	var lines := text.strip_edges().split("\n", false)
	return lines[lines.size() - 1] if lines.size() > 0 else fallback
