extends TextureRect

# CONFIG
var shader_local_size := 512
#var image_size : int = 800
@onready var image_size : int = %ComputeParticleLife.size.x
var point_count : int = 1024*15
var species_count : int = 8

# STARTUP PARAMS
var rand_start_interaction_range : float = 2.0  # force will be random between -X and +X
var rand_start_radius_mul : float = 2.0 # different startup patterns use this multiplier
var start_point_count : int = point_count # only used when restarting new field
var start_species_count : int = species_count # only used when restarting new field
var starting_method : int = 2 # which method to use when restarting new field?

# SPEED/TIME
var dt : float = .25
var paused_dt : float = dt # only used for pause/resume feature

# PARTICLE SIZE
var draw_radius : float = 3.0
var interaction_radius : float = 50.0

# COLLISION FORCE
var collision_modifier : float = 0.5
var collision_radius : float =  draw_radius + collision_modifier:
	get():
		return draw_radius + collision_modifier
var collision_strength : float = 10.0 # 20.0 # 30.0 # 15.0 # 4.0 #2.0 # 5.0 # 10.0 # 0.0

# BORDER STYLE (optional)
var border_style : float = 0.0 # 0 no boundary, 1 bounded rectangle, 2 bounded circle, 3 bouncy rectangle, 4 bouncy circle
var border_size_scale : float = 1.0 # scaled from image_size

# CENTER FORCE (optional)
var center_attraction : float = 0.0 # 0.1 #0.28 #0.35 # 0.01 # # set to 0 to turn off

# FORCE ADJUSTMENTS
var damping : float = 0.95 #1.0 # 0.85 #0.99 # FRICTION
var max_force : float = 500.0 # 13.0 # 3.0 #0.1 # 20.0 # 5.0 # 0.0 to 5.0
var force_softening_mul : float = 0.05
var max_velocity_mul : float = 0.25
var force_softening : float = interaction_radius * force_softening_mul:
	get():
		return interaction_radius * force_softening_mul

var max_velocity : float = interaction_radius * max_velocity_mul:
	get():
		return interaction_radius * max_velocity_mul

# CAMERA
var camera_center : Vector2 = Vector2.ZERO
var zoom : float = 0.82 # 0.52 # 0.16 # 0.24 #0.16 # 0.34 # 0.21 # 0.6
const MIN_ZOOM := 0.1
const MAX_ZOOM := 5.0

# INTERACTION MATRIX
var interaction_matrix : PackedFloat32Array = []

# RENDERER SETUP
var rd := RenderingServer.create_local_rendering_device()
var shader : RID
var pipeline : RID
var uniform_set : RID
var output_tex : RID
var fmt := RDTextureFormat.new()
var view := RDTextureView.new()
var buffers : Array[RID] = []
var uniforms : Array[RDUniform] = []
var output_tex_uniform : RDUniform

func _ready():
	randomize()
	fmt.width = image_size
	fmt.height = image_size
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
					| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
					| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
					| RenderingDevice.TEXTURE_USAGE_CPU_READ_BIT
	view = RDTextureView.new()
	restart_simulation()

func restart_simulation():
	# Use startup settings - consider refactor logic for %CheckBoxLockMatrix
	point_count = start_point_count
	if (species_count != start_species_count && !%CheckBoxLockMatrix.disabled && %CheckBoxLockMatrix.button_pressed):
		%CheckBoxLockMatrix.button_pressed = false
	species_count = start_species_count

	# Create playfield
	var start_data : Dictionary = {}
	match starting_method:
		0: start_data = build_starting_particles()
		1: start_data = build_starting_particles_symmetric()
		2: start_data = build_starting_particles_spiral()
		3: start_data = build_starting_particles_spiral_symmetric()
		4: start_data = build_starting_particles_columns()
		5: start_data = build_starting_particles_columns_symmetric()
		_: start_data = build_starting_particles()
	rebuild_buffers(start_data)

	%CheckBoxLockMatrix.disabled=false

func generate_matrix_random(count: int, range: float) -> PackedFloat32Array:
	var matrix := PackedFloat32Array()
	for i in range(count * count):
		matrix.append(randf_range(-range, range))
	return matrix

func generate_matrix_symmetric(count: int, range: float) -> PackedFloat32Array:
	var tmp = []
	for i in range(count):
		tmp.append([])
		for j in range(count):
			if j < i:
				tmp[i].append(tmp[j][i])
			else:
				tmp[i].append(randf_range(-range, range))
	var matrix := PackedFloat32Array()
	for i in range(count):
		for j in range(count):
			matrix.append(tmp[i][j])
	return matrix

func build_starting_particles() -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()
	var radius = (image_size * rand_start_radius_mul) * 0.5

	for i in range(point_count):
		var p = Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
		var v =  Vector2.ZERO
		var s = randi() % species_count
		
		pos.append(p)
		vel.append(v)
		species.append(s)

	# Create random interaction matrix
	if (%CheckBoxLockMatrix.disabled || !%CheckBoxLockMatrix.button_pressed):
		interaction_matrix = generate_matrix_random(species_count, rand_start_interaction_range)

	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": interaction_matrix
	}

