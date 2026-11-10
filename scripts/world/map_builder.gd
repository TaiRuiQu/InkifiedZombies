class_name MapBuilder
extends Node3D

## Builds a data-selected ink-wash arena with a separate batched detail pass.
## Everything is procedural primitives and shaders — no imported models.

const GROUND_SHADER: Shader = preload("res://shaders/ink_ground.gdshader")
const SKY_SHADER: Shader = preload("res://shaders/ink_sky_dome.gdshader")
const BRUSH_FONT: Font = preload("res://assets/fonts/MaShanZheng-Regular.ttf")

const ARENA_RADIUS := 27.9
const GATE_COUNT := 8
const GATE_RADIUS := 24.6
const SPAWN_RADIUS := 35.0

var definition: MapDefinition
var map_id := "courtyard"
var rng := RandomNumberGenerator.new()
var spawn_positions: Array[Vector3] = []
var player_spawn := Vector3(0.0, 0.1, 17.0)
var arena_center := Vector3.ZERO

var _dome: MeshInstance3D
var _lanterns: Array[OmniLight3D] = []
var _lantern_base_energy: Array[float] = []
var _lantern_phase: Array[float] = []
var _time := 0.0
var _world_body: StaticBody3D


func configure(id: String) -> void:
	definition = MapDB.get_map(id)
	map_id = definition.id
	player_spawn = definition.player_spawn


func build(id: String = "") -> void:
	if not id.is_empty() or definition == null:
		configure(id if not id.is_empty() else map_id)
	rng.seed = definition.seed_value
	_build_world_body()
	_build_environment()
	_build_sky()
	_build_ground()
	_build_walls()
	_build_gates()
	_build_landmarks()
	_build_props()
	_build_nature()
	_build_mountains()
	_build_atmosphere()
	var detail_pass := MapDetails.new()
	detail_pass.name = "ArchitecturalDetails"
	add_child(detail_pass)
	detail_pass.build(self, definition)


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_dome):
		var cam := get_viewport().get_camera_3d()
		if cam:
			_dome.global_position = cam.global_position
	for i in _lanterns.size():
		var light := _lanterns[i]
		if is_instance_valid(light):
			var phase := _lantern_phase[i]
			var flicker := 0.86 + 0.14 * sin(_time * 7.3 + phase) * sin(_time * 3.1 + phase * 1.7)
			light.light_energy = _lantern_base_energy[i] * flicker


# --------------------------------------------------------------------------
# World body / environment
# --------------------------------------------------------------------------

func _build_world_body() -> void:
	_world_body = StaticBody3D.new()
	_world_body.name = "WorldCollision"
	_world_body.collision_layer = 1
	_world_body.collision_mask = 0
	add_child(_world_body)
	_collider(Vector3(140.0, 1.0, 140.0), Vector3(0, -0.5, 0), Vector3.ZERO)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a99e88")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = definition.ambient_color
	env.ambient_light_energy = definition.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.98

	env.fog_enabled = true
	env.fog_light_color = definition.fog_color
	env.fog_light_energy = 0.45
	env.fog_sun_scatter = 0.1
	env.fog_density = definition.fog_density
	env.fog_sky_affect = 0.0
	env.fog_height = 1.5
	env.fog_height_density = 0.045

	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.1

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = definition.sun_light
	sun.light_energy = definition.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	add_child(sun)
	sun.look_at_from_position(Vector3(-42, 18, -68), Vector3.ZERO, Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("8fa6b8")
	fill.light_energy = 0.36
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3(30, 22, 46), Vector3.ZERO, Vector3.UP)


func _build_sky() -> void:
	_dome = MeshInstance3D.new()
	_dome.name = "SkyDome"
	var sphere := SphereMesh.new()
	sphere.radius = 620.0
	sphere.height = 1240.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_dome.mesh = sphere
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.extra_cull_margin = 100.0
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("sun_dir", Vector3(-0.45, 0.21, -0.87).normalized())
	mat.set_shader_parameter("top_color", definition.sky_top)
	mat.set_shader_parameter("horizon_color", definition.sky_horizon)
	mat.set_shader_parameter("low_color", Color("aaa08a"))
	mat.set_shader_parameter("cloud_color", Color("33393a"))
	mat.set_shader_parameter("sun_color", definition.sun_color)
	mat.set_shader_parameter("ridge_far", Color("8a948b"))
	mat.set_shader_parameter("ridge_mid", Color("5f6c63"))
	mat.set_shader_parameter("ridge_near", Color("38443e"))
	mat.set_shader_parameter("ridge_near_strength", 1.0 if definition.night else 0.0)
	mat.set_shader_parameter("cloud_amount", 0.9)
	_dome.material_override = mat
	add_child(_dome)


func _build_ground() -> void:
	# Outer ink-dark plain.
	var outer := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	outer.mesh = plane
	outer.position.y = -0.07
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var outer_mat := ShaderMaterial.new()
	outer_mat.shader = GROUND_SHADER
	outer_mat.set_shader_parameter("base_color", Color("37342c"))
	outer_mat.set_shader_parameter("ink_color", Color("12110e"))
	outer_mat.set_shader_parameter("dust_color", Color("49443a"))
	outer_mat.set_shader_parameter("moss_color", Color("333c32"))
	outer_mat.set_shader_parameter("arena_radius", 500.0)
	outer.material_override = outer_mat
	add_child(outer)

	# Painted arena floor.
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 28.9
	cyl.bottom_radius = 28.9
	cyl.height = 0.4
	cyl.radial_segments = 96
	disc.mesh = cyl
	disc.position.y = -0.2
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("base_color", definition.ground_color)
	mat.set_shader_parameter("ink_color", Color("15130e"))
	mat.set_shader_parameter("dust_color", Color("a79a82"))
	mat.set_shader_parameter("moss_color", Color("414b3b"))
	mat.set_shader_parameter("arena_radius", 27.5)
	disc.material_override = mat
	add_child(disc)

	# Worn stone processional path from the south gate.
	for i in 12:
		var z := 24.0 - i * 1.55
		var stone := Color("6e6757").lerp(Color("8e836d"), rng.randf())
		Ink.add_box(self, Vector3(2.0 + rng.randf_range(-0.2, 0.3), 0.09, 1.15),
			stone, Vector3(rng.randf_range(-0.35, 0.35), 0.02, z),
			Vector3(0, rng.randf_range(-5, 5), 0),
			{"outline": 0.006, "wash": 0.55, "wobble": 0.002})

	# Ink splashes and spills across the floor.
	for i in 30:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(2.5, 25.0)
		_splat_decal(Vector3(cos(ang) * rad, 0.012, sin(ang) * rad), rng.randf_range(1.4, 5.0), rng.randi() % 3)

	# Long dry-brush sweeps.
	for i in 18:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(3.0, 24.0)
		_brush_streak(Vector3(cos(ang) * rad, 0.015, sin(ang) * rad),
			rng.randf_range(4.0, 11.0), rng.randf_range(0, 360), rng.randf_range(0.8, 2.4), i % 4)


