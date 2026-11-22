class_name Hero
extends CharacterBody3D
## Heroína/herói de blocos. Iara: arco, chuva de flechas, flecha de gelo.
## Bento: lança em combo, onda de choque, escudo.
## Animação em "stop motion": a pose só muda 12 vezes por segundo.

signal downed(hero: Hero)

const STOP_MOTION_FPS := 12.0
const ROLL_TIME := 0.32
const ROLL_SPEED := 17.0
const INVULN_TIME := 1.0

var kind := "iara"
var display_name := "Iara"
var world: Node            # Main (consultas de inimigos, projéteis, efeitos)
var player_index := 0
var active := true

var max_hearts := 5
var hearts := 5
var damage_mult := 1.0
var cooldown_mult := 1.0
var speed := 6.0

var special_cd := 0.0
var special_max := 8.0
var alt_cd := 0.0
var alt_max := 6.0
var attack_cd := 0.0
var roll_cd := 0.0
var roll_t := 0.0
var roll_dir := Vector3.ZERO
var invuln := 0.0
var shield_t := 0.0
var down := false
var down_t := 0.0
var revive_progress := 0.0
var combo := 0
var combo_t := 0.0
var facing := Vector3(0, 0, 1)

# Entrada vinda do Main
var in_move := Vector2.ZERO
var in_attack := false
var in_special := false
var in_alt := false
var in_dodge := false

var _model: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _torso: Node3D
var _weapon: Node3D
var _shield_vis: MeshInstance3D
var _anim_t := 0.0
var _anim_acc := 0.0
var _pose := "idle"
var _pose_t := 0.0
var _blink := 0.0


func setup(k: String, w: Node, index: int) -> void:
	kind = k
	world = w
	player_index = index
	if kind == "iara":
		display_name = "Iara"
		speed = 6.2
		special_max = 8.0
		alt_max = 6.0
	else:
		display_name = "Bento"
		speed = 5.6
		special_max = 8.0
		alt_max = 7.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.9
	shape.shape = cap
	shape.position.y = 0.95
	add_child(shape)
	_build_model()


func apply_upgrades(save: Dictionary) -> void:
	max_hearts = 5 + int(save.get("up_hearts", 0))
	damage_mult = 1.0 + 0.2 * int(save.get("up_damage", 0))
	cooldown_mult = 1.0 - 0.12 * int(save.get("up_cooldown", 0))
	hearts = max_hearts


# ---------------------------------------------------------------- modelo

func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var skin := Color(0.96, 0.78, 0.6)
	var shirt := Color(0.85, 0.35, 0.15) if kind == "iara" else Color(0.15, 0.38, 0.75)
	var pants := Color(0.35, 0.25, 0.18) if kind == "iara" else Color(0.25, 0.25, 0.3)
	var hair := Color(0.75, 0.22, 0.08) if kind == "iara" else Color(0.55, 0.57, 0.6)

	for side in [-1.0, 1.0]:
		var hip := Bricks.joint(_model, Vector3(0.19 * side, 0.78, 0))
		Bricks.piece(hip, Vector3(0, -0.36, 0), Vector3(0.32, 0.72, 0.36), pants)
		Bricks.piece(hip, Vector3(0, -0.72, -0.06), Vector3(0.34, 0.12, 0.48), Color(0.2, 0.15, 0.1))
		_legs.append(hip)
	_torso = Bricks.joint(_model, Vector3(0, 0.78, 0))
	Bricks.piece(_torso, Vector3(0, 0.38, 0), Vector3(0.82, 0.74, 0.46), shirt)
	Bricks.piece(_torso, Vector3(0, 0.03, 0), Vector3(0.84, 0.12, 0.48), Color(0.3, 0.2, 0.12))  # cinto
	for side in [-1.0, 1.0]:
		var sh := Bricks.joint(_torso, Vector3(0.52 * side, 0.66, 0))
		Bricks.piece(sh, Vector3(0, -0.28, 0), Vector3(0.24, 0.62, 0.28), shirt)
		Bricks.piece(sh, Vector3(0, -0.64, 0), Vector3(0.26, 0.16, 0.26), skin)
		_arms.append(sh)
	var head := Bricks.joint(_torso, Vector3(0, 0.78, 0))
	Bricks.piece(head, Vector3(0, 0.28, 0), Vector3(0.52, 0.52, 0.5), skin, true)
	for side in [-1.0, 1.0]:
		Bricks.piece(head, Vector3(0.12 * side, 0.32, 0.26), Vector3(0.08, 0.1, 0.02), Color(0.05, 0.05, 0.05))
	Bricks.piece(head, Vector3(0, 0.17, 0.26), Vector3(0.16, 0.04, 0.02), Color(0.45, 0.15, 0.1))  # sorriso
	if kind == "iara":
		Bricks.piece(head, Vector3(0, 0.58, -0.04), Vector3(0.58, 0.16, 0.58), hair)
		Bricks.piece(head, Vector3(0, 0.36, -0.28), Vector3(0.54, 0.36, 0.1), hair)
		Bricks.piece(head, Vector3(0, 0.0, -0.36), Vector3(0.16, 0.5, 0.14), hair)  # trança
		# Arco na mão esquerda
		_weapon = Bricks.joint(_arms[0], Vector3(0, -0.66, 0.1))
		Bricks.piece(_weapon, Vector3(0, 0.4, 0.1), Vector3(0.06, 0.5, 0.06), Color(0.45, 0.28, 0.12))
		Bricks.piece(_weapon, Vector3(0, -0.2, 0.1), Vector3(0.06, 0.5, 0.06), Color(0.45, 0.28, 0.12))
		Bricks.piece(_weapon, Vector3(0, 0.1, 0.02), Vector3(0.02, 1.1, 0.02), Color(0.9, 0.9, 0.85))
		Bricks.piece(_weapon, Vector3(0, 0.65, 0.18), Vector3(0.08, 0.12, 0.08), Color(0.2, 0.8, 1.0), false, true)
	else:
		Bricks.piece(head, Vector3(0, 0.6, 0), Vector3(0.6, 0.2, 0.58), hair, true)  # capacete
		Bricks.piece(head, Vector3(0, 0.78, 0), Vector3(0.1, 0.18, 0.4), Color(0.85, 0.15, 0.1))  # crista
		# Lança na mão direita
		_weapon = Bricks.joint(_arms[1], Vector3(0, -0.66, 0))
		Bricks.piece(_weapon, Vector3(0, 0, 0.4), Vector3(0.08, 0.08, 2.0), Color(0.4, 0.28, 0.15))
		Bricks.piece(_weapon, Vector3(0, 0, 1.5), Vector3(0.18, 0.06, 0.35), Color(0.3, 0.85, 1.0), false, true)
		_shield_vis = Bricks.piece(_model, Vector3(0, 1.1, 0.75), Vector3(1.2, 1.4, 0.08), Color(0.3, 0.8, 1.0), false, true)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.3, 0.8, 1.0, 0.35)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.emission_enabled = true
		sm.emission = Color(0.2, 0.6, 1.0)
		_shield_vis.material_override = sm
		_shield_vis.visible = false


