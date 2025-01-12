#+feature dynamic-literals
package ion
import rl "vendor:raylib"
import im "shared:odin-imgui"

/*     
 * takes in rl keyboard button
 * but also check for equivalent rl gamepad key
*/
leftStickDeadzoneX   :: 0.1
leftStickDeadzoneY   :: 0.1
rightStickDeadzoneX  :: 0.1
rightStickDeadzoneY  :: 0.1
leftTriggerDeadzone  :: -0.9
rightTriggerDeadzone :: -0.9


//gamepad keyboard
gp_kb : map[rl.KeyboardKey]rl.GamepadButton = {
	.A 	    = .LEFT_FACE_LEFT,
	.D 	    = .LEFT_FACE_RIGHT,
	.S 	    = .LEFT_FACE_DOWN,
	.W 	    = .RIGHT_FACE_DOWN,
	.ENTER  = .MIDDLE_RIGHT,
}

/*
Takes in a key and checks if it has corrosponding key and also checks if the corresponding key is down or pressed
*/

is_down :: #force_inline proc(key : rl.KeyboardKey) -> bool {
    gp_key , ok := gp_kb[key]

    if ok{
    	ret := rl.IsKeyDown(key) || rl.IsGamepadButtonDown(0, gp_key)

        left_x, left_y : f32 
        left_x = rl.GetGamepadAxisMovement(0, .LEFT_X)
        left_y = rl.GetGamepadAxisMovement(0, .LEFT_Y)
        if (left_x > -leftStickDeadzoneX && left_x < leftStickDeadzoneX) {
            left_x = 0.0
        }
        if (left_y > -leftStickDeadzoneY && left_y < leftStickDeadzoneY) {
            left_y = 0.0
        }
        if key == .A do if left_x <= -0.5 do ret = true
        if key == .D do if left_x >= 0.5 do ret = true

        if key == .W do if left_y <= -0.5 do ret = true
        if key == .S do if left_y >=  0.5 do ret = true

        return ret
    }else{
    	return rl.IsKeyDown(key)
    }
}

is_pressed :: #force_inline proc(key : rl.KeyboardKey) -> bool {
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
    //rl.UnloadRenderTexture(game.render_texture)

    if rl.IsWindowFullscreen(){
        //game.render_texture = rl.LoadRenderTexture(game.width, game.height)

        io := im.GetIO()
        game.width  = i32(game.config.size.x)
        game.height = i32(game.config.size.y)

        im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", 33)
        build_font_atlas()
        rl.SetMouseScale(2, 2)

        //im.Style_ScaleAllSizes(im.GetStyle(), 0.5)
        rl.SetWindowSize(game.width, game.height)
        im.Style_ScaleAllSizes(im.GetStyle(), 1)
    }else{
        w := rl.GetMonitorWidth(display)
        h := rl.GetMonitorHeight(display)

        io := im.GetIO()
        
        im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", 33)
        im.Style_ScaleAllSizes(im.GetStyle(), 0.5)
        build_font_atlas()
        game.width  = w
        game.height = h
        rl.SetMouseScale(1, 1)


        //game.render_texture = rl.LoadRenderTexture(w, h)
        //im.Style_ScaleAllSizes(im.GetStyle(), 2)
        rl.SetWindowSize(w, h)
    }
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

