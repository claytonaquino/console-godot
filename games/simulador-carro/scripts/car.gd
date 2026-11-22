class_name Car
extends RigidBody3D
## Carro com física própria. O Godot cuida só do corpo rígido (gravidade,
## colisão com barreiras); suspensão, pneus, motor, câmbio, diferencial,
## freios e aerodinâmica são calculados aqui, a 240 Hz.
##
## Eixos locais: -Z é a frente, +X a direita, +Y para cima.

signal gear_changed(gear: int)

# ---------------------------------------------------------------- parâmetros
const MASS := 1250.0
const WHEEL_RADIUS := 0.32
const WHEEL_INERTIA := 1.2            # kg·m² (roda + pneu + freio)
const SUSP_REST := 0.35               # comprimento livre da mola (m)
const SUSP_MAX := 0.22                # curso máximo de compressão (m)
const SPRING_K := 32000.0             # N/m
const DAMP_BUMP := 2600.0             # N·s/m
const DAMP_REBOUND := 3600.0          # N·s/m
const ARB_FRONT := 12000.0            # barra estabilizadora (N/m)
const ARB_REAR := 7000.0
const MAX_STEER := deg_to_rad(33.0)
const BRAKE_TORQUE := 4800.0          # torque total de freio nas 4 rodas (N·m)
const BRAKE_BIAS := 0.64              # fração na dianteira
const HANDBRAKE_TORQUE := 1800.0
const CDA := 0.72                     # arrasto: Cd · área (m²)
const CLA := 0.35                     # sustentação negativa: Cl · área (m²)
const ROLLING := 0.014                # coeficiente de resistência ao rolamento
const SUBSTEPS := 10                  # subpassos da dinâmica das rodas

# Motor 2.0 aspirado: torque (N·m) por rotação (rpm)
const TORQUE_CURVE := [[800.0, 120.0], [2000.0, 165.0], [3500.0, 195.0], [4800.0, 205.0],
	[6000.0, 190.0], [7000.0, 160.0], [7400.0, 0.0]]
const IDLE_RPM := 900.0
const REDLINE := 7000.0
const ENGINE_INERTIA := 0.18
const ENGINE_BRAKE := 45.0            # N·m de freio-motor no limite de giro
const GEARS := [-3.30, 0.0, 3.50, 2.12, 1.48, 1.12, 0.92, 0.78]  # índice 0 = ré, 1 = neutro
const FINAL_DRIVE := 4.10
const DRIVETRAIN_EFF := 0.88
const LSD_LOCK := 120.0               # N·m por rad/s de diferença (diferencial autoblocante)

# ---------------------------------------------------------------- estado
## Pedais como o jogador aperta (0..1). Em ré com câmbio automático,
## o freio vira acelerador e vice-versa.
var throttle_in := 0.0
var brake_in := 0.0
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := 0.0
var auto_gearbox := true
var lsd_enabled := true
var abs_enabled := true
var gear := 2                          # índice em GEARS: 2 = 1ª marcha
var engine_rpm := IDLE_RPM
var surface_mu := [1.0, 1.0, 1.0, 1.0] # definido pela pista, por roda
var surface_roll := [1.0, 1.0, 1.0, 1.0]
var shift_timer := 0.0
var reverse_timer := 0.0
var speed := 0.0                       # m/s, positivo para a frente

## Uma entrada por roda: FL, FR, RL, RR
var wheels: Array[Dictionary] = []
var _steer := 0.0
var _visual_root: Node3D


func _ready() -> void:
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.08, 0.05)
	inertia = Vector3(2000.0, 2200.0, 520.0)
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.76, 0.55, 4.20)
	shape.shape = box
	shape.position = Vector3(0, 0.12, 0)
	add_child(shape)

	var mounts := [Vector3(-0.78, 0, -1.30), Vector3(0.78, 0, -1.30), Vector3(-0.79, 0, 1.30), Vector3(0.79, 0, 1.30)]
	for i in 4:
		wheels.append({
			"mount": mounts[i], "front": i < 2, "left": i % 2 == 0,
			"omega": 0.0, "comp": 0.0, "comp_prev": 0.0, "contact": false,
			"fz": 0.0, "fx": 0.0, "fy": 0.0, "kappa": 0.0, "alpha": 0.0,
			"mu": 1.0, "spin": 0.0, "drive": 0.0, "point": Vector3.ZERO, "normal": Vector3.UP,
		})
	_build_visual()


