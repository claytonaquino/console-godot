class_name Machine
extends CharacterBody3D
## Máquinas inimigas. Cada uma tem "peças": o corpo e pontos fracos que
## levam dano extra, se soltam quando destruídos e mudam o comportamento.
##
##  rastejante: pequena, morde de perto. Sensor (olho) destruído = fica cega.
##  zumbidor:   voa e atira. Hélice destruída = despenca.
##  chifrudo:   média, investe em linha reta. Tanque destruído = explode e
##              para de investir; chifre destruído = investida fraca.
##  colosso:    chefe. Lançador de mísseis e canhões destacáveis; o núcleo
##              só fica vulnerável quando os dois canhões caem.

signal died(m: Machine)

const TYPES := {
	"rastejante": {"hp": 40.0, "speed": 4.4, "radius": 0.9, "coins": 6, "blocks": 1, "color": Color(0.45, 0.5, 0.58)},
	"zumbidor": {"hp": 30.0, "speed": 4.0, "radius": 0.7, "coins": 8, "blocks": 1, "color": Color(0.85, 0.75, 0.2)},
	"chifrudo": {"hp": 150.0, "speed": 3.0, "radius": 1.5, "coins": 25, "blocks": 4, "color": Color(0.55, 0.3, 0.2)},
	"colosso": {"hp": 800.0, "speed": 2.2, "radius": 3.0, "coins": 150, "blocks": 20, "color": Color(0.35, 0.36, 0.4)},
}

var type := "rastejante"
var world: Node
var hp := 40.0
var max_hp := 40.0
var speed := 4.0
var radius := 1.0
var parts: Array[Dictionary] = []
var frozen_t := 0.0
var stun_t := 0.0
var dead := false
var phase := 1
var flags := {}               # comportamentos perdidos: "blind", "no_charge"...
var state := "idle"
var state_t := 0.0
var target: Hero
var home := Vector3.ZERO

var _model: Node3D
var _ice: MeshInstance3D
var _anim_t := 0.0
var _anim_acc := 0.0
var _cool := {}
var _charge_dir := Vector3.ZERO
var _legs: Array[Node3D] = []
var _rotor: Node3D
var _summoned := false


func setup(t: String, w: Node) -> void:
	type = t
	world = w
	var cfg: Dictionary = TYPES[t]
	max_hp = cfg.hp
	hp = max_hp
	speed = cfg.speed
	radius = cfg.radius


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	home = global_position
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = minf(radius, 2.2)
	cap.height = maxf(cap.radius * 2.0, 1.2)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)
	_model = Node3D.new()
	add_child(_model)
	call("_build_" + type)
	_ice = MeshInstance3D.new()
	_ice.mesh = Bricks.box_mesh()
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.6, 0.9, 1.0, 0.45)
	im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.emission_enabled = true
	im.emission = Color(0.3, 0.6, 0.9)
	_ice.material_override = im
	_ice.scale = Vector3(radius * 2.2, radius * 1.8, radius * 2.2)
	_ice.position.y = radius * 0.9
	_ice.visible = false
	add_child(_ice)
	_cool = {"attack": randf_range(0.5, 1.5), "missiles": 5.0, "volley": 3.0, "stomp": 1.0, "charge": 2.0}


# ---------------------------------------------------------------- peças

func _part(name: String, node: Node3D, r: float, part_hp: float, mult: float, weak: bool, color: Color) -> void:
	parts.append({"name": name, "node": node, "radius": r, "hp": part_hp, "max_hp": part_hp,
		"mult": mult, "weak": weak, "alive": true, "color": color})


func part_pos(p: Dictionary) -> Vector3:
	return (p.node as Node3D).global_position


## Peça atingida por um segmento (flecha). Retorna {} se nada.
func hit_segment(a: Vector3, b: Vector3, r: float) -> Dictionary:
	if dead:
		return {}
	var best := {}
	var best_t := 2.0
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1e-6)
	for p in parts:
		if not p.alive:
			continue
		var c := part_pos(p)
		var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		var d := (a + ab * t).distance_to(c)
		var reach: float = p.radius + r
		# Pontos fracos têm prioridade quando o segmento passa perto dos dois.
		var score := t - (0.05 if p.weak else 0.0)
		if d <= reach and score < best_t:
			best_t = score
			best = p
	return best


func parts_in_sphere(center: Vector3, r: float) -> Array:
	var out := []
	for p in parts:
		if p.alive and part_pos(p).distance_to(center) <= r + p.radius:
			out.append(p)
	return out


