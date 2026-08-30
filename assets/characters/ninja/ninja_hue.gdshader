// Recolours one shared character texture per player.
//
// A flat hue rotation would recolour the skin along with the armour, turning
// faces green. The texture's crimson accents sit at roughly hue 0.0 with
// saturation ~0.68, while skin sits at hue 0.07 saturation ~0.35 and the dark
// armour below 0.2 -- so saturation, not hue, is what separates them. Only
// pixels above the threshold are rotated, and the mask is feathered so the
// boundary does not alias into a hard edge.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform float hue_shift : hint_range(-1.0, 1.0) = 0.0;
uniform float saturation_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float saturation_feather : hint_range(0.005, 0.5) = 0.13;
uniform float saturation_gain : hint_range(0.5, 2.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.62;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
// Flashes the whole model on being hit. Cheaper and more legible than swapping
// materials, and it survives the hue shift untouched.
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	vec3 hsv = rgb_to_hsv(texel.rgb);

	float mask = smoothstep(
		saturation_threshold - saturation_feather,
		saturation_threshold + saturation_feather,
		hsv.y);

	hsv.x = fract(hsv.x + hue_shift * mask);
	hsv.y = clamp(hsv.y * mix(1.0, saturation_gain, mask), 0.0, 1.0);

	vec3 colour = hsv_to_rgb(hsv);
	ALBEDO = mix(colour, vec3(1.0), hit_flash);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = vec3(hit_flash * 0.6);
}
