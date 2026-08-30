// An afterimage: the ninja's silhouette, flat, in the player's colour.
//
// Not a translucent copy of the real material. Reusing the hue-rotation shader
// was the obvious first try and it came out as coloured noise: rgb_to_hsv gives
// an essentially random hue for near-grey pixels, which is harmless while the
// mask leaves them alone, and explodes the moment you raise saturation across
// the whole texture to make a dark ninja visible on a pale floor.
//
// A silhouette is also the better answer to what a decoy is for. It has to be
// read at a glance, mid-fight, as "a Jinsoku-coloured person standing there" --
// detail would only make it harder to tell from the real one at speed, which is
// the opposite of the job. The texture is used for shape and for a hint of
// internal shading, and nothing else.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, shadows_disabled, unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec3 ghost_color : source_color = vec3(0.4, 0.9, 1.0);
// Fades as the decoy runs out of time, so it reads as expiring rather than
// simply vanishing.
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	// Perceptual luminance, so the fabric folds and the sash still show through
	// as light and shade without carrying any of the texture's own hues.
	float shade = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));

	ALBEDO = ghost_color * mix(0.55, 1.35, shade);
	// Rim brightening: the silhouette's edge is what the eye actually catches
	// when four fighters are moving at once.
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	EMISSION = ghost_color * pow(rim, 2.0) * 0.9;
	ALPHA = ghost_alpha;
}