func body_part() -> Dictionary:
	return parts[0]


## Aplica dano numa peça. kind: "arrow", "melee", "area", "ice"
func take(p: Dictionary, dmg: float, kind: String, from: Vector3) -> void:
	if dead:
		return
	var mult: float = p.mult
	var label := ""
	var color := Color.WHITE
	if p.name == "nucleo":
		if flags.has("core_open"):
			mult = 3.0
		else:
			mult = 0.3
			label = "Blindado!"
			color = Color(0.7, 0.7, 0.7)
	if frozen_t > 0.0 and kind == "melee":
		mult *= 3.0
		frozen_t = 0.0
		_ice.visible = false
		world.fx.popup(global_position + Vector3(0, radius * 2.2, 0), "DESPEDAÇOU!", Color(0.5, 0.95, 1.0), 96)
		world.fx.debris(global_position + Vector3(0, radius, 0), Color(0.7, 0.95, 1.0), 14, 7.0)
		world.sfx.play("shatter")
	var eff := dmg * mult
	if p.weak and p.name != "nucleo":
		label = "CRÍTICO!"
		color = Color(1.0, 0.85, 0.2)
		world.sfx.play("crit")
	else:
		world.sfx.play("hit")
	world.fx.popup(part_pos(p) + Vector3(0, 0.6, 0), ("%d" % int(round(eff))) + (" " + label if label != "" else ""), color, 64 if label == "" else 80)
	world.fx.debris(part_pos(p), p.color, 3, 3.0)
	hp -= eff
	if p.weak and p.alive:
		p.hp -= dmg * (2.0 if p.name == "nucleo" and flags.has("core_open") else 1.0)
		if p.hp <= 0.0 and p.name != "nucleo":
			_lose_part(p)
	if kind == "area" and type in ["rastejante", "zumbidor"]:
		stun_t = maxf(stun_t, 0.6)
		var push := global_position - from
		push.y = 0
		if push.length() > 0.01:
			velocity = push.normalized() * 10.0
	if hp <= 0.0:
		_die()


func freeze(seconds: float) -> void:
	if dead:
		return
	if type == "colosso":
		flags["slow"] = seconds
		world.fx.popup(global_position + Vector3(0, 6.0, 0), "Lento!", Color(0.5, 0.9, 1.0))
		return
	frozen_t = seconds
	_ice.visible = true
	world.fx.popup(global_position + Vector3(0, radius * 2.0, 0), "Congelado!", Color(0.5, 0.9, 1.0))


func _lose_part(p: Dictionary) -> void:
	p.alive = false
	var n: Node3D = p.node
	world.fx.debris(n.global_position, p.color, 16, 8.0)
	world.fx.popup(n.global_position + Vector3(0, 1.0, 0), "Peça destruída!", Color(1.0, 0.6, 0.2), 80)
	world.sfx.play("boom")
	n.visible = false
	hp -= 15.0
	match p.name:
		"sensor":
			flags["blind"] = true
		"helice":
			flags["falling"] = true
		"tanque":
			flags["no_charge"] = true
			world.explosion(n.global_position, 3.5, 1, self)
			hp -= 25.0
		"chifre":
			flags["weak_charge"] = true
		"misseis":
			flags["no_missiles"] = true
			world.dialogue_bark("Iara", "Sem mísseis! Agora os canhões!")
		"canhao_e", "canhao_d":
			if not _part_alive("canhao_e") and not _part_alive("canhao_d"):
				flags["no_cannons"] = true
				flags["core_open"] = true
				world.fx.popup(global_position + Vector3(0, 7.5, 0), "NÚCLEO EXPOSTO!", Color(1.0, 0.3, 0.9), 110)
				world.dialogue_bark("Bento", "O núcleo brilhando! Mira ali!")
	if hp <= 0.0:
		_die()


func _part_alive(name: String) -> bool:
	for p in parts:
		if p.name == name:
			return p.alive
	return false


func _die() -> void:
	if dead:
		return
	dead = true
	var cfg: Dictionary = TYPES[type]
	world.fx.debris(global_position + Vector3(0, radius, 0), cfg.color, 22 if type != "colosso" else 60, 9.0)
	world.fx.ring(global_position, radius * 2.5, Color(1, 0.6, 0.2))
	world.sfx.play("boom")
	world.drop_loot(global_position, cfg.coins, cfg.blocks)
	died.emit(self)
	queue_free()


# ---------------------------------------------------------------- IA