# --------------------------------------------------------------------------
# Walls and gates
# --------------------------------------------------------------------------

func _build_walls() -> void:
	var pieces := 32
	for i in pieces:
		var a := TAU * float(i) / float(pieces)
		if _near_gate(a, 6.2):
			continue
		_wall_piece(a, ARENA_RADIUS)

	# Players stay in the courtyard; enemies can walk in from outside.
	var boundary := StaticBody3D.new()
	boundary.name = "PlayerBoundary"
	boundary.collision_layer = 64
	boundary.collision_mask = 0
	add_child(boundary)
	for g in GATE_COUNT:
		var a := TAU * float(g) / float(GATE_COUNT)
		var p := Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS + 0.2)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.9, 6.0, 6.4)
		var barrier := CollisionShape3D.new()
		barrier.shape = shape
		barrier.position = p + Vector3.UP * 3.0
		barrier.rotation.y = -a
		boundary.add_child(barrier)


func _near_gate(a: float, threshold_deg: float) -> bool:
	for g in GATE_COUNT:
		var ga := TAU * float(g) / float(GATE_COUNT)
		if absf(wrapf(a - ga, -PI, PI)) < deg_to_rad(threshold_deg):
			return true
	return false


func _wall_piece(a: float, radius: float) -> void:
	var span := TAU / 32.0
	var length := 2.0 * radius * sin(span * 0.5) * 1.02
	var p := Vector3(cos(a), 0, sin(a)) * radius
	var rot_y := -rad_to_deg(a)
	var h := 2.95 + rng.randf_range(-0.2, 0.55)
	var stone := Color("5f5a4c").lerp(Color("78705e"), rng.randf())
	var wall_mesh := Ink.add_box(self, Vector3(1.05, h, length), stone, Vector3(p.x, h * 0.5, p.z),
		Vector3(rng.randf_range(-0.6, 0.6), rot_y, rng.randf_range(-0.5, 0.5)),
		{"outline": 0})
	wall_mesh.material_override = Ink.wall(stone, {
		"outline": 0.009, "wobble": 0.0025, "moss": 0.75, "hatch": 0.55,
		"pool": 0.4, "block_w": 1.05, "block_h": 0.54
	})
	Ink.add_box(self, Vector3(1.32, 0.16, length + 0.12), Ink.INK_SOFT,
		Vector3(p.x, h + 0.06, p.z), Vector3(0, rot_y, 0),
		{"outline": 0.008, "wobble": 0.002, "pool": 0.1})
	# Broken crown stones.
	for k in rng.randi_range(0, 2):
		var t := rng.randf_range(-0.38, 0.38)
		var bp := p + Vector3(-sin(a), 0, cos(a)) * t * length
		var bh := rng.randf_range(0.12, 0.3)
		Ink.add_box(self, Vector3(0.9, bh, 0.7), stone.darkened(0.08), Vector3(bp.x, h + 0.1 + bh * 0.5, bp.z),
			Vector3(0, rot_y + rng.randf_range(-12, 12), 0), {"outline": 0.007, "wobble": 0.002})
	# A broken merlon every few pieces gives the wall a torn silhouette.
	if rng.randf() > 0.42:
		var mh := rng.randf_range(0.55, 1.15)
		Ink.add_box(self, Vector3(0.85, mh, 1.35), stone.darkened(0.04),
			Vector3(p.x, h + 0.08 + mh * 0.5, p.z),
			Vector3(0, rot_y + rng.randf_range(-6, 6), rng.randf_range(-2, 2)),
			{"outline": 0.008, "wobble": 0.003, "wash": 0.5})
	# Wet moss on the arena-facing side.
	var inward := Vector3(-p.x, 0, -p.z).normalized()
	var tangent := Vector3(-sin(a), 0, cos(a))
	var mp := p + inward * 0.55 + tangent * rng.randf_range(-length * 0.3, length * 0.3) + Vector3(0, rng.randf_range(0.3, h - 0.3), 0)
	Ink.add_sphere(self, 0.3, Color("4c5745"), mp, Vector3(1.3, 0.55, 1.8), Vector3(0, rng.randf_range(0, 360), 0),
		{"outline": 0.005, "wobble": 0.003, "wash": 0.5})
	_collider(Vector3(1.05, h, length), Vector3(p.x, h * 0.5, p.z), Vector3(0, rot_y, 0))