# ---------------------------------------------------------------- lógica

func _physics_process(delta: float) -> void:
	if not active:
		return
	_tick(delta)


func _tick(delta: float) -> void:
	special_cd = maxf(0.0, special_cd - delta)
	alt_cd = maxf(0.0, alt_cd - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	shield_t = maxf(0.0, shield_t - delta)
	combo_t = maxf(0.0, combo_t - delta)
	_pose_t = maxf(0.0, _pose_t - delta)
	if _shield_vis:
		_shield_vis.visible = shield_t > 0.0

	if down:
		down_t += delta
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var move := Vector3(in_move.x, 0, in_move.y)
	# A câmera é isométrica (girada 45°): ajusta o analógico para a tela.
	move = move.rotated(Vector3.UP, deg_to_rad(-45.0))
	if move.length() > 1.0:
		move = move.normalized()

	if roll_t > 0.0:
		roll_t -= delta
		velocity = roll_dir * ROLL_SPEED * (0.4 + roll_t / ROLL_TIME)
		move_and_slide()
		return

	if in_dodge and roll_cd <= 0.0:
		roll_dir = move.normalized() if move.length() > 0.2 else facing
		roll_t = ROLL_TIME
		roll_cd = 0.75
		invuln = maxf(invuln, ROLL_TIME + 0.05)
		_set_pose("roll", ROLL_TIME)
		world.sfx.play("roll")
		return

	var spd := speed * (0.45 if _pose_t > 0.0 and _pose in ["shoot", "thrust", "slam"] else 1.0)
	velocity = Vector3(move.x * spd, velocity.y - 30.0 * delta, move.z * spd)
	if is_on_floor():
		velocity.y = -1.0
	if move.length() > 0.15:
		facing = facing.lerp(move.normalized(), clampf(delta * 14.0, 0.0, 1.0)).normalized()
	move_and_slide()

	if in_attack and attack_cd <= 0.0:
		_attack()
	if in_special and special_cd <= 0.0:
		_special()
	if in_alt and alt_cd <= 0.0:
		_alt()


func _aim(max_range: float) -> Vector3:
	var target: Variant = world.nearest_enemy(global_position, max_range, facing, -0.1)
	if target != null:
		var p: Vector3 = target
		var d := p - global_position
		d.y = 0
		if d.length() > 0.1:
			facing = d.normalized()
	return facing


func _attack() -> void:
	if kind == "iara":
		var dir := _aim(16.0)
		attack_cd = 0.36
		world.spawn_arrow(self, global_position + Vector3(0, 1.25, 0) + dir * 0.6, dir, 11.0 * damage_mult, false)
		_set_pose("shoot", 0.25)
		world.sfx.play("shoot")
	else:
		_aim(3.5)
		combo = (combo + 1) % 3 if combo_t > 0.0 else 0
		combo_t = 0.7
		attack_cd = 0.3 if combo < 2 else 0.5
		var dmg := (14.0 if combo < 2 else 24.0) * damage_mult
		world.melee(self, global_position + facing * 1.4 + Vector3(0, 1.0, 0), 1.9, dmg, combo == 2)
		_set_pose("thrust" if combo < 2 else "slam", 0.25)
		world.sfx.play("swing")


func _special() -> void:
	special_cd = special_max * cooldown_mult
	if kind == "iara":
		var dir := _aim(18.0)
		var target: Variant = world.nearest_enemy(global_position, 18.0, facing, 0.2)
		var center: Vector3 = target if target != null else global_position + dir * 7.0
		center.y = 0
		world.arrow_rain(self, center, 4.0, 26.0 * damage_mult)
		_set_pose("shoot", 0.4)
		world.sfx.play("shoot")
	else:
		world.shockwave(self, global_position, 5.5, 30.0 * damage_mult)
		_set_pose("slam", 0.4)
		world.sfx.play("boom")


func _alt() -> void:
	alt_cd = alt_max * cooldown_mult
	if kind == "iara":
		var dir := _aim(16.0)
		world.spawn_arrow(self, global_position + Vector3(0, 1.25, 0) + dir * 0.6, dir, 6.0 * damage_mult, true)
		_set_pose("shoot", 0.25)
		world.sfx.play("freeze")
	else:
		shield_t = 2.5
		world.sfx.play("freeze", 0.0)


## Dano vindo de inimigos (em corações).
func hurt(amount: int, from: Vector3) -> void:
	if down or invuln > 0.0 or not active:
		return
	if shield_t > 0.0:
		var to_src := (from - global_position)
		to_src.y = 0
		if to_src.normalized().dot(facing) > 0.1:
			world.fx.popup(global_position + Vector3(0, 2.2, 0), "Bloqueou!", Color(0.5, 0.9, 1.0))
			return
	hearts = maxi(0, hearts - amount)
	invuln = INVULN_TIME
	world.sfx.play("hurt")
	world.fx.debris(global_position + Vector3(0, 1.2, 0), Color(1, 0.3, 0.3), 4, 3.0)
	var push := global_position - from
	push.y = 0
	if push.length() > 0.01:
		velocity = push.normalized() * 8.0
	if hearts <= 0:
		down = true
		down_t = 0.0
		revive_progress = 0.0
		_set_pose("down", 999.0)
		downed.emit(self)


func revive(full := false) -> void:
	down = false
	hearts = max_hearts if full else maxi(2, max_hearts / 2)
	invuln = 2.0
	_pose_t = 0.0
	_pose = "idle"


func _set_pose(p: String, t: float) -> void:
	_pose = p
	_pose_t = t
	_anim_acc = 1.0  # força atualização imediata


# ---------------------------------------------------------------- animação

func _process(delta: float) -> void:
	_anim_t += delta
	_anim_acc += delta
	_blink = invuln
	if invuln > 0.0 and not down:
		_model.visible = fmod(invuln, 0.2) > 0.08
	else:
		_model.visible = true
	if _anim_acc < 1.0 / STOP_MOTION_FPS:
		return
	_anim_acc = 0.0
	# Direção do corpo
	_model.basis = Basis.looking_at(-facing, Vector3.UP) if facing.length() > 0.1 else _model.basis
	var t := floorf(_anim_t * STOP_MOTION_FPS) / STOP_MOTION_FPS
	var moving := Vector2(velocity.x, velocity.z).length() > 0.8
	_model.rotation.x = 0.0
	_model.position = Vector3.ZERO
	var swing := sin(t * 11.0) * 0.6 if moving else 0.0
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation = Vector3(-swing * 0.8, 0, 0)
	_arms[1].rotation = Vector3(swing * 0.8, 0, 0)
	_torso.rotation = Vector3(0, 0, 0)
	_model.position.y = absf(sin(t * 11.0)) * 0.08 if moving else sin(t * 3.0) * 0.02
	if _pose_t > 0.0:
		match _pose:
			"shoot":
				_arms[0].rotation = Vector3(-1.5, 0, 0)
				_arms[1].rotation = Vector3(-1.4, 0.4, 0)
			"thrust":
				_arms[1].rotation = Vector3(-1.5, 0, 0)
				_torso.rotation.y = -0.3
			"slam":
				_arms[0].rotation = Vector3(-2.6, 0, 0)
				_arms[1].rotation = Vector3(-2.6, 0, 0)
				_torso.rotation.x = 0.2
			"roll":
				_model.rotation.x = -TAU * (1.0 - roll_t / ROLL_TIME)
				_model.position.y = 0.5
			"down":
				_model.rotation.x = -PI / 2.0
				_model.position.y = 0.3
	if down:
		_model.rotation.x = -PI / 2.0
		_model.position.y = 0.3