func _cooldown(key: String, delta: float) -> bool:
	_cool[key] = float(_cool.get(key, 0.0)) - delta
	return _cool[key] <= 0.0


func _physics_process(delta: float) -> void:
	if dead or world.paused:
		return
	state_t += delta
	if flags.has("slow"):
		flags["slow"] = float(flags["slow"]) - delta
		if flags["slow"] <= 0.0:
			flags.erase("slow")
	if frozen_t > 0.0:
		frozen_t -= delta
		if frozen_t <= 0.0:
			_ice.visible = false
		velocity = Vector3.ZERO
		return
	if stun_t > 0.0:
		stun_t -= delta
		velocity = velocity.move_toward(Vector3.ZERO, delta * 30.0)
		move_and_slide()
		return
	target = world.nearest_hero(global_position)
	call("_ai_" + type, delta)


func _to_target() -> Vector3:
	if target == null:
		return Vector3.ZERO
	var d := target.global_position - global_position
	d.y = 0
	return d


func _face(dir: Vector3, delta: float, rate := 8.0) -> void:
	if dir.length() < 0.01:
		return
	var cur := -_model.global_basis.z
	cur.y = 0
	var want := dir.normalized()
	var nd := cur.slerp(want, clampf(delta * rate, 0.0, 1.0)) if cur.length() > 0.1 else want
	_model.basis = Basis.looking_at(nd, Vector3.UP)


func _walk(dir: Vector3, spd: float, delta: float) -> void:
	if spd > 0.0 and state in ["idle", "chase", "walk"] and dir.length() > 0.01:
		dir = world.path_dir(global_position, dir)
	if flags.has("slow"):
		spd *= 0.4
	var v := dir.normalized() * spd if dir.length() > 0.01 else Vector3.ZERO
	velocity = Vector3(v.x, velocity.y - 30.0 * delta, v.z)
	if is_on_floor():
		velocity.y = -1.0
	move_and_slide()


func _ai_rastejante(delta: float) -> void:
	if target == null:
		_walk(Vector3.ZERO, 0, delta)
		return
	var to := _to_target()
	var dist := to.length()
	if flags.has("blind"):
		# Cega: anda em zigue-zague e erra o alvo
		to = to.rotated(Vector3.UP, sin(state_t * 2.0) * 1.3)
	match state:
		"idle", "chase":
			state = "chase"
			_face(to, delta)
			if dist > 1.8:
				_walk(to, speed, delta)
			else:
				_walk(Vector3.ZERO, 0, delta)
			if dist < 2.6 and _cooldown("attack", delta):
				state = "windup"
				state_t = 0.0
		"windup":
			_walk(Vector3.ZERO, 0, delta)
			_face(to, delta, 4.0)
			if state_t > 0.45:
				state = "lunge"
				state_t = 0.0
				_charge_dir = -_model.global_basis.z
				_charge_dir.y = 0
		"lunge":
			_walk(_charge_dir, 11.0, delta)
			world.hit_heroes(global_position + _charge_dir * 0.8, 1.1, 1, global_position)
			if state_t > 0.22:
				state = "chase"
				_cool["attack"] = randf_range(1.2, 2.0)


func _ai_zumbidor(delta: float) -> void:
	_rotor.rotation.y += delta * 30.0
	if flags.has("falling"):
		velocity = Vector3(velocity.x * 0.95, velocity.y - 25.0 * delta, velocity.z * 0.95)
		move_and_slide()
		_model.rotation.z += delta * 8.0
		if is_on_floor() or global_position.y < 0.3:
			world.explosion(global_position, 2.5, 1, self)
			hp = 0
			_die()
		return
	var hover := 2.6 + sin(state_t * 3.0) * 0.25
	var vy := (hover - global_position.y) * 4.0
	if target == null:
		velocity = Vector3(0, vy, 0)
		move_and_slide()
		return
	var to := _to_target()
	var dist := to.length()
	_face(to, delta)
	var want := Vector3.ZERO
	if dist > 9.0:
		want = to.normalized()
	elif dist < 6.0:
		want = -to.normalized()
	else:
		want = to.normalized().rotated(Vector3.UP, PI / 2.0) * 0.6
	var v := want * speed
	velocity = Vector3(v.x, vy, v.z)
	move_and_slide()
	if dist < 14.0 and _cooldown("attack", delta):
		_cool["attack"] = randf_range(2.0, 2.8)
		var from := global_position + Vector3(0, -0.2, 0)
		var aim := target.global_position + Vector3(0, 1.0, 0) - from
		world.spawn_bolt(self, from, aim.normalized(), 9.0, 1, Color(1.0, 0.5, 0.1))