func _build_gates() -> void:
	var glyphs := ["魄", "魇", "祟", "殤", "魅", "妄", "冥", "魍"]
	for g in GATE_COUNT:
		var a := TAU * float(g) / float(GATE_COUNT)
		var center := Vector3(cos(a), 0, sin(a)) * GATE_RADIUS
		var rot_y := -rad_to_deg(a)
		var gate := Node3D.new()
		gate.name = "Gate_%d" % g
		gate.position = center
		gate.rotation_degrees.y = rot_y
		add_child(gate)

		var wood := Color("4a3d31")
		var wood_hi := Color("63523f")
		Ink.add_box(gate, Vector3(0.3, 3.5, 0.3), wood, Vector3(0, 1.75, -2.35),
			Vector3(0, 0, rng.randf_range(-2, 2)), {"outline": 0.008, "wobble": 0.003, "wash": 0.4})
		Ink.add_box(gate, Vector3(0.3, 3.5, 0.3), wood, Vector3(0, 1.75, 2.35),
			Vector3(0, 0, rng.randf_range(-2, 2)), {"outline": 0.008, "wobble": 0.003, "wash": 0.4})
		Ink.add_box(gate, Vector3(0.42, 0.34, 5.15), wood_hi, Vector3(0, 3.6, 0),
			Vector3(0, 0, rng.randf_range(-1.5, 1.5)), {"outline": 0.008, "wobble": 0.002})
		Ink.add_box(gate, Vector3(0.3, 0.22, 4.5), wood, Vector3(0, 3.05, 0),
			Vector3(0, 0, 0), {"outline": 0.007, "wobble": 0.002})
		# Paper talisman hanging in the passage, facing the arena.
		Ink.add_box(gate, Vector3(0.035, 1.15, 0.62), Ink.PAPER, Vector3(-0.02, 2.42, 0),
			Vector3(0, 0, rng.randf_range(-3, 3)), {"outline": 0.005, "wobble": 0.004, "wash": 0.25, "rim": 0.2})
		Ink.add_box(gate, Vector3(0.02, 0.24, 0.24), Ink.CINNABAR, Vector3(-0.045, 2.1, 0),
			Vector3(0, 0, rng.randf_range(-8, 8)), {"outline": 0.003})
		var label := Ink.add_label(gate, glyphs[g], BRUSH_FONT, 92, Ink.INK,
			Vector3(-0.05, 2.48, 0), 0.0042, Vector3(0, -90, 0), false)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.rotation_degrees = Vector3(0, -90, 0)

		# Charred base stones and a permanent ink pool.
		Ink.add_cylinder(gate, 0.22, 0.26, 0.18, Color("4d4940"), Vector3(0, 0.09, -2.35), Vector3.ZERO,
			{"outline": 0.006, "wobble": 0.002})
		Ink.add_cylinder(gate, 0.22, 0.26, 0.18, Color("4d4940"), Vector3(0, 0.09, 2.35), Vector3.ZERO,
			{"outline": 0.006, "wobble": 0.002})
		_splat_decal(center + Vector3(-cos(a), 0, -sin(a)) * 0.7, 2.6, g % 3)
		_collider(Vector3(0.4, 3.5, 0.4), center + Vector3(-sin(a), 0, cos(a)) * 2.35 + Vector3(0, 1.75, 0), Vector3(0, rot_y, 0))
		_collider(Vector3(0.4, 3.5, 0.4), center + Vector3(sin(a), 0, -cos(a)) * 2.35 + Vector3(0, 1.75, 0), Vector3(0, rot_y, 0))

		spawn_positions.append(Vector3(cos(a), 0, sin(a)) * SPAWN_RADIUS + Vector3.UP * 0.05)


# --------------------------------------------------------------------------
# Landmarks
# --------------------------------------------------------------------------

func _build_landmarks() -> void:
	_torii(Vector3(0, 0, -34.5), 0)
	_brush_monument(definition.monument_position)
	_well(definition.well_position)
	_build_pillars()
	_great_banner(Vector3(-14.5, 0, -24.8), "墨", Ink.CINNABAR_DARK)
	_great_banner(Vector3(14.5, 0, -24.8), "潮", Ink.INDIGO)
	# Fallen shrine beams.
	Ink.add_box(self, Vector3(3.6, 0.35, 0.4), Color("5c4a38"), Vector3(14, 0.3, -17),
		Vector3(4, 24, 8), {"outline": 0.008, "wobble": 0.002})
	Ink.add_box(self, Vector3(0.35, 2.0, 0.35), Color("5c4a38"), Vector3(15.5, 1.0, -16.6),
		Vector3(70, 12, 0), {"outline": 0.008, "wobble": 0.002})


func _great_banner(pos: Vector3, glyph: String, cloth: Color) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	Ink.add_cylinder(g, 0.11, 0.15, 6.2, Color("3b3024"), Vector3(0, 3.1, 0), Vector3(0, 0, 1.5),
		{"outline": 0.007, "wobble": 0.002})
	Ink.add_box(g, Vector3(2.7, 0.14, 0.14), Color("3b3024"), Vector3(1.15, 5.9, 0), Vector3(0, 0, -2),
		{"outline": 0.006, "wobble": 0.002})
	Ink.add_box(g, Vector3(2.15, 4.15, 0.04), cloth, Vector3(1.15, 3.8, 0.06), Vector3(0, 0, -1.2),
		{"outline": 0.008, "wobble": 0.005, "wash": 0.5, "rim": 0.2})
	Ink.add_box(g, Vector3(2.35, 0.12, 0.1), Ink.INK_SOFT, Vector3(1.15, 5.72, 0.06), Vector3(0, 0, -1.2),
		{"outline": 0.004, "wobble": 0.002})
	var label := Ink.add_label(g, glyph, BRUSH_FONT, 240, Ink.PAPER, Vector3(1.15, 3.85, 0.1),
		0.0062, Vector3.ZERO, false)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_collider(Vector3(0.5, 6.0, 0.5), pos + Vector3(0, 3.0, 0), Vector3.ZERO)


func _build_pillars() -> void:
	var spots := definition.pillar_positions
	for p in spots:
		_ruined_pillar(p)


func _ruined_pillar(pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = rng.randf_range(-20, 20)
	add_child(g)
	var h := rng.randf_range(3.2, 5.2)
	var stone := Color("6d6758").lerp(Color("89806c"), rng.randf())
	Ink.add_box(g, Vector3(1.5, 0.5, 1.5), Color("5a5548"), Vector3(0, 0.25, 0),
		Vector3(0, rng.randf_range(0, 20), 0), {"outline": 0.008, "wobble": 0.002, "wash": 0.5})
	Ink.add_box(g, Vector3(0.82, h, 0.82), stone, Vector3(0, 0.5 + h * 0.5, 0),
		Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)),
		{"outline": 0}).material_override = Ink.wall(stone, {
			"outline": 0.009, "wobble": 0.002, "moss": 0.55, "hatch": 0.45,
			"pool": 0.3, "block_w": 0.8, "block_h": 0.45
		})
	Ink.add_box(g, Vector3(0.95, 0.22, 0.95), stone.darkened(0.05), Vector3(0, 0.61, 0),
		Vector3.ZERO, {"outline": 0.006, "wobble": 0.002})
	# Broken crown.
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var off := Vector3(cos(a) * 0.22, h + 0.2 + k * 0.16, sin(a) * 0.22)
		Ink.add_box(g, Vector3(0.4, rng.randf_range(0.2, 0.55), 0.4), stone,
			off, Vector3(0, rng.randf_range(-15, 15), rng.randf_range(-12, 12)),
			{"outline": 0.006, "wobble": 0.003})
	# Paper seal wrapped around the shaft.
	Ink.add_box(g, Vector3(0.88, 0.72, 0.03), Ink.PAPER,
		Vector3(0, 0.5 + h * 0.62, 0.43), Vector3(0, 0, rng.randf_range(-4, 4)),
		{"outline": 0.004, "wobble": 0.006, "wash": 0.25})
	Ink.add_box(g, Vector3(0.26, 0.26, 0.02), Ink.CINNABAR,
		Vector3(0, 0.5 + h * 0.62, 0.455), Vector3(0, 0, rng.randf_range(-8, 8)),
		{"outline": 0.002, "wobble": 0.003})
	# Red binding rope.
	Ink.add_cylinder(g, 0.49, 0.49, 0.08, Ink.CINNABAR_DARK, Vector3(0, 0.5 + h * 0.3, 0),
		Vector3.ZERO, {"outline": 0.003})
	_collider(Vector3(1.2, h, 1.2), pos + Vector3(0, h * 0.5, 0), Vector3.ZERO)


