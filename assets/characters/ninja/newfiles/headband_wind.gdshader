shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.6;
uniform float wind_speed : hint_range(0.0, 10.0) = 4.0;
void vertex() {
 float t = clamp(-VERTEX.z / 0.45, 0.0, 1.0);
 float phase = TIME * wind_speed - t * 8.0 + VERTEX.x * 12.0;
 VERTEX.y += wind_strength * 0.05 * t * t * sin(phase);
 VERTEX.x += wind_strength * 0.025 * t * t * sin(phase * 0.73);
}
void fragment() {
 ALBEDO = texture(albedo_map, UV).rgb;
 ROUGHNESS = 0.92;
 NORMAL_MAP = texture(normal_map, UV).rgb;
}