func _ai_chifrudo(delta: float) -> void:
	for i in _legs.size():
		_legs[i].rotation.x = sin(_anim_t * 9.0 + i * PI) * 0.4 if state == "chase" else 0.0
	if target == null:
		_walk(Vector3.ZERO, 0, delta)
		return
	var to := _to_target()
	var dist := to.length()
	match state:
		"idle", "chase":
			state = "chase"
			_face(to, delta, 4.0)
			if dist > 2.8:
				_walk(to, speed, delta)
			else:
				_walk(Vector3.ZERO, 0, delta)
			if dist < 3.2 and _cooldown("attack", delta):
				state = "stomp"
				state_t = 0.0
				world.fx.telegraph(global_position, 3.4, 0.7)
			elif not flags.has("no_charge") and dist > 5.0 and dist < 16.0 and _cooldown("charge", delta):
				state = "aim"
				state_t = 0.0
		"stomp":
			_walk(Vector3.ZERO, 0, delta)
			if state_t > 0.7:
				world.hit_heroes(global_position, 3.4, 1, global_position)
				world.fx.ring(global_position, 3.6, Color(1, 0.6, 0.3))
				world.sfx.play("boom")
				state = "chase"
				_cool["attack"] = 2.0
		"aim":
			_walk(Vector3.ZERO, 0, delta)
			_face(to, delta, 6.0)
			if state_t < 0.05:
				var d := to.normalized()
				for k in 6:
					world.fx.telegraph(global_position + d * (2.0 + k * 2.4), 1.2, 0.9)
			if state_t > 0.9:
				state = "charge"
				state_t = 0.0
				_charge_dir = -_model.global_basis.z
				_charge_dir.y = 0
				_charge_dir = _charge_dir.normalized()
		"charge":
			var before := global_position
			_walk(_charge_dir, 15.0, delta)
			var dmg := 1 if flags.has("weak_charge") else 2
			world.hit_heroes(global_position + _charge_dir * 1.2, 1.6, dmg, global_position)
			var moved := before.distance_to(global_position)
			if state_t > 0.12 and moved < 15.0 * delta * 0.3:
				# Bateu na parede: fica tonto
				state = "chase"
				stun_t = 1.8 if not flags.has("weak_charge") else 0.8
				world.fx.popup(global_position + Vector3(0, 3.0, 0), "Tonto!", Color(1, 1, 0.5))
				world.sfx.play("boom")
				_cool["charge"] = 4.0
			elif state_t > 1.1:
				state = "chase"
				_cool["charge"] = randf_range(3.5, 5.0)


func _ai_colosso(delta: float) -> void:
	for i in _legs.size():
		_legs[i].rotation.x = sin(_anim_t * 3.0 + i * PI) * 0.25
	if phase == 1 and hp < max_hp * 0.5:
		phase = 2
		speed *= 1.3
		world.dialogue_bark("NÚCLEO-0", "Reforços! Destruam os insetos de carne!")
		if not _summoned:
			_summoned = true
			for k in 2:
				world.spawn_machine("rastejante", global_position + Vector3(randf_range(-6, 6), 0, randf_range(4, 8)))
	if target == null:
		_walk(Vector3.ZERO, 0, delta)
		return
	var to := _to_target()
	var dist := to.length()
	match state:
		"idle", "walk":
			state = "walk"
			_face(to, delta, 1.5)
			_walk(to if dist > 5.0 else Vector3.ZERO, speed, delta)
			if dist < 6.0 and _cooldown("stomp", delta):
				state = "stomp"
				state_t = 0.0
				world.fx.telegraph(global_position, 6.0, 1.0)
			elif not flags.has("no_missiles") and _cooldown("missiles", delta):
				state = "missiles"
				state_t = 0.0
				var spots: Array[Vector3] = []
				for h in world.living_heroes():
					spots.append(h.global_position)
				for k in (2 if phase == 1 else 4):
					spots.append(global_position + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)))
				for s in spots:
					world.fx.telegraph(s, 2.4, 1.4)
				world.schedule(1.4, func() -> void:
					for s in spots:
						world.explosion(s, 2.4, 1, self)
					)
				_cool["missiles"] = 8.0 if phase == 1 else 6.0
			elif not flags.has("no_cannons") and _cooldown("volley", delta):
				_cool["volley"] = 3.2 if phase == 1 else 2.4
				for pn in ["canhao_e", "canhao_d"]:
					for p in parts:
						if p.name == pn and p.alive:
							var from := part_pos(p)
							var aim := (target.global_position + Vector3(0, 1, 0) - from).normalized()
							for k in 3:
								world.spawn_bolt(self, from, aim.rotated(Vector3.UP, (k - 1) * 0.18), 11.0, 1, Color(1, 0.3, 0.2))
		"stomp":
			_walk(Vector3.ZERO, 0, delta)
			if state_t > 1.0:
				world.hit_heroes(global_position, 6.0, 1, global_position)
				world.fx.ring(global_position, 6.5, Color(1, 0.5, 0.2))
				world.fx.debris(global_position, Color(0.4, 0.3, 0.2), 12, 6.0)
				world.sfx.play("boom")
				world.shake(0.5)
				state = "walk"
				_cool["stomp"] = 3.5 if phase == 1 else 2.6
		"missiles":
			_walk(Vector3.ZERO, 0, delta)
			if state_t > 0.8:
				state = "walk"