func _torii(pos: Vector3, rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = rot_y
	add_child(g)
	var red := Color("8f2f24")
	var red_dark := Color("64221b")
	var black := Color("241f19")
	Ink.add_cylinder(g, 0.34, 0.46, 6.2, red_dark, Vector3(-4.1, 3.1, 0), Vector3(0, 0, -1.5),
		{"outline": 0.009, "wobble": 0.0025, "wash": 0.4})
	Ink.add_cylinder(g, 0.34, 0.46, 6.2, red_dark, Vector3(4.1, 3.1, 0), Vector3(0, 0, 1.5),
		{"outline": 0.009, "wobble": 0.0025, "wash": 0.4})
	Ink.add_box(g, Vector3(9.6, 0.5, 0.75), red, Vector3(0, 6.0, 0), Vector3(0, 0, 0),
		{"outline": 0.009, "wobble": 0.002, "wash": 0.35})
	Ink.add_box(g, Vector3(10.4, 0.22, 0.95), black, Vector3(0, 6.36, 0), Vector3(0, 0, 0),
		{"outline": 0.008, "wobble": 0.002})
	Ink.add_box(g, Vector3(8.1, 0.34, 0.5), red, Vector3(0, 4.85, 0), Vector3(0, 0, 0),
		{"outline": 0.008, "wobble": 0.002})
	Ink.add_box(g, Vector3(1.3, 0.9, 0.18), black, Vector3(0, 5.45, 0.28), Vector3.ZERO,
		{"outline": 0.006, "wobble": 0.002})
	var label := Ink.add_label(g, "墨 門", BRUSH_FONT, 72, Ink.PAPER, Vector3(0, 5.45, 0.4),
		0.0045, Vector3.ZERO, false)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Support feet.
	Ink.add_cylinder(g, 0.62, 0.72, 0.35, Color("5b564a"), Vector3(-4.1, 0.17, 0), Vector3.ZERO,
		{"outline": 0.007})
	Ink.add_cylinder(g, 0.62, 0.72, 0.35, Color("5b564a"), Vector3(4.1, 0.17, 0), Vector3.ZERO,
		{"outline": 0.007})


func _brush_monument(pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = 18.0
	add_child(g)
	# Stone plinth.
	Ink.add_cylinder(g, 1.45, 1.75, 0.55, Color("6f6a5b"), Vector3(0, 0.28, 0), Vector3.ZERO,
		{"outline": 0.009, "wobble": 0.002, "wash": 0.45})
	Ink.add_box(g, Vector3(2.1, 0.3, 2.1), Color("827b69"), Vector3(0, 0.66, 0), Vector3(0, 8, 0),
		{"outline": 0.009, "wobble": 0.002})
	# Broken chains / rings around the base.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		Ink.add_cylinder(g, 0.18, 0.2, 0.16, Ink.INK_SOFT, Vector3(cos(a) * 1.35, 0.08, sin(a) * 1.35), Vector3.ZERO,
			{"outline": 0.005})
	# Giant brush, plunged tip-down into the plinth.
	var tilt := Vector3(0, 0, 13.0)
	Ink.add_cylinder(g, 0.42, 0.05, 1.85, Ink.INK, Vector3(0.45, 1.5, 0.0), tilt,
		{"outline": 0.009, "wobble": 0.003, "wash": 0.35, "pool": 0.3})
	Ink.add_cylinder(g, 0.46, 0.46, 0.17, Ink.GOLD, Vector3(0.41, 2.45, 0.0), tilt,
		{"outline": 0.005, "wobble": 0.002})
	Ink.add_cylinder(g, 0.22, 0.26, 4.9, Color("4a392b"), Vector3(-0.16, 4.95, 0.0), tilt,
		{"outline": 0.01, "wobble": 0.0025, "wash": 0.38, "pool": 0.15})
	Ink.add_cylinder(g, 0.28, 0.28, 0.16, Ink.GOLD, Vector3(-0.5, 6.7, 0.0), tilt, {"outline": 0.005})
	# Tassel and charm.
	Ink.add_cylinder(g, 0.24, 0.06, 0.6, Ink.CINNABAR, Vector3(-0.82, 7.35, 0.0), tilt,
		{"outline": 0.006, "wobble": 0.005})
	Ink.add_capsule(g, 0.07, 0.62, Ink.CINNABAR_DARK, Vector3(-1.02, 7.0, 0.0), Vector3(6, 0, 18),
		{"outline": 0.004})
	# Paper charm tied to the handle.
	Ink.add_box(g, Vector3(0.03, 0.62, 0.42), Ink.PAPER, Vector3(0.12, 4.15, 0.25),
		Vector3(0, 12, 3), {"outline": 0.004, "wobble": 0.005, "wash": 0.2})
	Ink.add_box(g, Vector3(0.02, 0.2, 0.2), Ink.CINNABAR, Vector3(0.1, 4.05, 0.27),
		Vector3(0, 12, 3), {"outline": 0.002})
	# Ink pooling around the tip.
	_splat_decal(pos + Vector3(0.4, 0.012, 0.0), 2.8, 2)
	# Scattered prayer stones.
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.8, 2.7)
		Ink.add_sphere(g, 0.2, Color("6c675b"), Vector3(cos(a) * r, 0.12, sin(a) * r),
			Vector3(1.2, 0.6, 1.0), Vector3(0, rng.randf_range(0, 360), 0),
			{"outline": 0.005, "wobble": 0.002})
	_collider(Vector3(2.4, 2.0, 2.4), pos + Vector3(0, 1.0, 0), Vector3.ZERO)


