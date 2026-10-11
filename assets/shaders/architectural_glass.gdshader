shader_type spatial;
uniform float night = 0.0;
varying vec3 world_position;
varying float pane_seed;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 vec3 origin = MODEL_MATRIX[3].xyz;
 pane_seed = fract(sin(dot(origin, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}
void fragment() {
 // Glass remains opaque for stable depth and correct occlusion of closed buildings.
 float edge = min(min(UV.x, 1.0-UV.x), min(UV.y, 1.0-UV.y));
 vec2 room_uv = UV + VIEW.xy / max(abs(VIEW.z), 0.4) * 0.08;
 float room = step(0.09, room_uv.x)*step(room_uv.x,0.91)*step(0.12,room_uv.y)*step(room_uv.y,0.88);
 float blind = step(pane_seed, 0.42) * step(UV.y, 0.25+pane_seed);
 float slats = 0.87 + 0.13*smoothstep(0.3,0.7,fract(UV.y*25.0));
 vec3 interior = mix(vec3(0.025,0.038,0.043),vec3(0.10,0.12,0.115),pane_seed);
 ALBEDO = mix(interior*mix(0.55,1.0,room),vec3(0.31,0.30,0.265)*slats,blind*0.75);
 ALBEDO *= smoothstep(0.0, 0.025, edge)*0.25+0.75;
 METALLIC = 0.32;
 SPECULAR = 0.8;
 ROUGHNESS = 0.16 + blind*0.16 + pane_seed*0.065;
 EMISSION = vec3(1.0,0.72,0.40)*night*step(0.76,pane_seed)*room*0.42;
}
