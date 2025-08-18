extends Node
class_name ParticleBuilder

# MAIN BUILD FUNCTION
func build_particles(owner_node, pos_func: Callable, use_symmetric_matrix: bool) -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()
	
	for i in range(owner_node.point_count):
		var s = i % owner_node.species_count
		pos.append(pos_func.call(owner_node, i, s))
		vel.append(Vector2.ZERO)
		species.append(s)

	if (owner_node.get_node("%CheckBoxLockMatrix").disabled || !owner_node.get_node("%CheckBoxLockMatrix").button_pressed):
		if use_symmetric_matrix:
			owner_node.interaction_matrix = generate_matrix_symmetric(owner_node.species_count, owner_node.rand_start_interaction_range)
		else:
			owner_node.interaction_matrix = generate_matrix_random(owner_node.species_count, owner_node.rand_start_interaction_range)
	
	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": owner_node.interaction_matrix
	}

# RANDOM OR SYMMETRICAL INTERACTION FORCES
func generate_matrix_random(count: int, force_range: float) -> PackedFloat32Array:
	var matrix := PackedFloat32Array()
	for i in range(count * count):
		matrix.append(randf_range(-force_range, force_range))
	return matrix
	
func generate_matrix_symmetric(count: int, force_range: float) -> PackedFloat32Array:
	var tmp = []
	for i in range(count):
		tmp.append([])
		for j in range(count):
			if j < i:
				tmp[i].append(tmp[j][i])
			else:
				tmp[i].append(randf_range(-force_range, force_range))
	var matrix := PackedFloat32Array()
	for i in range(count):
		for j in range(count):
			matrix.append(tmp[i][j])
	return matrix

# PARTICLE POSITIONS
func pos_random(owner_node, _i:int, _s:int) -> Vector2:
	var radius = (owner_node.image_size * owner_node.rand_start_radius_mul) * 0.5
	return Vector2(randf_range(-radius, radius), randf_range(-radius, radius))

func pos_ring(owner_node, i:int, _s:int) -> Vector2:
	var center = Vector2.ZERO
	var radius = min(owner_node.image_size, owner_node.image_size) * owner_node.rand_start_radius_mul * 0.25
	var angle = (TAU / owner_node.point_count) * i
	return center + Vector2(cos(angle), sin(angle)) * radius

func pos_columns(owner_node, _i:int, s:int) -> Vector2:
	var band_width = owner_node.image_size / float(owner_node.species_count) * owner_node.rand_start_radius_mul
	var half_width = (band_width * owner_node.species_count) * 0.5
	var x_min = s * band_width
	var x_max = (s + 1) * band_width
	var x = randf_range(x_min, x_max) - half_width
	var y = randf_range(0.0, owner_node.image_size) - owner_node.image_size * 0.5
	return Vector2(x, y)
	
func pos_spiral(owner_node, i:int, _s:int) -> Vector2:
	var arm_index = i % spiral_arms
	var arm_angle = (TAU / spiral_arms) * arm_index
	var t = float(i) / owner_node.point_count
	var radius = t * spiral_max_radius
	var angle = spiral_turns * (radius / spiral_max_radius) * TAU + arm_angle + spiral_base_angle
	angle += randf_range(-spiral_arm_spread, spiral_arm_spread)
	radius += randf_range(-spiral_arm_spread * spiral_max_radius, spiral_arm_spread * spiral_max_radius)
	return spiral_center + Vector2(cos(angle), sin(angle)) * radius
	
# Spiral parameters when needed
var spiral_center = Vector2.ZERO
var spiral_max_radius = 0.0
var spiral_arms = 4
var spiral_turns = 3.0
var spiral_arm_spread = 0.015
var spiral_base_angle = 0.0
func setup_spiral_params(owner_node):
	spiral_center = Vector2.ZERO
	spiral_max_radius = min(owner_node.image_size, owner_node.image_size) * owner_node.rand_start_radius_mul * 0.5
	spiral_arms = 4
	spiral_turns = 3.0
	spiral_arm_spread = 0.015
	spiral_base_angle = randf() * TAU  # only once per restart