func _well(pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	var stone := Color("726c5e")
	Ink.add_cylinder(g, 1.3, 1.4, 0.8, stone, Vector3(0, 0.4, 0), Vector3.ZERO,
		{"outline": 0.01, "wobble": 0.002, "wash": 0.45, "pool": 0.35})
	var torus := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.02
	tm.outer_radius = 1.38
	tm.rings = 20
	tm.ring_segments = 8
	torus.mesh = tm
	torus.position.y = 0.82
	torus.material_override = Ink.surface(stone, {"outline": 0.007, "wobble": 0.002})
	g.add_child(torus)
	Ink.add_cylinder(g, 1.02, 1.02, 0.06, Ink.INK, Vector3(0, 0.6, 0), Vector3.ZERO,
		{"outline": 0, "wash": 0.1})
	var wood := Color("4b3c2d")
	Ink.add_box(g, Vector3(0.16, 2.2, 0.16), wood, Vector3(-1.15, 1.1, 0), Vector3(0, 0, -2),
		{"outline": 0.007, "wobble": 0.002})
	Ink.add_box(g, Vector3(0.16, 2.2, 0.16), wood, Vector3(1.15, 1.1, 0), Vector3(0, 0, 2),
		{"outline": 0.007, "wobble": 0.002})
	Ink.add_prism(g, Vector3(2.7, 0.65, 1.5), Color("332d23"), Vector3(0, 2.45, 0), Vector3(0, 0, 0),
		{"outline": 0.008, "wobble": 0.002})
	Ink.add_cylinder(g, 0.3, 0.36, 0.42, Color("54432f"), Vector3(0.7, 1.7, 0), Vector3.ZERO,
		{"outline": 0.005, "wobble": 0.003})
	Ink.add_cylinder(g, 0.025, 0.025, 1.05, Color("2b251e"), Vector3(0.7, 2.4, 0), Vector3.ZERO,
		{"outline": 0})
	Ink.add_cylinder(g, 0.95, 0.98, 0.04, Color("141815"), Vector3(0, 0.56, 0), Vector3.ZERO,
		{"outline": 0, "wash": 0.05, "rim": 0.35})
	_collider(Vector3(2.9, 1.0, 2.9), pos + Vector3(0, 0.5, 0), Vector3.ZERO)


# --------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------

func _build_props() -> void:
	_lantern(Vector3(-12.5, 0, 10.5), 1.0)
	_lantern(Vector3(12.5, 0, 10.5), 1.0)
	_lantern(Vector3(-12.5, 0, -10.5), 1.0)
	_lantern(Vector3(12.5, 0, -10.5), 1.0)
	_lantern(Vector3(3.8, 0, 23.0), 1.15)
	_pine(Vector3(-18.5, 0, -3.0), 1.15)
	_pine(Vector3(18.0, 0, -10.5), 0.95)
	_pine(Vector3(-19.0, 0, 14.5), 0.8)
	_crates(Vector3(-9.5, 0, 11.5))
	_crates(Vector3(15.0, 0, 12.5))
	_barrels(Vector3(17.0, 0, 14.0))
	_barrels(Vector3(-16.0, 0, -15.0))
	_banner(Vector3(-23.0, 0, 3.5), -15.0, "墨", Ink.CINNABAR_DARK)
	_banner(Vector3(22.5, 0, 6.0), 185.0, "禁", Ink.INDIGO)
	_banner(Vector3(-8.0, 0, -23.5), 25.0, "守", Ink.PAPER_DARK)
	_banner(Vector3(8.5, 0, 22.5), 200.0, "夜", Ink.OCHRE_DARK)
	_scatter_rocks()
	# Broken cart wheel.
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.85
	tm.rings = 14
	tm.ring_segments = 6
	wheel.mesh = tm
	wheel.position = Vector3(-14.5, 0.85, -9.0)
	wheel.rotation_degrees = Vector3(0, 35, 78)
	wheel.material_override = Ink.surface(Color("4b3b2a"), {"outline": 0.007, "wobble": 0.002})
	add_child(wheel)


func _lantern(pos: Vector3, scale: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.scale = Vector3.ONE * scale
	add_child(g)
	var stone := Color("77705f")
	Ink.add_cylinder(g, 0.52, 0.72, 0.22, Color("625c4e"), Vector3(0, 0.11, 0), Vector3.ZERO,
		{"outline": 0.007, "wobble": 0.002})
	Ink.add_cylinder(g, 0.18, 0.24, 1.15, stone, Vector3(0, 0.75, 0), Vector3.ZERO,
		{"outline": 0.007, "wobble": 0.002, "wash": 0.45})
	Ink.add_box(g, Vector3(0.72, 0.12, 0.72), Color("5b564a"), Vector3(0, 1.38, 0), Vector3(0, 8, 0),
		{"outline": 0.006, "wobble": 0.002})
	# Light housing.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Ink.add_box(g, Vector3(0.09, 0.72, 0.09), Ink.INK_SOFT,
				Vector3(sx * 0.26, 1.78, sz * 0.26), Vector3.ZERO, {"outline": 0.004, "wobble": 0.002})
	Ink.add_box(g, Vector3(0.52, 0.64, 0.52), Color("f0d9a2"), Vector3(0, 1.78, 0), Vector3.ZERO,
		{"outline": 0, "wash": 0.1, "rim": 0.4})
	Ink.add_prism(g, Vector3(1.05, 0.42, 1.05), Color("3d3b34"), Vector3(0, 2.28, 0), Vector3(0, 45, 0),
		{"outline": 0.007, "wobble": 0.002})
	Ink.add_sphere(g, 0.13, Color("3d3b34"), Vector3(0, 2.55, 0), Vector3(1, 1.3, 1), Vector3.ZERO,
		{"outline": 0.004})
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.78, 0)
	light.light_color = Color("ffbf78")
	light.light_energy = 1.35
	light.omni_range = 8.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	g.add_child(light)
	_lanterns.append(light)
	_lantern_base_energy.append(light.light_energy)
	_lantern_phase.append(rng.randf() * 20.0)
	var glow := Ink.add_quad(g, Vector2(1.7, 1.7), Ink.glow(Color(1.0, 0.62, 0.28, 0.32)),
		Vector3(0, 1.78, 0), Vector3.ZERO)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(Vector3(1.0, 2.5, 1.0), pos + Vector3(0, 1.25, 0), Vector3.ZERO)


