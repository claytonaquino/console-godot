extends Node3D
## Ilha de Teste: mundo 3D gerado por código (terreno, água, árvores,
## pedras, céu e sol) com um jogador em primeira pessoa.
## Serve para testar o console, os controles e o desempenho da placa de vídeo.
##
## Controle: analógico esquerdo anda, direito olha, A pula, B/L3 corre,
##           Y qualidade, X hora do dia, Select sai.
## Teclado:  WASD + mouse, Espaço pula, Shift corre, Q qualidade, T hora, Esc sai.

const WORLD_SIZE := 320.0
const GRID := 160
const SEA_LEVEL := 0.0
const TREE_COUNT := 900
const ROCK_COUNT := 140

const QUALITY := [
	{"name": "Baixa", "shadows": false, "shadow_size": 1024, "scale": 0.6, "msaa": Viewport.MSAA_DISABLED, "trees": 300},
	{"name": "Média", "shadows": true, "shadow_size": 2048, "scale": 0.8, "msaa": Viewport.MSAA_DISABLED, "trees": 600},
	{"name": "Alta", "shadows": true, "shadow_size": 4096, "scale": 1.0, "msaa": Viewport.MSAA_2X, "trees": TREE_COUNT},
]

const TIMES := [
	{"name": "Manhã", "pitch": -22.0, "yaw": 60.0, "color": Color(1.0, 0.88, 0.74), "energy": 0.95,
		"top": Color(0.30, 0.52, 0.85), "horizon": Color(0.80, 0.82, 0.86), "ambient": 0.65, "fog": Color(0.75, 0.80, 0.88)},
	{"name": "Meio-dia", "pitch": -62.0, "yaw": 20.0, "color": Color(1.0, 0.98, 0.94), "energy": 1.15,
		"top": Color(0.22, 0.45, 0.85), "horizon": Color(0.68, 0.78, 0.90), "ambient": 0.75, "fog": Color(0.70, 0.80, 0.92)},
	{"name": "Pôr do sol", "pitch": -7.0, "yaw": -110.0, "color": Color(1.0, 0.55, 0.30), "energy": 0.8,
		"top": Color(0.20, 0.25, 0.50), "horizon": Color(0.98, 0.58, 0.35), "ambient": 0.45, "fog": Color(0.85, 0.55, 0.40)},
	{"name": "Noite", "pitch": -40.0, "yaw": 150.0, "color": Color(0.55, 0.65, 1.0), "energy": 0.18,
		"top": Color(0.01, 0.02, 0.06), "horizon": Color(0.05, 0.08, 0.16), "ambient": 0.18, "fog": Color(0.04, 0.06, 0.12)},
]

var heights := PackedFloat32Array()
var cell := WORLD_SIZE / GRID
var quality := 1
var time_index := 0

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var trees_trunk: MultiMeshInstance3D
var trees_top: MultiMeshInstance3D
var player: CharacterBody3D
var cam: Camera3D
var hud: Label
var hint: Label

var _fps_samples: Array[float] = []
var _hud_timer := 0.0
var _auto_checks := 0
var _auto_timer := 4.0
var _pitch := 0.0
var _vel_y := 0.0


func _ready() -> void:
	_setup_input()
	_make_heights()
	_make_environment()
	_make_terrain()
	_make_water()
	_make_trees()
	_make_rocks()
	_make_player()
	_make_hud()
	if OS.get_environment("ILHA_QUALITY").is_valid_int():
		quality = clampi(int(OS.get_environment("ILHA_QUALITY")), 0, 2)
		_auto_checks = 99
	_apply_quality()
	_apply_time()
	if OS.get_environment("ILHA_SELFTEST") != "":
		_selftest.call_deferred(OS.get_environment("ILHA_SELFTEST"))


# ---------------------------------------------------------------- terreno

