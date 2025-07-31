extends Node2D

var slider_bindings = {
	"%SliderSpeed": "dt",
	"%SliderDampen": "damping",
	"%SliderSenseRadius": "interaction_radius",
	"%SliderForceSoftenMultiplier": "force_softening_mul",
	"%SliderMaxVelocityMultiplier": "max_velocity_mul",
	"%SliderDrawSize": "draw_radius",
	"%SliderCollideModifier": "collision_modifier",
	"%SliderCollideStr": "collision_strength",
	"%SliderCenterPull": "center_attraction",
	"%SliderMaxForce": "max_force",
	"%SliderBorderStyle": "border_style",
	"%SliderBorderScale": "border_size_scale"
}

func _ready():
	# Connect all sliders
	for slider_path in slider_bindings.keys():
		var slider = get_node(slider_path)
		var property = slider_bindings[slider_path]
		slider.value = %ComputeParticleLife.get(property)
		slider.connect("value_changed", Callable(self, "_on_slider_changed").bind(property))
	
	# Control defaults
	%SliderSpeed.value = %ComputeParticleLife.dt
	%SliderDampen.value = %ComputeParticleLife.damping
	%SliderSenseRadius.value = %ComputeParticleLife.interaction_radius
	%SliderForceSoftenMultiplier.value = %ComputeParticleLife.force_softening_mul
	%SliderMaxVelocityMultiplier.value = %ComputeParticleLife.max_velocity_mul
	%SliderDrawSize.value = %ComputeParticleLife.draw_radius
	%SliderCollideModifier.value = %ComputeParticleLife.collision_modifier
	%SliderCollideStr.value = %ComputeParticleLife.collision_strength
	%SliderCenterPull.value = %ComputeParticleLife.center_attraction
	%SliderMaxForce.value = %ComputeParticleLife.max_force
	%SliderBorderStyle.value = %ComputeParticleLife.border_style
	%SliderBorderScale.value = %ComputeParticleLife.border_size_scale
	
	%OptionStartInteractionRange.selected = int(%ComputeParticleLife.rand_start_interaction_range)
	%OptionStartRadiusMultiplier.selected =  int(%ComputeParticleLife.rand_start_radius_mul)
	%OptionStartSpeciesCount.selected = %ComputeParticleLife.start_species_count
	%OptionStartPointCount.selected = 3

func _process(_delta):
	# SET READOUT TEXT
	%LabelReadoutValues.text = "\n" + \
	str(snapped(%ComputeParticleLife.point_count,1))+"\n"+ \
	str(snapped(%ComputeParticleLife.species_count,1))+"\n"+ \
	str(snapped(%ComputeParticleLife.dt,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.damping,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.interaction_radius,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.force_softening_mul,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.force_softening,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.max_velocity_mul,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.max_velocity,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.draw_radius,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.collision_modifier,.1))+"\n"+ \
	str(snapped(%ComputeParticleLife.collision_radius,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.collision_strength,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.border_style,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.border_size_scale,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.center_attraction,.01))+"\n"+ \
	str(snapped(%ComputeParticleLife.max_force,.01))+"\n"+ \
	"("+str(snapped(%ComputeParticleLife.camera_center.x,.1))+ ", " + str(snapped(%ComputeParticleLife.camera_center.y,.1)) + ")"+"\n"+ \
	str(snapped(%ComputeParticleLife.zoom,.01))+"\n"

	# SET INTERACTION MATRIX TEXT
	var species_count = %ComputeParticleLife.species_count
	var interaction_matrix = %ComputeParticleLife.interaction_matrix
	var lines := []
	for i in range(species_count):
		var line = str(i + 1) + ": "
		for j in range(species_count):
			var val = snapped(interaction_matrix[i * species_count + j], 0.01)
			line += "%5.2f" % val
			if j < species_count - 1:
				line += " | "
		lines.append(line)
	%LabelIntMatrix.text = "INTERACTION MATRIX\n\n" + "\n".join(lines)

	# HANDLE PAUSE/RESUME
	if Input.is_action_just_pressed("pause_resume"):
		pause_resume()

func pause_resume():
	if %ComputeParticleLife.dt == 0.0:
		%ComputeParticleLife.dt = %ComputeParticleLife.paused_dt  # resume
		%ButtonPauseResume.text = "PAUSE"
	else:
		%ComputeParticleLife.paused_dt = %ComputeParticleLife.dt  # store current
		%ComputeParticleLife.dt = 0.0       # pause
		%ButtonPauseResume.text = "RESUME"

func _on_slider_changed(value: float, property: String):
	%ComputeParticleLife.set(property, value)

func _on_button_restart_pressed() -> void:
	%ComputeParticleLife.restart_simulation()

func _on_button_pause_resume_pressed() -> void:
	pause_resume()

func _on_option_start_method_item_selected(index: int) -> void:
	%ComputeParticleLife.starting_method=index

func _on_option_start_interaction_range_item_selected(index: int) -> void:
	%ComputeParticleLife.rand_start_interaction_range=index

func _on_option_start_radius_multiplier_item_selected(index: int) -> void:
	%ComputeParticleLife.rand_start_radius_mul=index

func _on_option_start_point_count_item_selected(index: int) -> void:
	%ComputeParticleLife.start_point_count=int(%OptionStartPointCount.get_item_text(index))

func _on_option_start_species_count_item_selected(index: int) -> void:
	%ComputeParticleLife.start_species_count=index
	
	%CheckBoxLockMatrix.disabled=false
	if (%ComputeParticleLife.start_species_count != %ComputeParticleLife.species_count):
			%CheckBoxLockMatrix.disabled=true