func _pine(pos: Vector3, scale_v: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.scale = Vector3.ONE * scale_v
	add_child(g)
	var bark := Color("3d2f23")
	var leaf := Color("39493d")
	var leaf_dark := Color("233028")
	Ink.add_cylinder(g, 0.2, 0.52, 3.8, bark, Vector3(0, 1.9, 0), Vector3(2, 0, 3),
		{"outline": 0.009, "wobble": 0.0025, "wash": 0.48, "pool": 0.35})
	Ink.add_cylinder(g, 0.09, 0.2, 2.8, bark, Vector3(0.28, 4.6, 0.1), Vector3(3, 0, -14),
		{"outline": 0.008, "wobble": 0.0025, "wash": 0.45})
	# Low root flares.
	for i in 3:
		var ra := TAU * float(i) / 3.0 + 0.4
		Ink.add_cylinder(g, 0.08, 0.22, 0.9, bark, Vector3(cos(ra) * 0.35, 0.3, sin(ra) * 0.35),
			Vector3(0, rad_to_deg(ra) + 90, 62), {"outline": 0.005, "wobble": 0.002})
	for i in 9:
		var ang := float(i) * 40.0 + rng.randf_range(-16, 16)
		var tilt := rng.randf_range(62, 82)
		var length := rng.randf_range(1.3, 2.7)
		var y := rng.randf_range(2.5, 5.6)
		var basis := Basis.from_euler(Vector3(0, deg_to_rad(ang), deg_to_rad(tilt)))
		var dir := basis * Vector3.UP
		var base := Vector3(0.18, y, 0.0) + dir * length * 0.5
		Ink.add_cylinder(g, 0.035, 0.095, length, bark, base,
			Vector3(0, ang, tilt), {"outline": 0.006, "wobble": 0.0025, "wash": 0.4})
		var tip := Vector3(0.18, y, 0.0) + dir * length
		# Flat layered needle pads, like dry-brush strokes.
		Ink.add_sphere(g, 0.84, leaf_dark, tip, Vector3(1.8, 0.2, 1.35),
			Vector3(0, ang, rng.randf_range(-4, 4)),
			{"outline": 0.008, "wobble": 0.005, "wash": 0.55, "hatch": 0.75})
		Ink.add_sphere(g, 0.58, leaf, tip + Vector3(0, 0.10, 0), Vector3(1.55, 0.16, 1.15),
			Vector3(0, ang + 26, rng.randf_range(-4, 4)),
			{"outline": 0.006, "wobble": 0.005, "wash": 0.5})
		# Needle sprays breaking the edge of each pad.
		for k in 5:
			var na := ang + float(k) * 72.0 + rng.randf_range(-14, 14)
			var spray_edge := tip + Vector3(cos(deg_to_rad(na)) * 1.15, -0.02, sin(deg_to_rad(na)) * 0.95)
			Ink.add_box(g, Vector3(0.06, 0.022, 0.78), leaf_dark, spray_edge,
				Vector3(rng.randf_range(-10, -2), 90.0 - na, rng.randf_range(-8, 4)),
				{"outline": 0.002, "wobble": 0.004, "rim": 0.0, "wash": 0.3})
	Ink.add_sphere(g, 1.15, leaf_dark, Vector3(0.3, 5.9, 0.1), Vector3(1.7, 0.3, 1.4),
		Vector3(0, 20, 0), {"outline": 0.009, "wobble": 0.005, "wash": 0.55, "hatch": 0.7})
	Ink.add_sphere(g, 0.7, leaf, Vector3(0.45, 6.1, 0.0), Vector3(1.3, 0.22, 1.1),
		Vector3(0, 64, 0), {"outline": 0.006, "wobble": 0.005, "wash": 0.45})
	_collider(Vector3(0.9, 3.0, 0.9), pos + Vector3(0, 1.5, 0), Vector3.ZERO)


func _crates(pos: Vector3) -> void:
	var g := Node3D.new()
	g.name = "Crates"
	g.position = pos
	g.rotation_degrees.y = rng.randf_range(-20, 20)
	add_child(g)
	var wood := Color("6b5138")
	var wood_dark := Color("41311f")
	var sizes := [Vector3(1.3, 1.0, 1.3), Vector3(1.0, 0.9, 1.0), Vector3(1.15, 1.15, 1.15)]
	var offsets := [Vector3(0, 0.5, 0), Vector3(1.15, 0.45, 0.2), Vector3(-0.5, 0.575, 1.1)]
	for i in 3:
		var s: Vector3 = sizes[i]
		var o: Vector3 = offsets[i]
		var color := wood.lerp(wood_dark, rng.randf())
		Ink.add_box(g, s, color, o,
			Vector3.ZERO,
			{"outline": 0.008, "wobble": 0.002, "wash": 0.4})
		var body := StaticBody3D.new()
		body.name = "Crate_%d" % i
		body.collision_layer = 1
		body.collision_mask = 0
		g.add_child(body)
		var shape := BoxShape3D.new()
		shape.size = s
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = o
		body.add_child(collision)
		# Slat lines.
		for k in 2:
			Ink.add_box(g, Vector3(s.x + 0.04, 0.06, 0.08), wood_dark,
				o + Vector3(0, -s.y * 0.25 + k * s.y * 0.5, s.z * 0.5 + 0.01),
				Vector3.ZERO, {"outline": 0.002})
		# Talisman.
		Ink.add_box(g, Vector3(0.32, 0.46, 0.02), Ink.PAPER,
			o + Vector3(0, 0.1, s.z * 0.5 + 0.03), Vector3(0, 6, 3),
			{"outline": 0.003, "wobble": 0.003, "wash": 0.2})
		Ink.add_box(g, Vector3(0.12, 0.12, 0.015), Ink.CINNABAR,
			o + Vector3(0, 0.02, s.z * 0.5 + 0.045), Vector3(0, 6, 3), {"outline": 0.001})


func _barrels(pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	for i in 3:
		var p := Vector3(i * 0.85 - 0.8, 0.55, rng.randf_range(-0.3, 0.3))
		var wood := Color("5f4630").lerp(Color("7c5d3d"), rng.randf())
		Ink.add_cylinder(g, 0.38, 0.34, 1.1, wood, p, Vector3(0, rng.randf_range(0, 360), 0),
			{"outline": 0.007, "wobble": 0.002, "wash": 0.4})
		for k in 2:
			Ink.add_cylinder(g, 0.395, 0.395, 0.07, Ink.INK_SOFT,
				p + Vector3(0, -0.3 + k * 0.6, 0), Vector3.ZERO, {"outline": 0.002})
	_collider(Vector3(2.4, 1.2, 1.0), pos + Vector3(0, 0.6, 0), Vector3.ZERO)


func _banner(pos: Vector3, rot_y: float, glyph: String, cloth: Color) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = rot_y
	add_child(g)
	Ink.add_cylinder(g, 0.09, 0.12, 4.4, Color("41362a"), Vector3(0, 2.2, 0), Vector3(0, 0, 1.5),
		{"outline": 0.006, "wobble": 0.002})
	Ink.add_box(g, Vector3(1.8, 0.1, 0.1), Color("41362a"), Vector3(0.75, 4.15, 0), Vector3.ZERO,
		{"outline": 0.005})
	Ink.add_box(g, Vector3(1.25, 2.1, 0.035), cloth, Vector3(0.7, 3.0, 0.04),
		Vector3(0, 0, rng.randf_range(-4, 4)),
		{"outline": 0.006, "wobble": 0.005, "wash": 0.5, "rim": 0.18})
	var label := Ink.add_label(g, glyph, BRUSH_FONT, 108, Ink.PAPER if cloth.get_luminance() < 0.5 else Ink.INK,
		Vector3(0.7, 3.05, 0.08), 0.0052, Vector3.ZERO, false)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED


func _scatter_rocks() -> void:
	for i in 16:
		var a := rng.randf() * TAU
		if _near_gate(a, 6.5):
			continue
		var r := rng.randf_range(19.0, 26.0)
		var p := Vector3(cos(a) * r, 0.1, sin(a) * r)
		var s := rng.randf_range(0.18, 0.55)
		Ink.add_sphere(self, s, Color("6b665a").lerp(Color("8a8372"), rng.randf()), p,
			Vector3(rng.randf_range(1.0, 1.8), rng.randf_range(0.45, 0.8), rng.randf_range(1.0, 1.6)),
			Vector3(0, rng.randf_range(0, 360), rng.randf_range(-8, 8)),
			{"outline": 0.006, "wobble": 0.002, "wash": 0.5})
		if s > 0.4:
			_collider(Vector3(s * 2.0, s * 1.2, s * 2.0), p, Vector3.ZERO)


func _splat_decal(pos: Vector3, size: float, variant: int) -> void:
	var mat := Ink.unlit(Color(0.07, 0.065, 0.06, 0.62), false, false, false, ProcTex.splat(variant))
	var q := Ink.add_quad(self, Vector2(size, size), mat, pos, Vector3(-90, rng.randf_range(0, 360), 0))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _brush_streak(pos: Vector3, length: float, angle: float, width: float, variant: int) -> void:
	var mat := Ink.unlit(Color(0.06, 0.055, 0.05, 0.20), false, false, false, ProcTex.brush_stroke(128, variant))
	var q := Ink.add_quad(self, Vector2(length, width), mat, pos, Vector3(-90, angle, 0))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --------------------------------------------------------------------------
# Nature / distant scenery
# --------------------------------------------------------------------------

func _build_nature() -> void:
	if definition.extra_bamboo:
		for p in [Vector3(-20, 0, -14), Vector3(20, 0, 15), Vector3(16, 0, -20), Vector3(-17, 0, 20)]:
			_bamboo(p, 12)
	_bamboo(Vector3(-22.5, 0, 4.0), 10)
	_bamboo(Vector3(23.0, 0, 1.0), 9)
	_bamboo(Vector3(-3.0, 0, -24.0), 8)
	_bamboo(Vector3(11.0, 0, -23.0), 7)
	_bamboo(Vector3(22.0, 0, -19.0), 8)

	# Reeds along the wall base.
	var blade := Ink.cylinder_mesh(0.0, 0.05, 0.85, 4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	mm.instance_count = 420
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(19.5, 26.8)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if rng.randf() > 0.55 and r < 23.0:
			r = rng.randf_range(24.0, 26.8)
			p = Vector3(cos(a) * r, 0.0, sin(a) * r)
		var s := rng.randf_range(0.5, 1.7)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.22, 0.22)))
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, s, s)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Ink.surface(Color("4c5746"), {"outline": 0, "wash": 0.4, "hatch": 0.2, "rim": 0.05})
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _bamboo(pos: Vector3, count: int) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	for i in count:
		var p := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var h := rng.randf_range(3.2, 6.8)
		var col := Color("5a7058").lerp(Color("788c62"), rng.randf())
		var tilt := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		Ink.add_cylinder(g, 0.045, 0.075, h, col, p + Vector3(0, h * 0.5, 0), tilt,
			{"outline": 0.005, "wobble": 0.003, "wash": 0.4, "pool": 0.15})
		for k in 3:
			var ny := h * (0.3 + k * 0.22)
			Ink.add_cylinder(g, 0.085, 0.085, 0.06, col.darkened(0.25), p + Vector3(0, ny, 0), tilt,
				{"outline": 0.002})
		for k in 6:
			var a := rng.randf() * TAU
			var leaf_pos := p + Vector3(cos(a) * 0.28, h - 0.4 + rng.randf_range(-0.45, 0.3), sin(a) * 0.28)
			Ink.add_box(g, Vector3(0.10, 0.02, 0.9), col.lightened(0.05), leaf_pos,
				Vector3(rng.randf_range(-16, 16), rad_to_deg(a), rng.randf_range(-16, 16)),
				{"outline": 0, "wobble": 0.004, "rim": 0.1})


