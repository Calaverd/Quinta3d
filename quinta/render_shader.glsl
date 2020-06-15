#define PI 3.14159265359
#define MAX_LIGHT_NUMBER 10

uniform mat4 Model_Matrix;      //The position, rotation and scale of the model
uniform mat4 Model_Rot_Matrix;  //Only the rotation, need for the ambient shadows
//uniform mat4 Model_View_Matrix; //The position and rotation of the camera 
//uniform mat4 Projection_Matrix; //The Matrix proyection of the camera
uniform mat4 MVP; //Model_View_Matrix * Projection_Matrix
//uniform vec3 camPos;

uniform bool use_vertex_color = bool(0); 
uniform bool use_fog = bool(0); 

//ambient definitions
uniform vec3 AmbientRGB =  vec3(1.0); //vec3(0.8);//vec3(0.05,0.0,0.15);
uniform vec3 AmbientVector = vec3(0.0,0.0,1.0);
//light definitions 
uniform int num_lights = 0;
uniform vec3 lightPos[MAX_LIGHT_NUMBER];
//uniform vec3 lightRGB[MAX_LIGHT_NUMBER];
//uniform float lightR[MAX_LIGHT_NUMBER];

//uniform bool use_animation = bool(0);
//uniform mat4 matrix_pose[100];

uniform float offset_d;
uniform Image distortion_map;
uniform vec2  texture_size;

varying vec3 vposition;
varying vec3 unchanged_vposition;
varying vec3 face_normal;

#ifdef VERTEX
    attribute vec4 VertexWeight;
    attribute vec4 VertexBone;
    attribute vec3 VertexNormal;

    
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vec4 newVertex = vertex_position;
        face_normal = normalize(( NormalMatrix * VertexNormal).xyz); 
        vposition = (Model_Matrix*vertex_position).xyz;
        unchanged_vposition = (Model_Rot_Matrix * vertex_position).xyz;

        return MVP * Model_Matrix * vec4(newVertex.xyz, 1.0);
    }

#endif

#ifdef PIXEL
    vec3 faceNormals(vec3 pos) {
        vec3 fdx = dFdx(pos);
        vec3 fdy = dFdy(pos);
        return normalize(cross(fdx, fdy));
        }
    
    float attenuationCalc(float radio, float distance) {
        float p = 1.0-(min(distance,radio))/radio;
        return max(p,0.0);
        //float attenuation = (p) * sin(p*(PI / 2));
        //return max(attenuation, 0.0);
        }
    
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 obj_color = color;
        if (!use_vertex_color){ //use the texture color
            //texture_coords.x = 1.0-texture_coords.x;
            vec2 new_textcords = vec2(offset_d+texture_coords.y,offset_d+texture_coords.x);
            vec4 distortion_color = Texel(distortion_map,new_textcords);
            float delta = (1.0-distortion_color.r*2.0)*1.25;
            vec2 position = texture_coords * texture_size;
            position.x += delta;
            position.y -= delta;
            texture_coords = position/texture_size;
            obj_color = color*Texel(texture, texture_coords);
            if (obj_color.a == 0.0) discard;
        }

        /*
        float Kd = 2.2; //Diffuse reflectivity
        float Ka = 1.0; //Ambient reflectivity
        float Ks = 0.75; //specular reflectivity (how metal it looks)
        float Ksh = 1.8; //material Shininess

        //calculate the lightless color for the object
        vec3 ambient_light_normal = normalize(AmbientVector);
        vec3 untranslated_normal = normalize(unchanged_vposition);
        //untranslated_normal.z = -untranslated_normal.z;
        float ambient_shadows = 0.5-(dot(-untranslated_normal,ambient_light_normal)*0.5);
        
        vec3 lightless_color = vec3(0.0);

        if (use_fog)
            lightless_color = AmbientRGB*ambient_shadows + obj_color.rgb*0.1; 
        else
            lightless_color = (AmbientRGB*Ka)*ambient_shadows*obj_color.rgb; 

        vec3 endRGB = lightless_color;
        
        //calculate the effect of the lights...
        for(int i = 0; i < num_lights; i++){
            vec3 light_pos_to_model = (Model_Matrix * vec4( lightPos[i], 1.0 )  ).xyz;
            vec3 light_normal = normalize(light_pos_to_model);
            //light_normal.z = -light_normal.z;
            vec3 nfn = face_normal;
            if (light_pos_to_model.z > 0)
                nfn.z = -nfn.z;
            // I'm as confused as you about why this works 
            float distance = length(vec4(-lightPos[i].x,-lightPos[i].y,lightPos[i].z,1.0).xyz-vposition);
            
            float facedot = dot(nfn, -light_normal);                 //smoothed faces
            //float b = 1.0-clamp(dot(faceNormals(vposition),light_normal),0.0,1.0); //hard faces
            
            float radio = 15.0;
            
            float attenuation = attenuationCalc(radio,distance);
            //the behaibour of the color inside the light radio...
            vec3 light_rgb = vec3(1.0);//vec3(0.96,0.8,0.4);
            vec3 composite_color = vec3(obj_color)*light_rgb*Kd*(abs(facedot)*attenuation)*1.0;
            vec3 blend_color = mix( lightless_color, composite_color, attenuation);
            vec3 spec = vec3(0.0);
            if (facedot >= 0.0){
                composite_color += vec3(obj_color)*max(pow(attenuation,abs(facedot)),0.0);
                vec3 v = normalize( vec3(Model_Matrix * vec4( camPos.x,camPos.y,-camPos.z, 1.0 )  ));
                vec3 r = reflect(-nfn, light_normal);
                
                spec = vec3(obj_color)*light_rgb*Ks*pow(max( dot(r,v), 0.0),Ksh);
                //return vec4( spec,1.0);
                composite_color += spec;
                blend_color = mix( lightless_color, composite_color, attenuation);
                endRGB = mix(endRGB,blend_color,attenuation);
                }
            else{
                endRGB = mix( endRGB, blend_color, 1.0-attenuation);
                }
            }
        return vec4( endRGB ,obj_color.a);
        */
        return vec4( obj_color);
        }
#endif