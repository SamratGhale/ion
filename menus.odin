package ion

import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "core:fmt"

active_menu: i32
active_level_menu: i32


volume : f32 = 0

menu_render_settings :: proc() {
	rl.BeginTextureMode(game.render_texture)
	defer rl.EndTextureMode()
	rec: rl.Rectangle = {f32(game.render_texture.texture.width / 2) - 60, f32(game.render_texture.texture.height/ 2) - 100, 200, 40}
	rl.DrawTextEx(game.font, game.name, {rec.x, rec.y - 100}, 80, 0, rl.BLACK)

	rec.y += 60

	rl.GuiSlider(rec, "Volume", "", &volume, 0, 1)
	ma.device_set_master_volume(&game.audio_ctx.device, volume)
}

/**
	TODO:
		Disable mouse altogether
 */
menu_render_start_screen :: proc()  {
	rl.BeginTextureMode(game.render_texture)
	defer rl.EndTextureMode()

	rec: rl.Rectangle = {f32(game.render_texture.texture.width / 2) - 260, f32(game.render_texture.texture.height/ 2) - 100, 700, 80}
	rl.DrawTextEx(game.font, game.name, {rec.x, rec.y - 100}, 80, 0, rl.BLACK)

	rec.y += 60
	rec.x -= 160
	new_active_menu := active_menu
	rl.GuiToggleGroup(rec, "Settings\nSelect Level\nExit", &new_active_menu)

	if new_active_menu != active_menu do active_menu = new_active_menu

	if is_pressed(.S) do active_menu = clamp(active_menu + 1, 0, 2)
	if is_pressed(.W) do active_menu = clamp(active_menu - 1, 0, 2)

	if is_pressed(.ENTER) {
		switch active_menu 
		{
		case 0:
			game.mode = .SETTINGS
		case 1:
			game.mode = .LEVEL_PICKER
		case 2:
			rl.CloseWindow()
		}
	}
}

menu_render_level_picker :: proc() {
	rl.BeginTextureMode(game.render_texture)
	defer rl.EndTextureMode()
	
	rec: rl.Rectangle = {f32(game.render_texture.texture.width / 2) - 260, f32(game.render_texture.texture.height/ 2) - 100, 700, 80}
	rl.DrawTextEx(game.font, game.name, {rec.x, rec.y - 100}, 80, 0, rl.BLACK)

	rec.y += 60
	rec.x -= 160

	new_active_menu := active_level_menu
	rl.GuiToggleGroup(rec, game.level_names_single, &new_active_menu)

	if new_active_menu != active_level_menu do active_level_menu = new_active_menu

	if is_pressed(.S) do active_level_menu = clamp(active_level_menu + 1, 0, i32(len(game.levels) - 1))
	if is_pressed(.W) do active_level_menu = clamp(active_level_menu - 1, 0, i32(len(game.levels) - 1))

	if is_pressed(.ENTER) {
		game.curr_level_id = game.level_names_to_display[active_level_menu]
		game.mode = .EDITOR
	}
}