func _build_mountains() -> void:
	_build_green_ridge()
	# Dark rounded hills just beyond the cliff ring.
	for i in 9:
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.16, 0.16)
		var r := rng.randf_range(62.0, 92.0)
		var h := rng.randf_range(6.0, 16.0)
		var rad := rng.randf_range(24.0, 42.0)
		# Keep the solid slopes beyond the enemy approach lanes.
		r = maxf(r, rad * 1.7 + SPAWN_RADIUS + 6.0)
		var col := Color("28332c").lerp(Color("3c4a3f"), rng.randf())
		var hill := Ink.add_sphere(self, rad, col,
			Vector3(cos(a) * r, -h * 0.4, sin(a) * r),
			Vector3(1.7, h / rad, 1.3),
			Vector3(0, rng.randf_range(0, 360), rng.randf_range(-4, 4)),
			{"outline": 0, "wash": 0.5, "hatch": 0.12, "rim": 0.0, "pool": 0.0, "scale": 0.1})
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hill.name = "GreenSlope_%d" % i
		# Bake the visible geometry into collision, including its stretched shape.
		var faces := hill.mesh.get_faces()
		for vertex in faces.size():
			faces[vertex] = hill.transform * faces[vertex]
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.name = "GreenSlopeCollision_%d" % i
		collision.shape = shape
		_world_body.add_child(collision)

	# A broken ring of cliff rocks around the plateau (open at the north gate).
	for i in 34:
		var a := TAU * float(i) / 34.0 + rng.randf_range(-0.06, 0.06)
		if absf(wrapf(a - TAU * 0.75, -PI, PI)) < 0.42:
			continue
		var r := rng.randf_range(40.0, 52.0)
		var h := rng.randf_range(4.0, 10.5)
		var rad := rng.randf_range(2.5, 5.0)
		var col := Color("4b4b42").lerp(Color("646256"), rng.randf())
		var rock := Ink.add_sphere(self, rad, col,
			Vector3(cos(a) * r, h * 0.15, sin(a) * r),
			Vector3(rng.randf_range(0.9, 1.5), h / rad, rng.randf_range(0.8, 1.3)),
			Vector3(0, rng.randf_range(0, 360), rng.randf_range(-8, 8)),
			{"outline": 0.008, "wobble": 0.004, "wash": 0.55, "hatch": 0.4, "rim": 0.05, "pool": 0.0})
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if rng.randf() > 0.55:
			var h2 := rng.randf_range(2.0, 5.0)
			var rock2 := Ink.add_sphere(self, rad * 0.55, col.darkened(0.08),
				Vector3(cos(a + 0.04) * (r + 1.0), h * 0.5, sin(a + 0.04) * (r + 1.0)),
				Vector3(1.0, h2 / (rad * 0.55), 0.9), Vector3(0, rng.randf_range(0, 360), 0),
				{"outline": 0.007, "wobble": 0.004, "wash": 0.5, "hatch": 0.4, "rim": 0.04, "pool": 0.0})
			rock2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Forest silhouettes beyond the cliffs.
	var tree_mesh := Ink.cylinder_mesh(0.0, 0.9, 7.0, 5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tree_mesh
	mm.instance_count = 70
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(50.0, 76.0)
		var s := rng.randf_range(0.5, 1.5)
		var basis := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(cos(a) * r, 3.5 * s - 0.3, sin(a) * r)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Ink.surface(Color("232d27"), {"outline": 0, "wash": 0.3, "rim": 0.0})
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_green_ridge() -> void:
	# World-space rolling terrain replaces the nearby painted sky silhouette.
	# The inner skirt stays outside all eight enemy approach lanes.
	var radii := [48.0, 70.0, 98.0, 125.0, 165.0, 205.0]
	var profile := [0.0, 0.38, 1.0, 0.72, 0.28, 0.0]
	var segments := 96
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in radii.size() - 1:
		for column in segments:
			var corners: Array[Vector3] = []
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]:
				var ring_index: int = row + offset.x
				var angle := TAU * float(column + offset.y) / segments
				var height := (18.0 + 6.0 * sin(angle * 3.0 + 0.7) + 3.0 * sin(angle * 7.0 + 2.1)) * float(profile[ring_index]) - 0.5
				var distance: float = radii[ring_index]
				corners.append(Vector3(cos(angle) * distance, height, sin(angle) * distance))
			for index in [0, 1, 2, 1, 3, 2]:
				surface.add_vertex(corners[index])
	surface.generate_normals()
	var mesh := surface.commit()
	var terrain := MeshInstance3D.new()
	terrain.name = "GreenRidgeTerrain"
	terrain.mesh = mesh
	terrain.material_override = Ink.surface(Color("46664b") if not definition.night else Color("304a43"),
		{"outline": 0, "wash": 0.36, "hatch": 0.15, "rim": 0.04, "scale": 0.12})
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)
	var collision := CollisionShape3D.new()
	collision.name = "GreenRidgeTerrainCollision"
	collision.shape = mesh.create_trimesh_shape()
	_world_body.add_child(collision)


