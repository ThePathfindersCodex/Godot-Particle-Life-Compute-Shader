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
	# Use startup settings - consider refactor locking logic for %CheckBoxLockMatrix
	point_count = start_point_count
	if (species_count != start_species_count && !%CheckBoxLockMatrix.disabled && %CheckBoxLockMatrix.button_pressed):
		%CheckBoxLockMatrix.button_pressed = false
	species_count = start_species_count

	# Create playfield
	var start_data : Dictionary = {}
	match starting_method:
		0: start_data = StartupManager.build_particles(self, StartupManager.pos_random, false)
		1: start_data = StartupManager.build_particles(self, StartupManager.pos_ring, true)
		2: 
			StartupManager.setup_spiral_params(self)
			start_data = StartupManager.build_particles(self, StartupManager.pos_spiral, false)
		3: 
			StartupManager.setup_spiral_params(self)
			start_data = StartupManager.build_particles(self, StartupManager.pos_spiral, true)
		4: start_data = StartupManager.build_particles(self, StartupManager.pos_columns, false)
		5: start_data = StartupManager.build_particles(self, StartupManager.pos_columns, true)
		_: start_data = StartupManager.build_particles(self, StartupManager.pos_random, false)
	rebuild_buffers(start_data)

	# Unlock Checkbox
	%CheckBoxLockMatrix.disabled = false 

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
	var global_size_x : int = int(float(point_count) / shader_local_size) + 1
	var global_size_y : int = 1
	
	# but use 2 dimensions for image size during CLEAR stage 
	if (run_mode == 1) :
		global_size_x = image_size
		global_size_y = image_size
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

	# PUSH CONSTANT PARAMETERS
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
