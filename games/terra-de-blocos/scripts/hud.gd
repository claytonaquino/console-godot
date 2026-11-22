class_name Hud
extends Control
## Interface desenhada à mão (_draw): corações, recargas, moedas, objetivo,
## barra do chefe, falas, menus, título e resultados.

var main: Node
var font: Font

var objective := ""
var toast_text := ""
var toast_t := 0.0
var prompt := ""
var fade := 0.0

var bark_speaker := ""
var bark_text := ""
var bark_t := 0.0

var dlg_lines: Array = []
var dlg_index := 0
var dlg_chars := 0.0
var dlg_active := false

var menu_active := false
var menu_title := ""
var menu_items: Array = []       # [{label, desc, enabled}]
var menu_index := 0
var menu_footer := ""

var title_active := false
var results: Dictionary = {}
var _t := 0.0

const SPEAKER_COLORS := {
	"Iara": Color(1.0, 0.55, 0.3), "Bento": Color(0.45, 0.7, 1.0), "Artefato": Color(0.3, 0.95, 1.0),
	"NÚCLEO-0": Color(1.0, 0.3, 0.8), "Zuza": Color(0.7, 0.95, 0.5), "Tico": Color(0.95, 0.85, 0.4),
	"Placa": Color(0.9, 0.8, 0.6),
}


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func toast(text: String, seconds := 2.2) -> void:
	toast_text = text
	toast_t = seconds


func bark(speaker: String, text: String) -> void:
	bark_speaker = speaker
	bark_text = text
	bark_t = 3.2


func start_dialogue(lines: Array) -> void:
	dlg_lines = lines
	dlg_index = 0
	dlg_chars = 0.0
	dlg_active = not lines.is_empty()


## Avança a fala. Retorna false quando acabou.
func advance_dialogue() -> bool:
	if not dlg_active:
		return false
	var full: String = dlg_lines[dlg_index][1]
	if dlg_chars < full.length():
		dlg_chars = full.length()
		return true
	dlg_index += 1
	dlg_chars = 0.0
	if dlg_index >= dlg_lines.size():
		dlg_active = false
		return false
	return true


func open_menu(title: String, items: Array, footer := "A / Enter: escolher    B / Esc: voltar") -> void:
	menu_title = title
	menu_items = items
	menu_index = 0
	menu_footer = footer
	menu_active = true
	_skip_disabled(1)


func move_menu(d: int) -> void:
	if menu_items.is_empty():
		return
	menu_index = (menu_index + d + menu_items.size()) % menu_items.size()
	_skip_disabled(d)


func _skip_disabled(d: int) -> void:
	for i in menu_items.size():
		if menu_items[menu_index].get("enabled", true):
			return
		menu_index = (menu_index + d + menu_items.size()) % menu_items.size()


func _process(delta: float) -> void:
	_t += delta
	toast_t = maxf(0.0, toast_t - delta)
	bark_t = maxf(0.0, bark_t - delta)
	if dlg_active:
		dlg_chars += delta * 55.0
	queue_redraw()


# ---------------------------------------------------------------- desenho

func _txt(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 8) -> void:
	if outline > 0:
		draw_string_outline(font, pos, text, align, width, size, outline, Color(0, 0, 0, 0.75 * color.a))
	draw_string(font, pos, text, align, width, size, color)


func _panel(r: Rect2, color := Color(0.08, 0.07, 0.12, 0.82), border := Color(1, 1, 1, 0.15)) -> void:
	draw_rect(r, color)
	draw_rect(r, border, false, 3.0)


func _brick(pos: Vector2, s: float, color: Color) -> void:
	draw_rect(Rect2(pos, Vector2(s, s * 0.8)), color)
	draw_rect(Rect2(pos + Vector2(s * 0.15, -s * 0.18), Vector2(s * 0.28, s * 0.2)), color.lightened(0.15))
	draw_rect(Rect2(pos + Vector2(s * 0.57, -s * 0.18), Vector2(s * 0.28, s * 0.2)), color.lightened(0.15))
	draw_rect(Rect2(pos, Vector2(s, s * 0.8)), color.darkened(0.4), false, 2.0)


func _draw() -> void:
	var vs := get_viewport_rect().size
	if main == null:
		return
	if title_active:
		_draw_title(vs)
	elif not results.is_empty():
		_draw_results(vs)
	else:
		_draw_game(vs)
	if dlg_active:
		_draw_dialogue(vs)
	if menu_active:
		_draw_menu(vs)
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, fade))