func build_starting_particles_symmetric() -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()

	# Arrange points in symmetrical patterns (rings)
	var center = Vector2.ZERO
	var radius = min(image_size, image_size) * rand_start_radius_mul * 0.5
	for i in range(point_count):
		var angle = (TAU / point_count) * i
		var p = center + Vector2(cos(angle), sin(angle)) * radius
		var v = Vector2.ZERO
		var s = i % species_count
		
		pos.append(p)
		vel.append(v)
		species.append(s)

	# Create symmetric interaction matrix
	if (%CheckBoxLockMatrix.disabled || !%CheckBoxLockMatrix.button_pressed):
		interaction_matrix = generate_matrix_symmetric(species_count, rand_start_interaction_range)

	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": interaction_matrix
	}

func build_starting_particles_spiral() -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()

	# Spiral parameters
	var center = Vector2.ZERO
	var max_radius = min(image_size, image_size) * rand_start_radius_mul * 0.5
	var arms = 4                               # number of spiral arms
	var turns = 3.0                            # number of spiral rotations
	var arm_spread = 0.015                      # randomness factor to spread points from exact spiral
	var base_angle = randf() * TAU             # random rotation offset

	for i in range(point_count):
		var arm_index = i % arms
		var arm_angle = (TAU / arms) * arm_index

		# Radius from 0 to max_radius
		var t = float(i) / point_count
		var radius = t * max_radius

		# Spiral angle = number of turns * radius proportion + arm offset
		var angle = turns * (radius / max_radius) * TAU + arm_angle + base_angle

		# Apply some random spread
		angle += randf_range(-arm_spread, arm_spread)
		radius += randf_range(-arm_spread * max_radius, arm_spread * max_radius)

		var p = center + Vector2(cos(angle), sin(angle)) * radius
		var v = Vector2.ZERO
		var s = i % species_count

		pos.append(p)
		vel.append(v)
		species.append(s)

	# Build fully random interaction matrix (no symmetry)
	if (%CheckBoxLockMatrix.disabled || !%CheckBoxLockMatrix.button_pressed):
		interaction_matrix = generate_matrix_random(species_count, rand_start_interaction_range)

	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": interaction_matrix
	}

func build_starting_particles_spiral_symmetric() -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()

	# Spiral parameters
	var center = Vector2.ZERO
	var max_radius = min(image_size, image_size) * rand_start_radius_mul * 0.5
	var arms = 4                               # number of spiral arms
	var turns = 3.0                            # number of spiral rotations
	var arm_spread = 0.015                      # randomness factor to spread points from exact spiral
	var base_angle = randf() * TAU             # random rotation offset

	for i in range(point_count):
		var arm_index = i % arms
		var arm_angle = (TAU / arms) * arm_index

		# Radius from 0 to max_radius
		var t = float(i) / point_count
		var radius = t * max_radius

		# Spiral angle = number of turns * radius proportion + arm offset
		var angle = turns * (radius / max_radius) * TAU + arm_angle + base_angle

		# Apply some random spread
		angle += randf_range(-arm_spread, arm_spread)
		radius += randf_range(-arm_spread * max_radius, arm_spread * max_radius)

		var p = center + Vector2(cos(angle), sin(angle)) * radius
		var v = Vector2.ZERO
		var s = i % species_count

		pos.append(p)
		vel.append(v)
		species.append(s)

	# Build symmetric interaction matrix
	if (%CheckBoxLockMatrix.disabled || !%CheckBoxLockMatrix.button_pressed):
		interaction_matrix = generate_matrix_symmetric(species_count, rand_start_interaction_range)

	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": interaction_matrix
	}

func build_starting_particles_columns() -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()
	
	var band_width = image_size / float(species_count) * rand_start_radius_mul # Width of each vertical band
	var half_width = (band_width * species_count) * 0.5
	
	for i in range(point_count):
		var s = i % species_count  # Species index
		var x_min = s * band_width
		var x_max = (s + 1) * band_width
		
		# Random X inside species band
		var x = randf_range(x_min, x_max)
		# Random Y across full height
		var y = randf_range(0.0, image_size)
		
		# Center coordinates around (0,0)
		x -= half_width
		y -= image_size * 0.5
		
		pos.append(Vector2(x, y))
		vel.append(Vector2.ZERO)
		species.append(s)
	
	# Build fully random interaction matrix (non-symmetric)
	if (%CheckBoxLockMatrix.disabled || !%CheckBoxLockMatrix.button_pressed):
		interaction_matrix = generate_matrix_random(species_count, rand_start_interaction_range)
	
	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": interaction_matrix
	}

