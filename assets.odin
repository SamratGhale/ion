package ion

import os "core:os" // to format path
import "core:strings"
import "core:fmt"
import "core:slice"
import rl "vendor:raylib"

to_cstring :: strings.unsafe_string_to_cstring

/**
    Loads all the files from asset_path as a seperate texture (i.e seperate texture)
    TODO: context allocator
		  do not load if the file is not a image
**/

asset_texture_init :: proc(asset_path: string) {
    dir, _    := os.open(asset_path)
    files , _ := os.read_dir(dir, 1000)

    for file in files{
	if file.is_dir {
	    asset_texture_init(file.fullpath)
	} else {
	    fullname := strings.split(file.name, ".")
	    name := fullname[0]
	    append(&game.asset_names, name)
	    game.assets[name] = make([dynamic]rl.Texture2D, 0)
	    new_tex := rl.LoadTexture(to_cstring(file.fullpath))
	    append(&game.assets[name], new_tex)
	}
    }
}

/**
    Creates key value for each folder inside the path 
    and adds the texture inside the folder to the key
    TODO: context allocator
**/

asset_texture_init_by_folder :: proc(asset_path: string) {
    dir, _    := os.open(asset_path)
    files , _ := os.read_dir(dir, 200)

    for file in files{
	if file.is_dir {
	    folder_handle, _ := os.open(file.fullpath)
	    pngs, _ := os.read_dir(folder_handle, 200)

	    game.assets[file.name] = make([dynamic]rl.Texture, 0)
	    for png in pngs {
		append(&game.asset_names, file.name)
		tex := rl.LoadTexture(to_cstring(png.fullpath))
		append(&game.assets[file.name], tex)
	    }
	}
    }
}

/*
    Takes in a asset path and key
    loads all the asset in the folder in the key
*/
asset_texture_init_in_folder:: proc(asset_path, key: string) {
    folder_handle, _ := os.open(asset_path)
    assets, _        := os.read_dir(folder_handle, 200)
    append(&game.asset_names, key)
    game.assets[key] = make([dynamic]rl.Texture, 0)
    for asset in assets do append(&game.assets[key], rl.LoadTexture(to_cstring(asset.fullpath)))
}


asset_init_texture_all :: proc(config : Config) {
    handle, err := os.open(config.assets_path)
    if err  == nil{
	dirs, error := os.read_dir(handle, os.O_RDONLY)
	if error == nil{
	    for folder in dirs{
		if folder.is_dir{
		    strs := strings.split(folder.name, "_")
		    assert(len(strs) >= 2)
		    t :=strs[len(strs) -1][0] 
		    switch t{
		    case 's':
			asset_texture_init(folder.fullpath)
		    case 'a':
			asset_texture_init_in_folder(folder.fullpath, folder.name)
		    case 'g':
			asset_texture_init_by_folder(folder.fullpath)
		    }
		}
	    }
	}else{
	    //Error
	}
    }else{
	//Error
    }
    slice.sort(game.asset_names[:])
}

/**
    TODO: add music rl.Music
**/
asset_sounds_init_all:: proc(config : Config) {
	rl.InitAudioDevice()
	game.sounds = make(map[string]rl.Sound, 100)
	dir, _     := os.open(config.sounds_path)
	sounds, _  := os.read_dir(dir, 100)
	for sound in sounds do game.sounds[sound.name] = rl.LoadSound(to_cstring(sound.fullpath))
}

/*
Better than just indexing because it checks for nil
*/
asset_texture_get :: proc(tex: string) -> ^[dynamic]rl.Texture {
	if game.assets[tex] != nil do return &game.assets[tex] 
	else do return nil
}

outline_shader := `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;

uniform vec2  textureSize;

out vec4 finalColor;

void main(){
	vec2 tex_size = textureSize;
	vec4 texel = texture(texture0, fragTexCoord); //Get texel color
	vec2 texelScale   = vec2(0.0);
	vec4 outlineColor = vec4(1.0f, 0.0f, 0.2f, 1.0f);
	float outlineSize = 4.0f;
	texelScale.x = outlineSize/tex_size.x;
	texelScale.y = outlineSize/tex_size.y;

	vec4 corners = vec4(0.0);
	corners.x = texture(texture0, fragTexCoord + vec2(texelScale.x, texelScale.y)).a;
	corners.y = texture(texture0, fragTexCoord + vec2(texelScale.x, -texelScale.y)).a;
	corners.z = texture(texture0, fragTexCoord + vec2(-texelScale.x, texelScale.y)).a;
	corners.w = texture(texture0, fragTexCoord + vec2(-texelScale.x, -texelScale.y)).a;

	float outline = min(dot(corners, vec4(1.0)), 1.0);
	vec4 color = mix(vec4(0.0), outlineColor, outline);
	finalColor = mix(color, texel, 0.8);
}
`

load_asset_from_folder :: proc(config: Config){
	fd, err := os.open(config.shaders_path)

	if err == nil{
		dir, _ := os.read_dir(fd, 20)
		for file in dir{
			file_name, _ := strings.split(file.name, ".")
			if file_name[1] == "glsl"{
				game.shaders[file_name[0]] = rl.LoadShader(nil, to_cstring(file.fullpath))
			}
		}
	}
}


/* For now manually load all the shader because we don't know which is fragment shader etc.*/
//get this from user
//This are shaders included in the game engine
asset_shaders_init_all :: proc(config: Config) {
    game.shaders             = make(map[string]rl.Shader, 1)
    game.shaders["outline"]  = rl.LoadShaderFromMemory(nil, to_cstring(outline_shader))
    game.textureSizeLoc      = rl.GetShaderLocation(game.shaders["outline"], "textureSize",)
    load_asset_from_folder(config)
    //asset_sounds_init_all(config)
}