func _make_heights() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 2026
	noise.frequency = 0.0075
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.5
	var ridges := FastNoiseLite.new()
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridges.seed = 7
	ridges.frequency = 0.012
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3
	heights.resize((GRID + 1) * (GRID + 1))
	var half := WORLD_SIZE * 0.5
	for z in GRID + 1:
		for x in GRID + 1:
			var wx := x * cell - half
			var wz := z * cell - half
			var d := Vector2(wx, wz).length() / half
			var n := noise.get_noise_2d(wx, wz) * 0.5 + 0.5
			var r := maxf(0.0, ridges.get_noise_2d(wx, wz))
			var land := n * 26.0 + r * r * 22.0 * smoothstep(0.75, 0.2, d)
			var mask := smoothstep(1.0, 0.45, d)
			heights[z * (GRID + 1) + x] = lerpf(-9.0, land + 1.5, mask)


func height_at(wx: float, wz: float) -> float:
	var half := WORLD_SIZE * 0.5
	var gx := clampf((wx + half) / cell, 0.0, GRID - 0.001)
	var gz := clampf((wz + half) / cell, 0.0, GRID - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var w := GRID + 1
	var h00 := heights[z0 * w + x0]
	var h10 := heights[z0 * w + x0 + 1]
	var h01 := heights[(z0 + 1) * w + x0]
	var h11 := heights[(z0 + 1) * w + x0 + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func _normal_at_grid(x: int, z: int) -> Vector3:
	var w := GRID + 1
	var hl := heights[z * w + maxi(x - 1, 0)]
	var hr := heights[z * w + mini(x + 1, GRID)]
	var hd := heights[maxi(z - 1, 0) * w + x]
	var hu := heights[mini(z + 1, GRID) * w + x]
	return Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()


func _terrain_color(h: float, slope: float, x: int, z: int) -> Color:
	var jitter := (sin(x * 12.9898 + z * 78.233) * 43758.5453)
	jitter = (jitter - floorf(jitter)) * 0.06 - 0.03
	var sand := Color(0.80, 0.74, 0.56)
	var grass := Color(0.27, 0.47, 0.19).lerp(Color(0.38, 0.52, 0.22), clampf(h / 20.0, 0.0, 1.0))
	var rock := Color(0.46, 0.43, 0.39)
	var snow := Color(0.92, 0.93, 0.95)
	var c := sand.lerp(grass, smoothstep(0.8, 2.6, h))
	c = c.lerp(rock, smoothstep(0.35, 0.6, slope))
	c = c.lerp(snow, smoothstep(30.0, 36.0, h) * (1.0 - smoothstep(0.45, 0.7, slope)))
	if h < SEA_LEVEL - 0.5:
		c = sand.darkened(0.35)
	return Color(c.r + jitter, c.g + jitter, c.b + jitter)


func _make_terrain() -> void:
	var w := GRID + 1
	var half := WORLD_SIZE * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	for z in w:
		for x in w:
			var i := z * w + x
			var h := heights[i]
			var n := _normal_at_grid(x, z)
			verts[i] = Vector3(x * cell - half, h, z * cell - half)
			normals[i] = n
			colors[i] = _terrain_color(h, 1.0 - n.y, x, z)
	for z in GRID:
		for x in GRID:
			var i := z * w + x
			indices.append_array([i, i + 1, i + w, i + 1, i + w + 1, i + w])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600, 1600)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.33, 0.45, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.06
	mat.metallic = 0.25
	mat.metallic_specular = 0.8
	plane.material = mat
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position.y = SEA_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _slope_at(wx: float, wz: float) -> float:
	var e := 1.0
	var dx := height_at(wx + e, wz) - height_at(wx - e, wz)
	var dz := height_at(wx, wz + e) - height_at(wx, wz - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized().y


func _make_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var xforms: Array[Transform3D] = []
	var half := WORLD_SIZE * 0.5 - 4.0
	var tries := 0
	while xforms.size() < TREE_COUNT and tries < TREE_COUNT * 20:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := height_at(x, z)
		if h < 2.2 or h > 27.0 or _slope_at(x, z) < 0.82:
			continue
		var s := rng.randf_range(0.75, 1.45)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
		xforms.append(Transform3D(basis, Vector3(x, h - 0.2, z)))
	# Embaralha para que "visible_instance_count" (qualidade) pegue árvores espalhadas.
	for i in range(xforms.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := xforms[i]
		xforms[i] = xforms[j]
		xforms[j] = tmp

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.24
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.25, 0.16)
	trunk_mat.roughness = 1.0
	trunk.material = trunk_mat

	var top := CylinderMesh.new()
	top.top_radius = 0.0
	top.bottom_radius = 1.7
	top.height = 5.0
	top.radial_segments = 7
	top.rings = 2
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color.WHITE
	top_mat.vertex_color_use_as_albedo = true
	top_mat.roughness = 0.95
	top.material = top_mat

	trees_trunk = _multimesh(trunk, xforms, Vector3(0, 1.5, 0), false, rng)
	trees_top = _multimesh(top, xforms, Vector3(0, 4.6, 0), true, rng)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], offset: Vector3, tint: bool, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tint
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var t := xforms[i]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin + t.basis * offset))
		if tint:
			mm.set_instance_color(i, Color(0.13, 0.33, 0.16).lerp(Color(0.22, 0.42, 0.18), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


func _make_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.48, 0.45)
	mat.roughness = 1.0
	rock.material = mat
	var xforms: Array[Transform3D] = []
	var half := WORLD_SIZE * 0.5 - 4.0
	while xforms.size() < ROCK_COUNT:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := height_at(x, z)
		if h < -1.0:
			continue
		var s := Vector3(rng.randf_range(0.6, 2.6), rng.randf_range(0.4, 1.4), rng.randf_range(0.6, 2.6))
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(s), Vector3(x, h, z)))
	_multimesh(rock, xforms, Vector3.ZERO, false, rng)