func _draw_game(vs: Vector2) -> void:
	var heroes: Array = main.heroes
	for i in heroes.size():
		var h: Hero = heroes[i]
		if not is_instance_valid(h):
			continue
		var x := 30.0 if i == 0 else vs.x - 450.0
		_draw_hero_panel(Vector2(x, 26), h, i)
	if heroes.size() < 2 and main.state == "mission" and main.p2_available():
		_txt(Vector2(vs.x - 440, 60), "Jogador 2: aperte Start", 26, Color(1, 1, 1, 0.6 + 0.3 * sin(_t * 4.0)))
	# Moedas e blocos
	var cx := vs.x * 0.5
	_panel(Rect2(cx - 170, 20, 340, 62))
	draw_circle(Vector2(cx - 130, 51), 16, Color(1.0, 0.8, 0.2))
	draw_circle(Vector2(cx - 130, 51), 9, Color(0.9, 0.65, 0.1))
	_txt(Vector2(cx - 105, 63), str(main.coins_total()), 34, Color(1, 0.9, 0.5))
	_brick(Vector2(cx + 30, 42), 30, Color(0.3, 0.7, 1.0))
	_txt(Vector2(cx + 72, 63), str(main.blocks_total()), 34, Color(0.6, 0.85, 1.0))
	if objective != "":
		_txt(Vector2(0, 122), objective, 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if toast_t > 0.0:
		var a := clampf(toast_t * 2.0, 0.0, 1.0)
		_txt(Vector2(0, vs.y * 0.36), toast_text, 64, Color(1, 0.92, 0.4, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 14)
	if prompt != "" and not menu_active and not dlg_active:
		_panel(Rect2(cx - 260, vs.y - 150, 520, 56))
		_txt(Vector2(cx - 260, vs.y - 110), prompt, 30, Color(1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 520)
	if bark_t > 0.0 and not dlg_active:
		var a := clampf(bark_t * 2.0, 0.0, 1.0)
		_panel(Rect2(30, vs.y - 230, 700, 90), Color(0.08, 0.07, 0.12, 0.8 * a), Color(1, 1, 1, 0.15 * a))
		var sc: Color = SPEAKER_COLORS.get(bark_speaker, Color.WHITE)
		_txt(Vector2(50, vs.y - 195), bark_speaker, 26, Color(sc, a))
		_txt(Vector2(50, vs.y - 158), bark_text, 26, Color(1, 1, 1, a))
	var boss: Variant = main.boss
	if boss != null and is_instance_valid(boss) and not boss.dead:
		_draw_boss(vs, boss)


func _draw_hero_panel(pos: Vector2, h: Hero, index: int) -> void:
	_panel(Rect2(pos, Vector2(420, 150)))
	var col := Color(1.0, 0.55, 0.3) if h.kind == "iara" else Color(0.45, 0.7, 1.0)
	_txt(pos + Vector2(18, 40), "J%d  %s" % [index + 1, h.display_name], 30, col)
	for k in h.max_hearts:
		var hp := pos + Vector2(18 + k * 44, 58)
		var full := k < h.hearts
		_brick(hp, 34, Color(0.92, 0.18, 0.25) if full else Color(0.25, 0.2, 0.22))
	# Recargas
	var bars := [["Y  " + ("Chuva de flechas" if h.kind == "iara" else "Onda de choque"), h.special_cd, h.special_max * h.cooldown_mult],
		["B  " + ("Flecha de gelo" if h.kind == "iara" else "Escudo"), h.alt_cd, h.alt_max * h.cooldown_mult]]
	for k in bars.size():
		var y := pos.y + 108 + k * 22
		var cd: float = bars[k][1]
		var mx: float = bars[k][2]
		var frac := 1.0 - clampf(cd / maxf(mx, 0.01), 0.0, 1.0)
		draw_rect(Rect2(pos.x + 18, y, 170, 14), Color(0.2, 0.2, 0.25))
		draw_rect(Rect2(pos.x + 18, y, 170 * frac, 14), Color(0.4, 0.9, 1.0) if frac >= 1.0 else Color(0.35, 0.5, 0.7))
		_txt(Vector2(pos.x + 200, y + 14), bars[k][0], 20, Color(1, 1, 1, 0.9 if frac >= 1.0 else 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	if h.down:
		_panel(Rect2(pos + Vector2(0, 156), Vector2(420, 44)), Color(0.4, 0.05, 0.05, 0.85))
		var msg := "CAÍDO! Fique perto para reanimar" if main.heroes.size() > 1 else "Caído! Voltando..."
		_txt(pos + Vector2(14, 188), msg, 22, Color(1, 0.8, 0.8))
		draw_rect(Rect2(pos.x, pos.y + 196, 420 * h.revive_progress, 4), Color(0.4, 1.0, 0.5))


func _draw_boss(vs: Vector2, boss: Machine) -> void:
	var w := minf(900.0, vs.x - 200)
	var x := (vs.x - w) * 0.5
	var y := vs.y - 110
	_panel(Rect2(x - 20, y - 50, w + 40, 100))
	_txt(Vector2(x, y - 16), "COLOSSO DE SUCATA", 30, Color(1, 0.5, 0.4))
	draw_rect(Rect2(x, y, w, 22), Color(0.2, 0.1, 0.1))
	draw_rect(Rect2(x, y, w * clampf(boss.hp / boss.max_hp, 0, 1), 22), Color(0.9, 0.2, 0.2))
	var names := {"misseis": "Mísseis", "canhao_e": "Canhão E", "canhao_d": "Canhão D", "nucleo": "Núcleo"}
	var px := x + 360
	for p in boss.parts:
		if not names.has(p.name):
			continue
		var alive: bool = p.alive
		var label: String = names[p.name]
		var c := Color(1, 0.85, 0.3) if alive else Color(0.5, 0.5, 0.5)
		if p.name == "nucleo":
			c = Color(1, 0.4, 0.9) if boss.flags.has("core_open") else Color(0.6, 0.6, 0.7)
			label += " (aberto)" if boss.flags.has("core_open") else " (blindado)"
		elif not alive:
			label += " X"
		_txt(Vector2(px, y - 16), label, 22, c)
		px += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 26


func _draw_dialogue(vs: Vector2) -> void:
	var line: Array = dlg_lines[dlg_index]
	var r := Rect2(vs.x * 0.5 - 760, vs.y - 290, 1520, 230)
	_panel(r, Color(0.06, 0.05, 0.1, 0.92), Color(1, 1, 1, 0.25))
	var sc: Color = SPEAKER_COLORS.get(line[0], Color.WHITE)
	_txt(r.position + Vector2(40, 56), line[0], 36, sc)
	var full: String = line[1]
	var shown := full.substr(0, int(dlg_chars))
	draw_multiline_string(font, r.position + Vector2(40, 110), shown, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 34, -1, Color(1, 1, 1))
	if dlg_chars >= full.length():
		_txt(r.position + Vector2(r.size.x - 260, r.size.y - 22), "A / Enter  >", 26, Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 5.0)))


func _draw_menu(vs: Vector2) -> void:
	var h := 170.0 + menu_items.size() * 74.0
	var r := Rect2(vs.x * 0.5 - 520, vs.y * 0.5 - h * 0.5 + (170.0 if title_active else 0.0), 1040, h)
	_panel(r, Color(0.06, 0.05, 0.1, 0.94), Color(1, 0.85, 0.4, 0.4))
	_txt(Vector2(r.position.x, r.position.y + 64), menu_title, 46, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in menu_items.size():
		var it: Dictionary = menu_items[i]
		var y := r.position.y + 100 + i * 74
		var sel := i == menu_index
		var en: bool = it.get("enabled", true)
		if sel:
			draw_rect(Rect2(r.position.x + 30, y, r.size.x - 60, 66), Color(1, 0.85, 0.4, 0.18))
			draw_rect(Rect2(r.position.x + 30, y, 8, 66), Color(1, 0.85, 0.4))
		_txt(Vector2(r.position.x + 60, y + 32), it.label, 32, Color(1, 1, 1, 1.0 if en else 0.35))
		if it.has("desc"):
			_txt(Vector2(r.position.x + 60, y + 58), it.desc, 20, Color(0.8, 0.8, 0.85, 0.9 if en else 0.35))
		if it.has("right"):
			_txt(Vector2(r.position.x + 60, y + 32), it.right, 28, Color(1, 0.9, 0.5, 1.0 if en else 0.35), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 120)
	_txt(Vector2(r.position.x, r.end.y - 22), menu_footer, 22, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_title(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.25))
	var y := vs.y * 0.26
	var letters := "TERRA DE BLOCOS"
	var cols := [Color(0.95, 0.3, 0.25), Color(0.98, 0.75, 0.2), Color(0.3, 0.75, 0.35), Color(0.25, 0.55, 0.95)]
	var total := font.get_string_size(letters, HORIZONTAL_ALIGNMENT_LEFT, -1, 120).x
	var x := (vs.x - total) * 0.5
	for i in letters.length():
		var ch := letters[i]
		var bob := sin(_t * 3.0 + i * 0.5) * 6.0
		_txt(Vector2(x, y + bob), ch, 120, cols[i % cols.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 120).x
	_txt(Vector2(0, y + 80), "O Despertar das Máquinas", 48, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 12)
	_txt(Vector2(0, vs.y - 40), "v" + str(ProjectSettings.get_setting("application/config/version", "")) + "  ·  1 ou 2 jogadores  ·  Capítulo 1",
		22, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_results(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var r := Rect2(vs.x * 0.5 - 480, vs.y * 0.5 - 300, 960, 600)
	_panel(r, Color(0.06, 0.05, 0.1, 0.94), Color(1, 0.85, 0.4, 0.5))
	_txt(Vector2(r.position.x, r.position.y + 80), results.get("title", "Missão concluída!"), 54, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12)
	_txt(Vector2(r.position.x, r.position.y + 130), results.get("subtitle", ""), 28, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var rows: Array = results.get("rows", [])
	for i in rows.size():
		var y := r.position.y + 210 + i * 56
		_txt(Vector2(r.position.x + 90, y), rows[i][0], 32, Color(1, 1, 1))
		_txt(Vector2(r.position.x + 90, y), str(rows[i][1]), 32, Color(1, 0.9, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 180)
	_txt(Vector2(r.position.x, r.end.y - 40), "A / Enter: continuar", 26, Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 4.0)), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