# ---------------------------------------------------------------- física

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	var up := xf.basis.y
	var fwd_body := -xf.basis.z
	speed = state.linear_velocity.dot(fwd_body)
	if gear == 0 and auto_gearbox:
		throttle = brake_in
		brake = throttle_in
	else:
		throttle = throttle_in
		brake = brake_in

	# Direção: menos ângulo em alta velocidade, com suavização.
	var max_angle := MAX_STEER / (1.0 + absf(speed) / 22.0)
	_steer = move_toward(_steer, steer_input * max_angle, dt * 2.6)

	_update_gearbox(dt)
	var drive := _drivetrain_torque(dt)

	# Suspensão: compressão de cada roda (raycast).
	var space := state.get_space_state()
	for i in 4:
		var w := wheels[i]
		var origin := xf * (w.mount as Vector3)
		var ray_len := SUSP_REST + WHEEL_RADIUS
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (ray_len + 0.05))
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		w.comp_prev = w.comp
		if hit.is_empty():
			w.contact = false
			w.comp = 0.0
			continue
		var dist := origin.distance_to(hit.position)
		w.contact = dist <= ray_len
		w.comp = clampf(ray_len - dist, 0.0, SUSP_MAX)
		w.point = hit.position
		w.normal = hit.normal

	# Barra estabilizadora: transfere carga entre esquerda e direita.
	var arb_f: float = (wheels[0].comp - wheels[1].comp) * ARB_FRONT
	var arb_r: float = (wheels[2].comp - wheels[3].comp) * ARB_REAR
	var arb := [arb_f, -arb_f, arb_r, -arb_r]

	for i in 4:
		var w := wheels[i]
		var steer_angle: float = _steer if w.front else 0.0
		var t_drive: float = 0.0 if w.front else (drive.x if w.left else drive.y)
		w.drive = t_drive
		var t_brake: float = brake * BRAKE_TORQUE * 0.5 * (BRAKE_BIAS if w.front else (1.0 - BRAKE_BIAS))
		if not w.front:
			t_brake += handbrake * HANDBRAKE_TORQUE
		if not w.contact:
			# Roda no ar: só torque de motor e freio.
			w.omega += (t_drive / WHEEL_INERTIA) * dt
			w.omega = move_toward(w.omega, 0.0, t_brake / WHEEL_INERTIA * dt)
			w.fz = 0.0
			w.fx = 0.0
			w.fy = 0.0
			continue

		var comp_vel: float = (w.comp - w.comp_prev) / dt
		var damp := DAMP_BUMP if comp_vel > 0.0 else DAMP_REBOUND
		var fz: float = maxf(0.0, SPRING_K * w.comp + damp * comp_vel + arb[i])
		# Batente: evita que a mola chegue ao fim do curso sem resistência.
		if w.comp > SUSP_MAX * 0.9:
			fz += (w.comp - SUSP_MAX * 0.9) * SPRING_K * 8.0
		w.fz = fz

		var n: Vector3 = w.normal
		var wheel_fwd := fwd_body.rotated(up, -steer_angle)
		wheel_fwd = (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var wheel_right := wheel_fwd.cross(n).normalized()
		var r_world: Vector3 = w.point - xf.origin
		var v := state.get_velocity_at_local_position(r_world)
		var vx := v.dot(wheel_fwd)
		var vy := v.dot(wheel_right)
		var denom := maxf(absf(vx), 3.0)
		var mu: float = surface_mu[i]
		var t_roll: float = ROLLING * surface_roll[i] * fz * WHEEL_RADIUS

		# Dinâmica da roda em subpassos (a rotação da roda é rígida demais
		# para o passo da física; com 10 subpassos fica estável).
		var sdt := dt / SUBSTEPS
		var fx_sum := 0.0
		var fy_sum := 0.0
		var omega: float = w.omega
		var kappa := 0.0
		for s in SUBSTEPS:
			kappa = (omega * WHEEL_RADIUS - vx) / denom
			var f := Tire.forces(kappa, vy / denom, fz, mu)
			fx_sum += f.x
			fy_sum += -f.y
			omega += (t_drive - f.x * WHEEL_RADIUS) / WHEEL_INERTIA * sdt
			# ABS: alivia o freio quando a roda começa a travar.
			var tb := t_brake
			if abs_enabled and absf(vx) > 2.0:
				var slip := -kappa * signf(vx)
				tb *= clampf((0.16 - slip) / 0.06, 0.0, 1.0)
			# Freio e rolamento só reduzem a rotação (nunca invertem).
			omega = move_toward(omega, 0.0, (tb + t_roll) / WHEEL_INERTIA * sdt)
		w.omega = omega
		w.fx = fx_sum / SUBSTEPS
		w.fy = fy_sum / SUBSTEPS
		w.kappa = kappa
		w.alpha = atan2(vy, absf(vx) + 0.5)
		w.mu = mu

		var force: Vector3 = wheel_fwd * w.fx + wheel_right * w.fy + n * fz
		state.apply_force(force, r_world)

	# Aerodinâmica
	var vel := state.linear_velocity
	var v2 := vel.length_squared()
	if v2 > 0.01:
		state.apply_central_force(-vel.normalized() * 0.5 * 1.225 * CDA * v2)
		state.apply_central_force(-up * 0.5 * 1.225 * CLA * speed * speed)

	# Parado, sem acelerar: segura o carro (evita deslizar devagar).
	if throttle < 0.05 and state.linear_velocity.length() < 0.4:
		state.linear_velocity = state.linear_velocity * 0.9


func _engine_torque(rpm: float) -> float:
	var curve: Array = TORQUE_CURVE
	if rpm <= curve[0][0]:
		return curve[0][1]
	for i in range(1, curve.size()):
		if rpm <= curve[i][0]:
			var a: Array = curve[i - 1]
			var b: Array = curve[i]
			return lerpf(a[1], b[1], (rpm - a[0]) / (b[0] - a[0]))
	return 0.0


## Torque nas rodas traseiras (Vector2: esquerda, direita), tração traseira.
func _drivetrain_torque(dt: float) -> Vector2:
	var ratio: float = GEARS[gear] * FINAL_DRIVE
	var w_l: float = wheels[2].omega
	var w_r: float = wheels[3].omega
	var w_avg := (w_l + w_r) * 0.5
	var pedal := throttle
	var wheel_rpm := absf(w_avg * ratio) * 60.0 / TAU

	if ratio == 0.0:
		# Neutro: motor livre.
		var target := IDLE_RPM + pedal * (REDLINE - IDLE_RPM)
		engine_rpm = move_toward(engine_rpm, target, dt * 9000.0)
		return Vector2.ZERO

	# Embreagem automática: patina abaixo de ~1300 rpm de roda.
	# Embreagem só patina na saída (1ª e ré) ou quase parando.
	var clutch_rpm := IDLE_RPM + 400.0 + pedal * 1800.0
	var launch_gear := gear <= 2
	var slipping := pedal > 0.02 and ((launch_gear and wheel_rpm < clutch_rpm) or wheel_rpm < IDLE_RPM)
	if slipping:
		engine_rpm = move_toward(engine_rpm, clutch_rpm, dt * 6000.0)
	else:
		engine_rpm = maxf(wheel_rpm, IDLE_RPM)

	var t_engine := 0.0
	if engine_rpm >= REDLINE + 150.0:
		t_engine = -ENGINE_BRAKE  # corte de giro
	elif pedal > 0.02:
		t_engine = _engine_torque(engine_rpm) * pedal
	else:
		t_engine = -ENGINE_BRAKE * clampf(engine_rpm / REDLINE, 0.1, 1.0)
		if wheel_rpm < IDLE_RPM + 100.0:
			t_engine = 0.0  # embreagem abre perto da marcha lenta

	var t_wheels := t_engine * ratio * DRIVETRAIN_EFF
	if slipping:
		# Embreagem patinando transmite torque mas limita o choque.
		t_wheels *= clampf(wheel_rpm / clutch_rpm, 0.6, 1.0)

	var bias := 0.0
	if lsd_enabled:
		bias = clampf((w_l - w_r) * LSD_LOCK, -absf(t_wheels) * 0.35 - 150.0, absf(t_wheels) * 0.35 + 150.0)
	return Vector2(t_wheels * 0.5 - bias, t_wheels * 0.5 + bias)


func _update_gearbox(dt: float) -> void:
	shift_timer = maxf(0.0, shift_timer - dt)
	if not auto_gearbox:
		return
	if shift_timer > 0.0:
		return
	# Ré automática: parado, segurando o freio.
	if gear >= 2 and speed < 0.5 and brake_in > 0.6 and throttle_in < 0.05:
		reverse_timer += dt
		if reverse_timer > 0.6:
			set_gear(0)
		return
	reverse_timer = 0.0
	if gear == 0:
		if throttle_in > 0.1 and speed > -0.5:
			set_gear(2)
		return
	if gear >= 2:
		if engine_rpm > 6700.0 and gear < GEARS.size() - 1:
			set_gear(gear + 1)
		elif engine_rpm < 2600.0 and gear > 2:
			# Só reduz se a marcha de baixo não estourar o giro.
			var w_avg: float = (wheels[2].omega + wheels[3].omega) * 0.5
			var next_rpm: float = absf(w_avg * GEARS[gear - 1] * FINAL_DRIVE) * 60.0 / TAU
			if next_rpm < 6200.0:
				set_gear(gear - 1)


func set_gear(g: int) -> void:
	g = clampi(g, 0, GEARS.size() - 1)
	if g == gear:
		return
	gear = g
	shift_timer = 0.35
	reverse_timer = 0.0
	gear_changed.emit(gear)


func shift_up() -> void:
	if gear == 0:
		set_gear(1)
	else:
		set_gear(gear + 1)


func shift_down() -> void:
	set_gear(gear - 1)


func gear_label() -> String:
	if gear == 0:
		return "R"
	if gear == 1:
		return "N"
	return str(gear - 1)


func speed_kmh() -> float:
	return absf(speed) * 3.6


## Recoloca o carro parado numa posição e direção.
func reset_to(pos: Vector3, forward: Vector3) -> void:
	var basis := Basis.looking_at(forward.normalized(), Vector3.UP)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, pos))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(basis, pos)
	for w in wheels:
		w.omega = 0.0
		w.comp = 0.0
		w.comp_prev = 0.0
	gear = 2
	engine_rpm = IDLE_RPM


