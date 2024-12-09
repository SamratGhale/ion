package ion
import rl "vendor:raylib"
import im "shared:odin-imgui"

/*     
 * takes in rl keyboard button
 * but also check for equivalent rl gamepad key
*/

//gamepad keyboard
gp_kb : map[rl.KeyboardKey]rl.GamepadButton = {
	.A 	= .LEFT_FACE_LEFT,
	.D 	= .LEFT_FACE_RIGHT,
	.S 	= .LEFT_FACE_DOWN,
	.W 	= .RIGHT_FACE_DOWN,
	.ENTER  = .MIDDLE_RIGHT,
}

/*
Takes in a key and checks if it has corrosponding key and also checks if the corresponding key is down or pressed
*/

is_down :: #force_inline proc(key : rl.KeyboardKey) -> bool
{

    gp_key , ok := gp_kb[key]

    if ok{
    	return rl.IsKeyDown(key) || rl.IsGamepadButtonDown(0, gp_key)
    }else{
    	return rl.IsKeyDown(key)
    }
}

is_pressed :: #force_inline proc(key : rl.KeyboardKey) -> bool
{
    gp_key , ok := gp_kb[key]

    ret := false 
    if ok{
    	ret = rl.IsKeyPressed(key) || rl.IsGamepadButtonPressed(0, gp_key)
    }else{
    	ret = rl.IsKeyPressed(key) 
    }

    if ret do rl.PlaySound(game.sounds["Button.wav"])

    return ret
}

/*
Handle and keys that should execute regardless of which mode the game is on
TODO: exit, escape
*/

toggle_fullscreen :: proc(){
    display := rl.GetCurrentMonitor()
    //Create new render texture
    rl.UnloadRenderTexture(game.render_texture)

    if rl.IsWindowFullscreen(){
        game.render_texture = rl.LoadRenderTexture(game.width, game.height)

        io := im.GetIO()

        im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", 10)
        build_font_atlas()

        im.Style_ScaleAllSizes(im.GetStyle(), 0.5)
        rl.SetWindowSize(game.width, game.height)
    }else{
        w := rl.GetMonitorWidth(display)
        h := rl.GetMonitorHeight(display)

        io := im.GetIO()
        
        im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", im.GetFontSize() * 2)
        build_font_atlas()

        game.render_texture = rl.LoadRenderTexture(w, h)
        im.Style_ScaleAllSizes(im.GetStyle(), 2)
        rl.SetWindowSize(w, h)
    }
    //io := im.GetIO()
    //im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", 9)
    
    rl.ToggleFullscreen()
}

handle_meta_keys :: proc() 
{
    if is_pressed(.F5) do game.mode = game.mode == .PLAY ? .EDITOR : .PLAY
    if is_pressed(.F4) do game.editor_ctx.hide_grid = !game.editor_ctx.hide_grid
    if is_pressed(.F3) do toggle_fullscreen()
    if is_pressed(.ESCAPE){
        switch game.mode{
            case .EDITOR, .PLAY:
                game.mode = .LEVEL_PICKER
            case .LEVEL_PICKER, .SETTINGS:
                game.mode = .START_SCREEN
            case .START_SCREEN: 
        }
    }
}


/*
 When the game is in rotated state,
 Return the corresponding keys to asdw for that rotation
 e.g. d is .S in 90 degrees
 jmp is which key is W
*/

get_rotated_asdw :: proc(level: ^Level) -> (a, s, d, w, jmp: rl.KeyboardKey) 
{
    switch (level.camera.rotation) 
    {
        case 0:
            a = .A
            s = .S
            d = .D
            w = .W
            jmp = .W
        case 90:
            d = .S
            w = .D
            a = .W
            s = .A
            jmp = a
        case 180:
            a = .D
            s = .W
            d = .A
            w = .S
            jmp = s
        case 270:
            a = .S
            s = .D
            d = .W
            w = .A
            jmp = d
    }
    return
}