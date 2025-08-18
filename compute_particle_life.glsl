#[compute]
#version 450
layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

struct MyVec2 { vec2 v; };

// Input
layout(set = 0, binding = 0, std430) buffer InPosBuffer     { MyVec2 data[]; } in_pos_buffer;
layout(set = 0, binding = 1, std430) buffer InVelBuffer     { MyVec2 data[]; } in_vel_buffer;
layout(set = 0, binding = 2, std430) buffer InSpeciesBuffer { int data[]; }   in_species_buffer;

// Output
layout(set = 0, binding = 3, std430) buffer OutPosBuffer    { MyVec2 data[]; } out_pos_buffer;
layout(set = 0, binding = 4, std430) buffer OutVelBuffer    { MyVec2 data[]; } out_vel_buffer;

// Interaction matrix (species_count x species_count)
layout(set = 0, binding = 5, std430) readonly buffer MatrixBuffer {
    float data[];
} interaction_matrix;

// Render target
layout(set = 0, binding = 6, rgba32f) uniform image2D OUTPUT_TEXTURE;

// Parameters
layout(push_constant, std430) uniform Params {
    float dt;
    float damping;
    float point_count;
    float species_count;
    float interaction_radius;
    float draw_radius;
	float collision_radius;
	float collision_strength;
	float border_style;
	float border_scale;
	float image_size;
	float center_attraction;
	float force_softening;
	float max_force;
	float max_velocity;
	float camera_center_x;
	float camera_center_y;
	float zoom;
    float run_mode;  // 0 = sim, 1 = draw
} params;

// Color generator per species // TODO: consider passing in colors as push constant parameter
vec3 species_color_custom(int species) {
    if (species == 0) return vec3(1.0, 0.0, 0.0); // Red
    if (species == 1) return vec3(0.0, 1.0, 0.0); // Green
    if (species == 2) return vec3(0.0, 0.0, 1.0); // Blue
    if (species == 3) return vec3(1.0, 1.0, 0.0); // Yellow
    if (species == 4) return vec3(1.0, 0.0, 1.0); // Purple
    if (species == 5) return vec3(0.0, 1.0, 1.0); // Lt Blue
    if (species == 6) return vec3(0.5, 0.5, 0.5); // Gray
	
    if (species == 7) return vec3(0.06, 0.64, 0.43); // Dr Green
    if (species == 8) return vec3(1.0, 0.65, 0.0); // Orange
    
	// last species
	return vec3(1.0); // White
}
vec3 heatmap_color(float t) {
    // Clamp between 0 and 1
    t = clamp(t, 0.0, 1.0);

    // Map t to blue to cyan to green to yellow to red
    if (t < 0.25) {
        // Blue to Cyan
        float k = t / 0.25;
        return mix(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), k);
    } else if (t < 0.5) {
        // Cyan to Green
        float k = (t - 0.25) / 0.25;
        return mix(vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), k);
    } else if (t < 0.75) {
        // Green to Yellow
        float k = (t - 0.5) / 0.25;
        return mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), k);
    } else {
        // Yellow to Red
        float k = (t - 0.75) / 0.25;
        return mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), k);
    }
}
vec3 species_color_dynamic(int species) {
    // Map species index to 0..1 range
    float t = float(species) / max(float(params.species_count - 1), 1.0);
    return heatmap_color(t);
}


// draw or erase circles
void draw_circle(vec2 center, float radius, vec4 color) {
    ivec2 min_pix = ivec2(floor(center - radius));
    ivec2 max_pix = ivec2(ceil(center + radius));
    for (int x = min_pix.x; x <= max_pix.x; x++) {
        for (int y = min_pix.y; y <= max_pix.y; y++) {
            vec2 p = vec2(x, y);
            if (length(p - center) <= radius) {
                imageStore(OUTPUT_TEXTURE, ivec2(x, y), color);
            }
        }
    }
}

// Apply a softened and capped force
float apply_force(float f, float dist, float softening, float max_force) {
    float softened_dist = sqrt(dist * dist + softening * softening);
    float force_mag = f / softened_dist;
	
    return clamp(force_mag, -max_force, max_force);
}

// Simple 2D hash to make a pseudo-random direction from particle IDs
vec2 random_dir(uint a, uint b) {
    uint seed = a * 1664525u + b * 1013904223u; // LCG mix
    float ang = float(seed % 6283u) * 0.001f;   // ~0 to ~2pi
    return vec2(cos(ang), sin(ang));
}

