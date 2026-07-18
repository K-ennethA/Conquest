shader_type spatial;

uniform bool is_selected = false;
uniform vec3 original_color : source_color;

void fragment() {
	
    vec3 base_color = original_color;
    //vec3 base_color;

    if (is_selected) {
        // Blend original with blue, or just switch to blue
		base_color = vec3(0.0, 0.0, 1.0); // Blue

        //base_color = mix(base_color, vec3(0.0, 0.0, 1.0), 0.9);
        EMISSION = vec3(0.0, 0.0, 1.0); // glow effect
    } else {
        EMISSION = vec3(0.0);
    }

    ALBEDO = base_color;
}

//shader_type spatial;
//void fragment() {
    //ALBEDO = vec3(1.0, 0.0, 0.0); // bright red
//}