func _process(delta: float) -> void:
	_anim_t += delta


# ---------------------------------------------------------------- modelos

func _build_rastejante() -> void:
	var c: Color = TYPES.rastejante.color
	var body := Bricks.joint(_model, Vector3(0, 0.55, 0))
	Bricks.piece(body, Vector3.ZERO, Vector3(1.0, 0.5, 1.4), c, true)
	Bricks.piece(body, Vector3(0, 0.05, -0.85), Vector3(0.7, 0.4, 0.4), c.darkened(0.2))
	Bricks.piece(body, Vector3(0, 0.1, 0.95), Vector3(0.2, 0.2, 0.6), c.darkened(0.3))  # cauda
	for sx in [-1.0, 1.0]:
		for sz in [-0.45, 0.45]:
			var leg := Bricks.joint(body, Vector3(0.55 * sx, -0.1, sz))
			Bricks.piece(leg, Vector3(0.12 * sx, -0.2, 0), Vector3(0.16, 0.45, 0.16), c.darkened(0.35))
			_legs.append(leg)
	_part("corpo", body, 0.85, 999, 1.0, false, c)
	var eye := Bricks.joint(body, Vector3(0, 0.12, -1.08))
	Bricks.piece(eye, Vector3.ZERO, Vector3(0.36, 0.26, 0.12), Color(0.2, 0.8, 1.0), false, true)
	_part("sensor", eye, 0.35, 14.0, 2.5, true, Color(0.2, 0.8, 1.0))


func _build_zumbidor() -> void:
	var c: Color = TYPES.zumbidor.color
	var body := Bricks.joint(_model, Vector3.ZERO)
	Bricks.piece(body, Vector3.ZERO, Vector3(0.9, 0.5, 0.9), c, false)
	Bricks.piece(body, Vector3(0, -0.3, -0.3), Vector3(0.3, 0.25, 0.4), Color(0.2, 0.2, 0.22))
	Bricks.piece(body, Vector3(0, -0.05, -0.5), Vector3(0.25, 0.18, 0.06), Color(1.0, 0.4, 0.1), false, true)
	_part("corpo", body, 0.6, 999, 1.0, false, c)
	_rotor = Bricks.joint(body, Vector3(0, 0.45, 0))
	Bricks.piece(_rotor, Vector3.ZERO, Vector3(1.8, 0.06, 0.2), Color(0.25, 0.25, 0.27))
	Bricks.piece(_rotor, Vector3.ZERO, Vector3(0.2, 0.06, 1.8), Color(0.25, 0.25, 0.27))
	Bricks.piece(_rotor, Vector3(0, -0.1, 0), Vector3(0.25, 0.2, 0.25), Color(0.9, 0.2, 0.15))
	_part("helice", _rotor, 0.5, 10.0, 2.5, true, Color(0.9, 0.2, 0.15))