# ---------------------------------------------------------------- luz e céu

func _make_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.ground_bottom_color = Color(0.10, 0.12, 0.14)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.05
	add_child(sun)


func _apply_time() -> void:
	var t: Dictionary = TIMES[time_index]
	sun.rotation_degrees = Vector3(t.pitch, t.yaw, 0.0)
	sun.light_color = t.color
	sun.light_energy = t.energy
	sky_mat.sky_top_color = t.top
	sky_mat.sky_horizon_color = t.horizon
	sky_mat.ground_horizon_color = t.horizon.darkened(0.2)
	env.ambient_light_energy = t.ambient
	env.fog_light_color = t.fog


func _apply_quality() -> void:
	var q: Dictionary = QUALITY[quality]
	sun.shadow_enabled = q.shadows
	RenderingServer.directional_shadow_atlas_set_size(q.shadow_size, true)
	get_viewport().scaling_3d_scale = q.scale
	get_viewport().msaa_3d = q.msaa
	trees_trunk.multimesh.visible_instance_count = mini(q.trees, trees_trunk.multimesh.instance_count)
	trees_top.multimesh.visible_instance_count = mini(q.trees, trees_top.multimesh.instance_count)
	_fps_samples.clear()


# ---------------------------------------------------------------- jogador

func _make_player() -> void:
	player = CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	player.add_child(col)
	cam = Camera3D.new()
	cam.position.y = 0.7
	cam.fov = 72.0
	cam.far = 900.0
	player.add_child(cam)
	add_child(player)
	# Nasce na praia, olhando para o centro da ilha.
	var spawn := Vector3.ZERO
	for i in 200:
		var p := Vector3(0, 0, -WORLD_SIZE * 0.5 + 10.0 + i * 1.5)
		var h := height_at(p.x, p.z)
		if h > 1.5:
			spawn = Vector3(p.x, h + 1.2, p.z)
			break
	player.position = spawn
	player.rotation.y = PI  # olhando para +Z (centro)


func _physics_process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	player.rotation.y -= look.x * 2.6 * delta
	_pitch = clampf(_pitch - look.y * 1.9 * delta, -1.4, 1.4)
	cam.rotation.x = _pitch

	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := 9.0 if Input.is_action_pressed("sprint") else 4.5
	var dir := (player.transform.basis * Vector3(move.x, 0, move.y))
	dir.y = 0
	var v := player.velocity
	v.x = dir.x * speed
	v.z = dir.z * speed
	if player.is_on_floor():
		v.y = 5.0 if Input.is_action_just_pressed("jump") else -1.0
	else:
		v.y -= 18.0 * delta
	# Na água o jogador boia devagar.
	if player.position.y < SEA_LEVEL - 0.6:
		v.y = maxf(v.y, 1.5)
	player.velocity = v
	player.move_and_slide()
	# Não deixa sair da ilha.
	var lim := WORLD_SIZE * 0.5 - 2.0
	player.position.x = clampf(player.position.x, -lim, lim)
	player.position.z = clampf(player.position.z, -lim, lim)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		player.rotation.y -= m.relative.x * 0.0025
		_pitch = clampf(_pitch - m.relative.y * 0.0025, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("quit_game"):
		get_tree().quit()
	elif event.is_action_pressed("cycle_quality"):
		quality = (quality + 1) % QUALITY.size()
		_auto_checks = 99
		_apply_quality()
	elif event.is_action_pressed("cycle_time"):
		time_index = (time_index + 1) % TIMES.size()
		_apply_time()


# ---------------------------------------------------------------- HUD

func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(28, 20)
	hud.add_theme_font_size_override("font_size", 24)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	hint = Label.new()
	hint.text = "Analógicos: andar/olhar   A: pular   B: correr   Y: qualidade   X: hora do dia   Select: sair"
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 6)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = -56
	layer.add_child(hint)