# ---------------------------------------------------------------- visual

var _wheel_nodes: Array[Node3D] = []


func _mat(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


## Extruda um perfil (z, y) com meia-largura w, centrado em x = 0.
func _extrude(poly: Array, w: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p2 := PackedVector2Array(poly)
	var tris := Geometry2D.triangulate_polygon(p2)
	for side in [-1.0, 1.0]:
		var order := range(tris.size()) if side > 0 else range(tris.size() - 1, -1, -1)
		for k in order:
			var v: Vector2 = p2[tris[k]]
			st.add_vertex(Vector3(w * side, v.y, v.x))
	for i in p2.size():
		var a: Vector2 = p2[i]
		var b: Vector2 = p2[(i + 1) % p2.size()]
		var qa := Vector3(-w, a.y, a.x)
		var qb := Vector3(-w, b.y, b.x)
		var ra := Vector3(w, a.y, a.x)
		var rb := Vector3(w, b.y, b.x)
		for v in [qa, qb, ra, ra, qb, rb]:
			st.add_vertex(v)
	st.generate_normals()
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_visual_root.add_child(mi)
	return mi


func _build_visual() -> void:
	_visual_root = Node3D.new()
	add_child(_visual_root)
	var paint := _mat(Color(0.85, 0.22, 0.12), 0.35, 0.3)
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := _mat(Color(0.08, 0.1, 0.14), 0.1, 0.6)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := _mat(Color(0.06, 0.06, 0.06), 0.8)
	var light_f := _mat(Color(1, 0.97, 0.85))
	light_f.emission_enabled = true
	light_f.emission = Color(1, 0.95, 0.8)
	var light_r := _mat(Color(0.8, 0.05, 0.05))
	light_r.emission_enabled = true
	light_r.emission = Color(0.6, 0.0, 0.0)

	# Carroceria: perfil lateral extrudado (capô inclinado, traseira mais alta).
	_extrude([Vector2(-2.08, -0.22), Vector2(2.08, -0.22), Vector2(2.08, 0.14), Vector2(1.96, 0.36),
		Vector2(-1.85, 0.30), Vector2(-2.08, 0.12)], 0.88, paint)
	# Cabine e teto ficam na camada 2, escondida na câmera de cockpit.
	_extrude([Vector2(-0.62, 0.30), Vector2(1.70, 0.35), Vector2(1.22, 0.72), Vector2(0.06, 0.74)], 0.74, glass).layers = 2
	_box(Vector3(1.42, 0.05, 1.12), Vector3(0, 0.75, 0.64), paint, _visual_root).layers = 2
	# Para-lamas escuros sobre as rodas
	for m in [Vector3(-0.80, 0.05, -1.30), Vector3(0.80, 0.05, -1.30), Vector3(-0.81, 0.05, 1.30), Vector3(0.81, 0.05, 1.30)]:
		_box(Vector3(0.18, 0.12, 0.86), m + Vector3(0, 0.08, 0), dark, _visual_root)
	_box(Vector3(1.40, 0.10, 0.25), Vector3(0, 0.27, -0.78), dark, _visual_root)     # painel
	_box(Vector3(1.78, 0.14, 0.25), Vector3(0, -0.12, -2.05), dark, _visual_root)   # para-choque
	_box(Vector3(1.78, 0.14, 0.25), Vector3(0, -0.12, 2.05), dark, _visual_root)
	_box(Vector3(1.6, 0.06, 0.25), Vector3(0, 0.38, 1.95), dark, _visual_root)      # aerofólio
	for x in [-0.62, 0.62]:
		_box(Vector3(0.32, 0.10, 0.05), Vector3(x, 0.1, -2.08), light_f, _visual_root)
		_box(Vector3(0.32, 0.10, 0.05), Vector3(x, 0.1, 2.08), light_r, _visual_root)

	var tire_mat := _mat(Color(0.05, 0.05, 0.05), 0.95)
	var rim_mat := _mat(Color(0.7, 0.72, 0.75), 0.3, 0.8)
	for w in wheels:
		var pivot := Node3D.new()
		_visual_root.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var tire := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = WHEEL_RADIUS
		cyl.bottom_radius = WHEEL_RADIUS
		cyl.height = 0.24
		cyl.radial_segments = 18
		cyl.material = tire_mat
		tire.mesh = cyl
		tire.rotation.z = PI / 2
		spin.add_child(tire)
		var rim := MeshInstance3D.new()
		var rcyl := CylinderMesh.new()
		rcyl.top_radius = WHEEL_RADIUS * 0.62
		rcyl.bottom_radius = WHEEL_RADIUS * 0.62
		rcyl.height = 0.25
		rcyl.radial_segments = 6  # seis "raios" visíveis
		rcyl.material = rim_mat
		rim.mesh = rcyl
		rim.rotation.z = PI / 2
		spin.add_child(rim)
		_wheel_nodes.append(pivot)


func _process(delta: float) -> void:
	# Posição visual das rodas (suspensão, direção e giro).
	for i in 4:
		var w := wheels[i]
		var pivot := _wheel_nodes[i]
		var drop: float = SUSP_REST - (w.comp as float)
		var target := (w.mount as Vector3) + Vector3(0, -drop, 0)
		pivot.position = pivot.position.lerp(target, clampf(delta * 30.0, 0.0, 1.0))
		pivot.rotation.y = -_steer if w.front else 0.0
		var spin := pivot.get_child(0) as Node3D
		spin.rotation.x -= (w.omega as float) * delta