func _build_atmosphere() -> void:
	# Drifting ash.
	var ash := CPUParticles3D.new()
	ash.position = Vector3(0, 5.5, 0)
	ash.amount = 110
	ash.lifetime = 16.0
	ash.preprocess = 6.0
	ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ash.emission_box_extents = Vector3(30, 7, 30)
	ash.direction = Vector3(0.2, -1, 0.15)
	ash.spread = 35.0
	ash.gravity = Vector3(0.12, -0.42, 0.06)
	ash.initial_velocity_min = 0.15
	ash.initial_velocity_max = 0.55
	ash.scale_amount_min = 0.35
	ash.scale_amount_max = 1.1
	var ash_quad := QuadMesh.new()
	ash_quad.size = Vector2(0.07, 0.07)
	ash.mesh = ash_quad
	ash.material_override = Ink.unlit(Color(0.92, 0.88, 0.77, 0.6), false, true, false, ProcTex.soft_circle(32))
	add_child(ash)

	# Heavy ink flakes.
	var flakes := CPUParticles3D.new()
	flakes.position = Vector3(0, 6.0, 0)
	flakes.amount = 28
	flakes.lifetime = 18.0
	flakes.preprocess = 4.0
	flakes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flakes.emission_box_extents = Vector3(28, 6, 28)
	flakes.direction = Vector3(-0.3, -1, 0.2)
	flakes.spread = 25.0
	flakes.gravity = Vector3(-0.18, -0.7, 0.12)
	flakes.initial_velocity_min = 0.2
	flakes.initial_velocity_max = 0.7
	flakes.scale_amount_min = 0.4
	flakes.scale_amount_max = 1.3
	var flake_quad := QuadMesh.new()
	flake_quad.size = Vector2(0.12, 0.05)
	flakes.mesh = flake_quad
	flakes.material_override = Ink.unlit(Color(0.10, 0.10, 0.09, 0.65), false, true, false, ProcTex.brush_stroke(32, 1))
	add_child(flakes)


# --------------------------------------------------------------------------
# Utility
# --------------------------------------------------------------------------

func _collider(size: Vector3, pos: Vector3, rot_deg: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	_world_body.add_child(cs)