func _process(delta: float) -> void:
	_fps_samples.append(Engine.get_frames_per_second())
	if _fps_samples.size() > 120:
		_fps_samples.pop_front()
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.5
		var vp := get_viewport()
		var size3d := Vector2(vp.get_visible_rect().size) * vp.scaling_3d_scale
		hud.text = "FPS: %d   |   Qualidade: %s   |   Hora: %s\n3D: %dx%d   |   %s" % [
			Engine.get_frames_per_second(), QUALITY[quality].name, TIMES[time_index].name,
			size3d.x, size3d.y, RenderingServer.get_video_adapter_name()]
	# Auto-ajuste: nos primeiros segundos, baixa a qualidade se o FPS estiver ruim.
	if _auto_checks < 2:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = 4.0
			_auto_checks += 1
			if _avg_fps() < 40.0 and quality > 0:
				quality -= 1
				_apply_quality()


func _avg_fps() -> float:
	if _fps_samples.is_empty():
		return 60.0
	var s := 0.0
	for f in _fps_samples:
		s += f
	return s / _fps_samples.size()


# ---------------------------------------------------------------- entrada

func _setup_input() -> void:
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0, KEY_A)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0, KEY_D)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0, KEY_W)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0, KEY_S)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0, KEY_LEFT)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0, KEY_RIGHT)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0, KEY_UP)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0, KEY_DOWN)
	_button("jump", JOY_BUTTON_A, KEY_SPACE)
	_button("sprint", JOY_BUTTON_B, KEY_SHIFT)
	_button("sprint", JOY_BUTTON_LEFT_STICK, KEY_NONE)
	_button("cycle_quality", JOY_BUTTON_Y, KEY_Q)
	_button("cycle_time", JOY_BUTTON_X, KEY_T)
	_button("quit_game", JOY_BUTTON_BACK, KEY_ESCAPE)


func _ensure(action: String, deadzone := 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)


func _axis(action: String, axis: JoyAxis, value: float, key: Key) -> void:
	_ensure(action)
	var j := InputEventJoypadMotion.new()
	j.axis = axis
	j.axis_value = value
	j.device = -1
	InputMap.action_add_event(action, j)
	if key != KEY_NONE:
		var k := InputEventKey.new()
		k.physical_keycode = key
		InputMap.action_add_event(action, k)


func _button(action: String, button: JoyButton, key: Key) -> void:
	_ensure(action, 0.5)
	var j := InputEventJoypadButton.new()
	j.button_index = button
	j.device = -1
	InputMap.action_add_event(action, j)
	if key != KEY_NONE:
		var k := InputEventKey.new()
		k.physical_keycode = key
		InputMap.action_add_event(action, k)


# ---------------------------------------------------------------- autoteste

func _selftest(dir: String) -> void:
	_auto_checks = 99
	DirAccess.make_dir_recursive_absolute(dir)
	var shots := [[0, 1, "ilha_manha_media"], [2, 2, "ilha_por_do_sol_alta"], [3, 0, "ilha_noite_baixa"]]
	for s in shots:
		time_index = s[0]
		quality = s[1]
		_apply_time()
		_apply_quality()
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(s[2] + ".png"))
		print("SELFTEST ", s[2], " fps=", Engine.get_frames_per_second())
		player.rotation.y += 0.9
	get_tree().quit()
