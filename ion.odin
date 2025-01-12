package ion

import "base:runtime"
import "core:fmt"
import virt "core:mem/virtual"
import im "shared:odin-imgui"
import b2 "vendor:box2d"
import rl "vendor:raylib"

EXTRA_DATA_SIZE :: runtime.Kilobyte * 5

cfmt :: fmt.ctprintf

Config :: struct {
	fullscreen:       bool,
	size:             rl.Vector2,
	fps:              i32,
	name:             string,
	levels_path:      string,
	background_color: rl.Color,

	//Label the prefix according to the type of asset, 
	assets_path:      string,
	shaders_path:     string,
	fonts_path:       string,
	sounds_path:      string,
}

DefaultConfig: Config = {
	fullscreen       = false,
	size             = {1920 / 2, 1080 / 2},
	fps              = 60,
	name             = "Game!",
	shaders_path     = "./shaders",
	assets_path      = "./assets",
	levels_path      = "./levels",
	fonts_path       = "./fonts",
	sounds_path      = "./sounds",
	background_color = rl.RAYWHITE,
}

GameMode :: enum {
	START_SCREEN,
	PLAY,
	LEVEL_PICKER,
	SETTINGS,
	EDITOR,
}

entities_update_all_proc :: proc(level: ^Level)
entities_render_custom :: proc(level: ^Level)

ExtraTypes :: enum {
	GAME,
	LEVEL,
	ENTITY,
}

/*
    Notes on Extra Types
    Extra types is stored in extra inside GameState, Level and Entity as u8 array
    The User can use it to store any data related to the game
    
    To let user change values of the fields in imgui we store the typeid of the extra
    and the editor checks the typeid for tags and shows it in imgui
    
    tags:
        imgui : 
            vec2         //vector 2 shows as two slider 
            checkbox
            enums?

*/

GameState :: struct {
	width, height:              i32,
	render_texture:             rl.RenderTexture,
	imgui_render_texture:       rl.RenderTexture,

	name:                       cstring,
	mode:                       GameMode,
	curr_level_id:              string,
	assets:                     map[string][dynamic]rl.Texture2D,
	asset_names:                [dynamic]string, //sorted
	sounds:                     map[string]rl.Sound,
	shaders:                    map[string]rl.Shader,
	levels:                     map[string]Level,
	level_names:                [dynamic]string, //contains all the levels
	level_names_to_display:     [dynamic]string, //contains level names to display
	level_names_single:         cstring, //contains level names to display
	editor_ctx:                 EditorContext,
	textureSizeLoc:             i32,
	arena:                      virt.Arena,
	allocator:                  runtime.Allocator,
	font:                       rl.Font,
	offset, size:               rl.Vector2,
	background_color:           rl.Color,
	entity_update_proc:         map[EntityType]update_entity,
	entities_update_all_custom: entities_update_all_proc,
	entities_render_custom:     entities_render_custom,
	extra:                      [EXTRA_DATA_SIZE]u8,
	skip_update_this_frame:     bool,
	prev_pos:                   rl.Vector2,
	config:                     Config,
	extra_type_ids:             [ExtraTypes]typeid,

	audio_ctx:                  AudioConfig,
}

game: GameState

/*
    Initilize
    Raylib
    Imgui
    Allocator
    Levels
    Assets
    Shaders
*/
raylib_imgui_init :: proc(using config: Config) {
	rl.InitWindow(game.width, game.height, to_cstring(name))

	rl.SetTargetFPS(fps)
	rl.SetExitKey(.KEY_NULL)
	game.font = rl.LoadFontEx("c:\\Windows\\Fonts\\Consola.ttf", 80, nil, 250)
	//rl.GuiLoadStyle("./raygui_style.rgs")
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 80)
	//rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_LINE_SPACING), 100)
	//rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_ALIGNMENT_VERTICAL), 100)
	//rl.GuiSetFont(game.font)

	im.CreateContext(nil)
	imgui_init()
	io := im.GetIO()
	im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", 33)
	build_font_atlas()

	display := rl.GetCurrentMonitor()
	w := rl.GetMonitorWidth(display)
	h := rl.GetMonitorHeight(display)
	game.render_texture = rl.LoadRenderTexture(w, h) //render texture should always be either full screen or the size the game started with
	game.imgui_render_texture = rl.LoadRenderTexture(w, h) //render texture should always be either full screen or the size the game started with
	b2.SetLengthUnitsPerMeter(LENGTH_UNIT_PER_METER)
        im.Style_ScaleAllSizes(im.GetStyle(), 4)
        rl.SetMouseScale(2, 2)

	init_miniaudio()
}


create_game :: proc(config: Config) -> ^GameState {
	game.background_color = config.background_color
	game.name = to_cstring(config.name)
	game.width = i32(config.size.x)
	game.height = i32(config.size.y)
	game.config = config
	raylib_imgui_init(config)
	asset_init_texture_all(config)
	asset_shaders_init_all(config)
	level_init_all(config)

	fmt.println(rl.GetMonitorWidth(0)/game.width)
	rl.SetMouseScale(2,2)

	return &game
}

//Start game loop 
start_game :: proc() {

	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)
		handle_meta_keys()

		rl.BeginDrawing()
		imgui_rl_begin()

		if game.mode == .PLAY || game.mode == .EDITOR {
			level := level_get(game.curr_level_id)
			rl.ClearBackground(level.background_color)
			rl.BeginTextureMode(game.render_texture)
			rl.ClearBackground(level.background_color)
			rl.EndTextureMode()

			rl.BeginTextureMode(game.imgui_render_texture)
			rl.ClearBackground(rl.ColorAlpha(rl.WHITE, 0))
			rl.EndTextureMode()

		} else {
			rl.ClearBackground(game.background_color)
			rl.BeginTextureMode(game.render_texture)
			rl.ClearBackground(game.background_color)
			rl.EndTextureMode()
		}

		switch (game.mode) {
			case .EDITOR:
			editor_update()
			editor_render_all()
			entities_render_all()
			case .PLAY:
			level := level_get(game.curr_level_id)
			editor_render_all()

			if !game.skip_update_this_frame {
				entities_update_all()
			}
			if game.entities_update_all_custom != nil {
				game.entities_update_all_custom(level)
			}
			entities_render_all()

			case .LEVEL_PICKER:
			menu_render_level_picker()
			case .SETTINGS:
			menu_render_settings()
			case .START_SCREEN:
			menu_render_start_screen()
		}


		rl.DrawTexturePro( game.render_texture.texture, { 0, 0, f32(game.render_texture.texture.width), -f32(game.render_texture.texture.height), }, {0, 0, f32(game.width), -f32(game.height)}, {}, 0.0, rl.ColorAlpha(rl.WHITE, 0.75), )

		rl.BeginTextureMode(game.imgui_render_texture)
		imgui_rl_end()
		rl.EndTextureMode()
		if game.mode == .PLAY ||  game.mode == .EDITOR{
			
			level := level_get(game.curr_level_id)
			if game.entities_render_custom != nil{
				game.entities_render_custom(level)
			}
			rl.DrawTexturePro(game.imgui_render_texture.texture, { 0, 0, f32(game.imgui_render_texture.texture.width), -f32(game.imgui_render_texture.texture.height), }, {0, 0, f32(game.width), -f32(game.height)}, {}, 0.0, rl.WHITE )

		}
		rl.EndDrawing()
	}
	rl.CloseWindow()
	imgui_shutdown()
}