func build_starting_particles_columns_symmetric() -> Dictionary:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var species := PackedInt32Array()
	
	var band_width = image_size / float(species_count) * rand_start_radius_mul # Width of each vertical band
	var half_width = (band_width * species_count) * 0.5
	
	for i in range(point_count):
		var s = i % species_count  # Species index
		var x_min = s * band_width
		var x_max = (s + 1) * band_width
		
		# Random X inside species band
		var x = randf_range(x_min, x_max)
		# Random Y across full height
		var y = randf_range(0.0, image_size)
		
		# Center coordinates around (0,0)
		x -= half_width
		y -= image_size * 0.5
		
		pos.append(Vector2(x, y))
		vel.append(Vector2.ZERO)
		species.append(s)
	
	# Build symmetric interaction matrix
	if (%CheckBoxLockMatrix.disabled || !%CheckBoxLockMatrix.button_pressed):
		interaction_matrix = generate_matrix_symmetric(species_count, rand_start_interaction_range)
	
	return {
		"pos": pos,
		"vel": vel,
		"species": species,
		"interaction_matrix": interaction_matrix
	}

func rebuild_buffers(data: Dictionary):
	buffers.clear()
	uniforms.clear()

	var pos_bytes :PackedByteArray= data["pos"].to_byte_array()
	var vel_bytes :PackedByteArray= data["vel"].to_byte_array()
	var species_bytes :PackedByteArray= data["species"].to_byte_array()
	var interaction_bytes :PackedByteArray= data["interaction_matrix"].to_byte_array()

	# IN BUFFERS
	buffers.append(rd.storage_buffer_create(pos_bytes.size(), pos_bytes))      # 0
	buffers.append(rd.storage_buffer_create(vel_bytes.size(), vel_bytes))      # 1
	buffers.append(rd.storage_buffer_create(species_bytes.size(), species_bytes))  # 2

	# OUT BUFFERS (copy of input)
	for b in [pos_bytes, vel_bytes]:
		buffers.append(rd.storage_buffer_create(b.size(), b))  # 3, 4

	# Interaction Matrix
	buffers.append(rd.storage_buffer_create(interaction_bytes.size(), interaction_bytes))  # 5

	# Output texture
	var output_img := Image.create(image_size, image_size, false, Image.FORMAT_RGBAF)
	texture = ImageTexture.create_from_image(output_img)
	output_tex = rd.texture_create(fmt, view, [output_img.get_data()])

	# UNIFORMS
	for i in range(6):
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buffers[i])
		uniforms.append(u)

	# IMAGE TEXTURE OUTPUT
	output_tex_uniform = RDUniform.new()
	output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_uniform.binding = 6
	output_tex_uniform.add_id(output_tex)
	uniforms.append(output_tex_uniform)

	# SHADER + PIPELINE
	var shader_file := load("res://compute_particle_life.glsl") as RDShaderFile
	shader = rd.shader_create_from_spirv(shader_file.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	uniform_set = rd.uniform_set_create(uniforms, shader, 0)

func compute_stage(run_mode:int):
	# default to 1 dimension for particles
	var global_size_x = (point_count / shader_local_size) + 1
	var global_size_y = 1
	
	# but use 2 dimensions for image size during CLEAR stage 
	if (run_mode == 1) :
		global_size_x = image_size
		global_size_y = image_size
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

	var params := PackedFloat32Array([
		dt,
		damping,
		point_count,
		species_count,
		interaction_radius,
		draw_radius,
		collision_radius,
		collision_strength,
		border_style,
		border_size_scale,
		image_size,
		center_attraction,
		force_softening,
		max_force,
		max_velocity,
		camera_center.x,
		camera_center.y,
		zoom,
		run_mode,
		0.0 # padding to 4
	])
	var params_bytes := PackedByteArray()
	params_bytes.append_array(params.to_byte_array())

	rd.compute_list_set_push_constant(compute_list, params_bytes, params_bytes.size())
	rd.compute_list_dispatch(compute_list, global_size_x, global_size_y, 1) 
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _process(_delta):
	### RUN ALL COMPUTE STAGES
	for run_mode in [0, 1, 2]:  # 0 = simulate, 1 = clear, 2 = draw
		compute_stage(run_mode)

	### RESOLVE RESULTS — copy GPU output back into input buffers
	var output_bytes_pos = rd.buffer_get_data(buffers[3])  # out_pos_buffer
	var output_bytes_vel = rd.buffer_get_data(buffers[4])  # out_vel_buffer
	rd.buffer_update(buffers[0], 0, output_bytes_pos.size(), output_bytes_pos)  # in_pos_buffer
	rd.buffer_update(buffers[1], 0, output_bytes_vel.size(), output_bytes_vel)  # in_vel_buffer

	# UPDATE TEXTURE ON SCREEN
	var byte_data := rd.texture_get_data(output_tex, 0)
	var image := Image.create_from_data(image_size, image_size, false, Image.FORMAT_RGBAF, byte_data)
	texture.update(image)

# HANDLE MOUSE INPUTS
var dragging := false
var last_mouse_pos := Vector2()
func _gui_input(event):
	if event is InputEventMouseButton:
		# Handle zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom * 1.05, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom / 1.05, MIN_ZOOM, MAX_ZOOM)

		# Start/stop panning with right mouse button
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			last_mouse_pos = event.position

	elif event is InputEventMouseMotion and dragging:
		# Convert drag delta to world space based on zoom
		var delta :Vector2= (event.position - last_mouse_pos) / zoom
		last_mouse_pos = event.position
		camera_center -= delta