func _build_chifrudo() -> void:
	var c: Color = TYPES.chifrudo.color
	var body := Bricks.joint(_model, Vector3(0, 1.2, 0))
	Bricks.piece(body, Vector3.ZERO, Vector3(1.8, 1.1, 2.6), c, true)
	Bricks.piece(body, Vector3(0, -0.1, -1.5), Vector3(1.2, 0.9, 0.6), c.darkened(0.25))
	for sx in [-1.0, 1.0]:
		for sz in [-0.8, 0.8]:
			var leg := Bricks.joint(body, Vector3(0.75 * sx, -0.5, sz))
			Bricks.piece(leg, Vector3(0, -0.35, 0), Vector3(0.4, 0.8, 0.4), c.darkened(0.4))
			_legs.append(leg)
	for sx in [-1.0, 1.0]:
		Bricks.piece(body, Vector3(0.28 * sx, 0.05, -1.82), Vector3(0.16, 0.12, 0.05), Color(1, 0.2, 0.1), false, true)
	_part("corpo", body, 1.4, 999, 1.0, false, c)
	var horn := Bricks.joint(body, Vector3(0, 0.3, -2.0))
	Bricks.piece(horn, Vector3(0, 0, -0.2), Vector3(0.25, 0.25, 0.9), Color(0.92, 0.88, 0.75))
	Bricks.piece(horn, Vector3(0, 0.25, -0.1), Vector3(0.2, 0.5, 0.2), Color(0.92, 0.88, 0.75))
	_part("chifre", horn, 0.5, 35.0, 2.0, true, Color(0.92, 0.88, 0.75))
	var tank := Bricks.joint(body, Vector3(0, 0.85, 0.6))
	Bricks.piece(tank, Vector3.ZERO, Vector3(0.9, 0.6, 1.0), Color(0.2, 0.9, 0.4), false, true)
	Bricks.piece(tank, Vector3(0, 0.35, 0), Vector3(1.0, 0.1, 0.2), Color(0.2, 0.2, 0.2))
	_part("tanque", tank, 0.6, 30.0, 3.0, true, Color(0.2, 0.9, 0.4))


func _build_colosso() -> void:
	var c: Color = TYPES.colosso.color
	var hip := Bricks.joint(_model, Vector3(0, 3.2, 0))
	for sx in [-1.0, 1.0]:
		var leg := Bricks.joint(hip, Vector3(1.3 * sx, 0, 0))
		Bricks.piece(leg, Vector3(0, -1.0, 0), Vector3(1.0, 2.0, 1.2), c.darkened(0.3), true)
		Bricks.piece(leg, Vector3(0, -2.9, -0.3), Vector3(1.5, 0.6, 2.2), c.darkened(0.45), true)
		_legs.append(leg)
	var body := Bricks.joint(hip, Vector3(0, 1.8, 0))
	Bricks.piece(body, Vector3.ZERO, Vector3(4.0, 2.8, 2.8), c, true)
	Bricks.piece(body, Vector3(0, 1.7, -0.6), Vector3(1.6, 1.0, 1.4), c.lightened(0.1), true)  # cabeça
	for sx in [-1.0, 1.0]:
		Bricks.piece(body, Vector3(0.4 * sx, 1.75, -1.32), Vector3(0.3, 0.2, 0.06), Color(1.0, 0.15, 0.1), false, true)
	_part("corpo", body, 2.2, 999, 1.0, false, c)
	var core := Bricks.joint(body, Vector3(0, 0.1, -1.45))
	Bricks.piece(core, Vector3.ZERO, Vector3(1.1, 1.1, 0.2), Color(1.0, 0.3, 0.9), false, true)
	Bricks.piece(core, Vector3(0, 0, 0.05), Vector3(1.5, 1.5, 0.15), Color(0.2, 0.2, 0.22))
	_part("nucleo", core, 0.8, 999.0, 0.3, true, Color(1.0, 0.3, 0.9))
	var pod := Bricks.joint(body, Vector3(0, 1.9, 1.0))
	Bricks.piece(pod, Vector3.ZERO, Vector3(2.4, 1.0, 1.4), Color(0.75, 0.2, 0.15), true)
	for k in 4:
		Bricks.piece(pod, Vector3(-0.8 + k * 0.53, 0.2, -0.72), Vector3(0.3, 0.3, 0.06), Color(1.0, 0.8, 0.2), false, true)
	_part("misseis", pod, 1.2, 140.0, 2.0, true, Color(0.75, 0.2, 0.15))
	for sx in [-1.0, 1.0]:
		var arm := Bricks.joint(body, Vector3(2.4 * sx, 0.3, 0))
		Bricks.piece(arm, Vector3(0, -0.6, -0.4), Vector3(0.9, 0.9, 2.2), c.darkened(0.15), true)
		Bricks.piece(arm, Vector3(0, -0.6, -1.65), Vector3(0.5, 0.5, 0.4), Color(1.0, 0.5, 0.1), false, true)
		var gun := Bricks.joint(arm, Vector3(0, -0.6, -1.7))
		_part("canhao_e" if sx < 0 else "canhao_d", gun, 0.9, 90.0, 2.0, true, Color(1.0, 0.5, 0.1))