// Applies border constraints based on params.border_style and border_scale
void apply_border(inout vec2 pos, inout vec2 vel) {
    ivec2 size = imageSize(OUTPUT_TEXTURE);
    vec2 half_bounds = vec2(size) * 0.5 * params.border_scale;
    float radius = float(min(size.x, size.y)) * 0.5 - 1.0;

    if (params.border_style == 0.0) {
        // No border
        return;
    }

    if (params.border_style == 1.0) {
        // Square border (clamp)
        pos = clamp(pos, -half_bounds, half_bounds - vec2(1.0));
    }
	else if (params.border_style == 2.0) {
		// Circle border (clamp)
		float dist = length(pos);
		float scaled_radius = radius * params.border_scale;
		if (dist > scaled_radius) {
			pos = normalize(pos) * scaled_radius;
		}
	}
    else if (params.border_style == 3.0) {
        // Bouncy square border
        if (pos.x < -half_bounds.x) {
            pos.x = -half_bounds.x;
            vel.x *= -1.0;
        } else if (pos.x > half_bounds.x) {
            pos.x = half_bounds.x;
            vel.x *= -1.0;
        }
        if (pos.y < -half_bounds.y) {
            pos.y = -half_bounds.y;
            vel.y *= -1.0;
        } else if (pos.y > half_bounds.y) {
            pos.y = half_bounds.y;
            vel.y *= -1.0;
        }
    }
	else if (params.border_style == 4.0) {
		// Bouncy circle border
		float dist = length(pos);
		float scaled_radius = radius * params.border_scale;
		if (dist > scaled_radius) {
			vec2 normal = normalize(pos);
			pos = normal * scaled_radius;
			vel = reflect(vel, normal);
		}
	}
}

void run_sim() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= uint(params.point_count)) return;

    vec2 pos = in_pos_buffer.data[id].v;
    vec2 vel = in_vel_buffer.data[id].v;
    int species = in_species_buffer.data[id];

	// Calculate particle forces
    vec2 force = vec2(0.0);
    for (uint i = 0; i < uint(params.point_count); ++i) {
        if (i == id) continue;

        vec2 other_pos = in_pos_buffer.data[i].v;
        int other_species = in_species_buffer.data[i];
        vec2 r = other_pos - pos;
		float dist = length(r);
		
		if (dist > 0.0001) {
			vec2 dir = normalize(r);
			
			// Particle attraction/repulsion (with softening + clamp)
            if (dist < params.interaction_radius) {
                float f = interaction_matrix.data[species * uint(params.species_count) + other_species];
                force += dir * apply_force(f, dist, params.force_softening, params.max_force);
            }

            // Particle collision (with softening + clamp)
            float min_dist = params.collision_radius * 2.0;
            if (dist < min_dist) {
                float penetration = min_dist - dist;
                float f = penetration * params.collision_strength;
                force -= dir * apply_force(f, dist, params.force_softening, params.max_force); // inverted sign
            }
		} else {
			// in the exact same spot, so push apart in a random direction
			vec2 dir = random_dir(id, i);
			float f = params.collision_strength * params.collision_radius; // tiny force
			//force -= dir * f;
			force -= dir * apply_force(f, 0.001, params.force_softening, params.max_force);
		}
    }
	
	// Attraction to center
	if (params.center_attraction>0.0001) {
		vec2 center = vec2(0.0); //vec2(params.image_size/2.0,params.image_size/2.0);
		vec2 r_center = center - pos;
		float dist_center = length(r_center);
		vec2 dir_center = normalize(r_center);
		force += params.center_attraction * dir_center; // / dist_center;
	}

    // Integrate velocity
    vel += force * params.dt;
    vel *= params.damping;
	
    // Velocity clamp
	float speed = length(vel);
    if (speed > params.max_velocity) {
        vel = normalize(vel) * params.max_velocity;
    }
	
	// Move
    pos += vel * params.dt;
	
	// Boundary collision
	apply_border(pos, vel);

	// Output
    out_pos_buffer.data[id].v = pos;
    out_vel_buffer.data[id].v = vel;
}

void clear_texture() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    imageStore(OUTPUT_TEXTURE, pixel, vec4(vec3(0.1),1.0)); // slight off-black	
    //imageStore(OUTPUT_TEXTURE, pixel, vec4(0.0)); // transparent	
}

void draw_texture() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= uint(params.point_count)) return;

	vec2 curr_pos = out_pos_buffer.data[id].v;   // Current particles pos
	vec2 image_size_vec = vec2(params.image_size,params.image_size);
    int species = in_species_buffer.data[id];
	
	// Determine color
    vec3 color = species_color_dynamic(species);
    //vec3 color = species_color_custom(species);
	
    // Convert particle position into screen coordinates with zoom/pan
    vec2 rel = in_pos_buffer.data[id].v - vec2(params.camera_center_x,params.camera_center_y);
    rel *= params.zoom;
    vec2 screen_pos = rel + image_size_vec * 0.5;

    // Discard if outside image
    if (screen_pos.x < -params.draw_radius || screen_pos.x >= image_size_vec.x + params.draw_radius ||
        screen_pos.y < -params.draw_radius || screen_pos.y >= image_size_vec.y + params.draw_radius) {
        return;
    }

    // Draw a circle for the particle
	float draw_size = params.draw_radius * params.zoom;
    draw_circle(screen_pos, draw_size, vec4(color, 1.0));
}


void main() {
    if (params.run_mode == 0 && params.dt > 0.0) {
		//if (params.dt == 0.0) return;
        run_sim();
	} else if (params.run_mode == 1) {
        clear_texture();
    } else if (params.run_mode == 2) {
        draw_texture();
    }
	
	
}
