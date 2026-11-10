class_name WeaponDetails
extends RefCounted

## Small readable features in the player's near field: fasteners, controls,
## sights, open muzzles, machined edges, inlays, grip wraps and jointed gloves.
const STEEL := Color("777b72")
const BRASS := Color("b79756")
const DARK := Color("121819")
const JADE := Color("719c91")
const GLOVE := Color("303a39")

static func build(model: WeaponModel, id: String) -> void:
	var detail_builders := {
		"brush_pistol": _pistol, "ink_shotgun": _shotgun,
		"wolf_smg": _smg, "cinnabar_rifle": _rifle,
		"ink_launcher": _launcher, "thunder_crossbow": _crossbow,
	}
	if detail_builders.has(id):
		detail_builders[id].call(model)
	_common(model, id)
	_hands(model, id)

static func _box(m: WeaponModel, size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return m._part(Ink.box_mesh(size), color, pos, rot, {"outline": 0.0012, "grain": 0.07})

static func _cyl(m: WeaponModel, radius: float, height: float, color: Color, pos: Vector3, rot := Vector3(90, 0, 0)) -> MeshInstance3D:
	return m._part(Ink.cylinder_mesh(radius, radius, height, 12), color, pos, rot, {"outline": 0.0010, "grain": 0.08})

static func _screw(m: WeaponModel, pos: Vector3, side: float) -> void:
	_cyl(m, 0.010, 0.006, STEEL, pos, Vector3(0, 0, 90))
	_box(m, Vector3(0.007, 0.002, 0.012), DARK, pos + Vector3(side * 0.004, 0, 0))

static func _front_sight(m: WeaponModel, z: float, y: float, width: float = 0.06) -> void:
	_box(m, Vector3(width, 0.012, 0.025), BRASS, Vector3(0, y, z))
	_box(m, Vector3(0.009, 0.037, 0.014), STEEL, Vector3(0, y + 0.020, z))
	_cyl(m, 0.006, 0.008, JADE, Vector3(0, y + 0.040, z + 0.008))

static func _rune(m: WeaponModel, x: float, y: float, z: float) -> void:
	# A narrow brass seal written in the visible side panel.
	for i in 3:
		_box(m, Vector3(0.003, 0.006, 0.035 - i * 0.006), BRASS, Vector3(x, y - i * 0.016, z + i * 0.008))
	_box(m, Vector3(0.003, 0.05, 0.006), BRASS, Vector3(x, y - 0.016, z))

static func _common(m: WeaponModel, id: String) -> void:
	var width := 0.08 if id == "thunder_crossbow" else 0.12
	# Open trigger guard, trigger and pivot.
	_box(m, Vector3(0.012, 0.075, 0.012), BRASS, Vector3(width * 0.30, -0.100, -0.08))
	_box(m, Vector3(0.012, 0.012, 0.110), BRASS, Vector3(width * 0.30, -0.140, -0.03))
	_box(m, Vector3(0.012, 0.050, 0.012), BRASS, Vector3(width * 0.30, -0.115, 0.020))
	_box(m, Vector3(0.010, 0.038, 0.015), STEEL, Vector3(0.015, -0.080, -0.028), Vector3(16, 0, 0))
	for z in [-0.12, 0.08]:
		_screw(m, Vector3(width * 0.58, 0.010, z), 1.0)
	_rune(m, width * 0.60, 0.050, -0.010)
	# Raised back notch with two paint dots; real opening leaves aim line clear.
	for side in [-1, 1]:
		_box(m, Vector3(0.018, 0.025, 0.022), DARK, Vector3(side * 0.025, 0.115, 0.060))
		_cyl(m, 0.004, 0.003, Ink.PAPER, Vector3(side * 0.024, 0.122, 0.073))

static func _pistol(m: WeaponModel) -> void:
	for i in 6:
		_box(m, Vector3(0.003, 0.044, 0.006), STEEL, Vector3(0.059, 0.048, -0.015 + i * 0.014), Vector3(0, 0, -10))
	var slide := _box(m, Vector3(0.065, 0.018, 0.17), STEEL, Vector3(0, 0.091, -0.11))
	m.register_moving(slide, "bolt", Vector3(0, 0, 0.055))
	_box(m, Vector3(0.006, 0.022, 0.055), DARK, Vector3(0.060, 0.056, -0.130))
	_box(m, Vector3(0.009, 0.018, 0.033), BRASS, Vector3(0.065, -0.012, 0.010))
	for i in 5:
		_box(m, Vector3(0.101, 0.009, 0.10), GLOVE, Vector3(0, -0.079 - i * 0.028, 0.046), Vector3(13, 0, 2))
	var mag := _box(m, Vector3(0.10, 0.025, 0.12), BRASS, Vector3(0, -0.224, 0.056))
	m.register_moving(mag, "magazine", Vector3(0, -0.14, 0.02))
	_front_sight(m, -0.32, 0.095)

static func _shotgun(m: WeaponModel) -> void:
	for side in [-1, 1]:
		# Actual dark bore sits inside a brass muzzle lip.
		_cyl(m, 0.045, 0.012, BRASS, Vector3(side * 0.048, 0.055, -0.758))
		_cyl(m, 0.033, 0.014, DARK, Vector3(side * 0.048, 0.055, -0.767))
		for i in 4:
			_box(m, Vector3(0.009, 0.040, 0.025), STEEL, Vector3(side * 0.091, 0.055, -0.57 + i * 0.075))
	var pump := _box(m, Vector3(0.192, 0.037, 0.23), BRASS.darkened(0.35), Vector3(0, -0.088, -0.32))
	m.register_moving(pump, "pump", Vector3(0, 0, 0.12))
	for i in 4:
		_cyl(m, 0.021, 0.068, Ink.CINNABAR, Vector3(0.106, 0.0, -0.08 + i * 0.052), Vector3.ZERO)
		_cyl(m, 0.023, 0.016, BRASS, Vector3(0.106, -0.040, -0.08 + i * 0.052), Vector3.ZERO)
	_box(m, Vector3(0.125, 0.13, 0.018), GLOVE, Vector3(0, -0.07, 0.417))
	_front_sight(m, -0.67, 0.110, 0.045)

static func _smg(m: WeaponModel) -> void:
	for i in 7:
		_box(m, Vector3(0.006, 0.025, 0.020), DARK, Vector3(0.072, 0.020, -0.15 + i * 0.040))
	var bolt := _box(m, Vector3(0.035, 0.018, 0.040), STEEL, Vector3(0.090, 0.050, -0.020))
	m.register_moving(bolt, "bolt", Vector3(0, 0, 0.080))
	for i in 6:
		var angle := float(i) * TAU / 6.0
		_cyl(m, 0.012, 0.014, BRASS, Vector3(cos(angle) * 0.105, -0.16 + sin(angle) * 0.105, 0.077))
	var mag := _cyl(m, 0.10, 0.014, BRASS, Vector3(0, -0.16, 0.080))
	m.register_moving(mag, "magazine", Vector3(0, -0.16, 0.04))
	for i in 4:
		_cyl(m, 0.040, 0.015, GLOVE, Vector3(0, -0.07 - i * 0.034, -0.25), Vector3(-20, 0, 0))
	_cyl(m, 0.036, 0.040, BRASS, Vector3(0, 0.06, -0.735))
	_cyl(m, 0.025, 0.010, DARK, Vector3(0, 0.06, -0.760))
	_front_sight(m, -0.43, 0.115)

static func _rifle(m: WeaponModel) -> void:
	# Scope collars and windage turret, bolt handle and lacquered wood inlay.
	for z in [-0.18, 0.020]:
		m.scope_tube(0.061, 0.024, BRASS, Vector3(0, 0.135, z))
		_box(m, Vector3(0.085, 0.035, 0.027), DARK, Vector3(0, 0.089, z))
	_cyl(m, 0.026, 0.038, STEEL, Vector3(0.068, 0.135, -0.075), Vector3(0, 0, 90))
	_cyl(m, 0.022, 0.032, STEEL, Vector3(0, 0.198, -0.075), Vector3.ZERO)
	var bolt := _box(m, Vector3(0.092, 0.018, 0.018), BRASS, Vector3(0.065, 0.030, 0.11), Vector3(0, 0, -25))
	m.register_moving(bolt, "bolt", Vector3(0.02, 0.01, 0.12))
	_cyl(m, 0.019, 0.027, DARK, Vector3(0.107, 0.010, 0.11), Vector3.ZERO)
	for i in 5:
		_box(m, Vector3(0.112, 0.008, 0.008), BRASS, Vector3(0, -0.024, 0.18 + i * 0.035))
	var mag := _box(m, Vector3(0.084, 0.10, 0.11), DARK, Vector3(0, -0.092, -0.065))
	m.register_moving(mag, "magazine", Vector3(0, -0.16, 0.03))
	_front_sight(m, -0.96, 0.085, 0.035)
	_cyl(m, 0.030, 0.03, BRASS, Vector3(0, 0.05, -1.072))
	_cyl(m, 0.019, 0.012, DARK, Vector3(0, 0.05, -1.092))

static func _launcher(m: WeaponModel) -> void:
	for i in 6:
		var angle := TAU * float(i) / 6.0
		_cyl(m, 0.038, 0.13, BRASS.darkened(0.25), Vector3(cos(angle) * 0.12, -0.05 + sin(angle) * 0.12, 0.035))
		_cyl(m, 0.027, 0.012, Ink.CINNABAR, Vector3(cos(angle) * 0.12, -0.05 + sin(angle) * 0.12, 0.107))
	_cyl(m, 0.083, 0.012, DARK, Vector3(0, 0.04, -0.646))
	for i in 5:
		_box(m, Vector3(0.12, 0.007, 0.012), BRASS, Vector3(0, 0.095, -0.28 - i * 0.05))
	# A skeletal ladder sight is deliberately offset from the ADS centre.
	for side in [-1, 1]:
		_box(m, Vector3(0.009, 0.17, 0.014), STEEL, Vector3(0.12 + side * 0.04, 0.17, -0.20))
	for i in 4:
		_box(m, Vector3(0.09, 0.007, 0.014), BRASS, Vector3(0.12, 0.105 + i * 0.045, -0.20))
	var latch := _box(m, Vector3(0.025, 0.050, 0.10), STEEL, Vector3(0.17, 0.01, 0.04))
	m.register_moving(latch, "magazine", Vector3(0.10, -0.08, 0))

static func _crossbow(m: WeaponModel) -> void:
	for side in [-1, 1]:
		_cyl(m, 0.052, 0.025, BRASS, Vector3(side * 0.43, 0.075, 0.16), Vector3.ZERO)
		_cyl(m, 0.027, 0.030, DARK, Vector3(side * 0.43, 0.076, 0.16), Vector3.ZERO)
		# Laminated bow limb seam and bronze limb attachment.
		_box(m, Vector3(0.36, 0.007, 0.014), JADE, Vector3(side * 0.24, 0.085, 0.08), Vector3(0, side * -22, side * -6))
		_box(m, Vector3(0.045, 0.08, 0.11), BRASS, Vector3(side * 0.09, 0.04, 0.03))
		for i in 4:
			_box(m, Vector3(0.007, 0.035, 0.07), BRASS, Vector3(side * (0.19 + i * 0.055), 0.065, 0.08 + i * 0.02), Vector3(0, side * -22, 0))
	for i in 3:
		_box(m, Vector3(0.065, 0.045, 0.012), Ink.PAPER, Vector3(0, 0.08, -0.04 + i * 0.055), Vector3(0, 0, 45))
	var carriage := _box(m, Vector3(0.08, 0.035, 0.065), STEEL, Vector3(0, 0.075, 0.14))
	m.register_moving(carriage, "bolt", Vector3(0, 0, -0.18))
	_front_sight(m, -0.52, 0.095, 0.045)

static func _hands(m: WeaponModel, id: String) -> void:
	# Layered sleeves, fingerless gloves and articulated fingers give scale.
	for hand_index in 2:
		var hand := Node3D.new()
		hand.name = "TriggerHand" if hand_index == 0 else "SupportHand"
		var left := hand_index == 1
		hand.position = Vector3(-0.032 if left else 0.035, -0.155 if left else -0.18, -0.28 if left else 0.095)
		if id == "brush_pistol" and left:
			hand.position = Vector3(-0.065, -0.20, 0.065)
		hand.rotation_degrees.z = -20 if left else 12
		m.add_child(hand)
		var palm := m._part(Ink.box_mesh(Vector3(0.085, 0.105, 0.09)), GLOVE, Vector3.ZERO, Vector3.ZERO, {"outline": 0.0018})
		palm.reparent(hand, false)
		var cuff := m._part(Ink.cylinder_mesh(0.06, 0.07, 0.16, 10), Ink.PLAYER_COAT, Vector3(0, -0.115, 0.035), Vector3(-24, 0, 0), {"outline": 0.002})
		cuff.reparent(hand, false)
		for i in 4:
			var finger := m._part(Ink.capsule_mesh(0.013, 0.069, 8, 3), Color("8b8171"), Vector3(-0.028 + i * 0.018, 0.025, -0.045), Vector3(65, 0, 0), {"outline": 0.001})
			finger.reparent(hand, false)
			var seam := _box(m, Vector3(0.004, 0.043, 0.005), STEEL.darkened(0.3), Vector3(-0.025 + i * 0.017, 0, 0.048))
			seam.reparent(hand, false)
		var thumb := m._part(Ink.capsule_mesh(0.017, 0.070, 8, 3), GLOVE, Vector3(0.042 if left else -0.042, 0.025, -0.01), Vector3(40, 0, -35 if left else 35), {"outline": 0.0015})
		thumb.reparent(hand, false)
		if left:
			m.support_hand = hand
			m.support_origin = hand.position
