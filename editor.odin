package ion

import im "shared:odin-imgui"
import "core:math"
import "base:runtime"
import "core:slice"
import "core:fmt"
import b2 "vendor:box2d"
import rl "vendor:raylib"


/**
   TODOS for editor mode
    Filter in entity editor
    Select entity by Static_Index
    not much difference in editor update and render
**/


EditorContext :: struct {
    //Entity type for making new entity
    entity_type:                 EntityType,

    selected_entity:             i32,
    asset_browser:               bool,
    curr_static_index:           Static_Index,
    copied_def:                  CreateEntityDef,
    hide_grid, enable_snap_50 : bool,

	selected_entities : [dynamic]i32,
	//Enable this when selected with LEFT_SHIFT
	multi_edit_mode   : bool,
}
btn_window_flags: im.WindowFlags = {.NoBackground, .NoTitleBar}

/* Render things that persists in all the state of the game like some buttons to switch state */
editor_render_menus :: proc() {
    if game.mode == .EDITOR || game.mode == .PLAY {
		if im.Begin("Btn", nil, btn_window_flags) {
			if im.Button(cfmt("%s Mode", game.mode)) do game.mode = game.mode == .PLAY ? .EDITOR : .PLAY
		}
		im.End()
    }
}
editor_render_level :: proc() /* imgui for selected level */
{
    ctx   := &game.editor_ctx
    level := &game.levels[game.curr_level_id]
    im.Text("Current level %s", game.curr_level_id)
    //Select entity
    if im.BeginCombo("Select entity", cfmt("%d", ctx.selected_entity)) {
		for i in 0 ..< len(level.entity_defs) {
			if im.Selectable(cfmt("%d", i + 1)) do ctx.selected_entity = i32(i + 1)
		}
		im.EndCombo()
    }

    if im.Button("Delete current enetity"){
		if game.editor_ctx.selected_entity != 0 {
			//def := level.entity_defs[game.editor_ctx.selected_entity - 1]
			ordered_remove(&level.entity_defs, game.editor_ctx.selected_entity - 1)
			level_reload(game.curr_level_id)
		}
    }

    //just create the entity and also select it
    if im.BeginCombo("Entity type", cfmt("%s", ctx.entity_type)) {
		for type in EntityType do if im.Selectable(cfmt("%s", type)) do ctx.entity_type = type
		im.EndCombo()
    }


    //This just creates new entity, edit the entity in the entity column
    if im.Button("Create new entity") {
		def := entity_get_def(ctx.entity_type)
		append(&level.entity_defs, def)
		level_reload(game.curr_level_id)
		game.editor_ctx.selected_entity = i32(len(level.entities) - 1)
    }

    im.Dummy(im.Vec2{0.0, 20.0})

    //player_index
    if im.BeginCombo("Player Index", cfmt("%d", level.player_index)) {
		for key in level.static_indexes {
			if im.Selectable(cfmt("%d", key)) do level.player_index = key
		}
		im.EndCombo()
    }

    //Zoom
    im.InputFloat("Camera zoom", &level.camera.zoom, 0.1)
    //Rotation
    im.SliderFloat("Camera rotation", &level.camera.rotation, 0, 360)

    im.Checkbox("Snap on 50", &game.editor_ctx.enable_snap_50)

    im.Dummy(im.Vec2{0.0, 20.0})
    if im.Button("Reload Level") {
		level_reload(game.curr_level_id)
    }
    im.SameLine()
    if im.Button("Save Level") {
		level_save_current()
    }

	if im.ColorPicker4("Background Color", &level.background_color_f32, {.Uint8,.InputRGB,.PickerHueBar, .AlphaBar}){
		val :[4]u8= transmute([4]u8)(im.ColorConvertFloat4ToU32(level.background_color_f32))
		level.background_color = rl.Color(val)
	}
}
editor_render_asset_browser :: proc(def: ^CreateEntityDef = nil) {/* imgui asset picker for selected */
    col_index := 0
    if im.Begin("Asset browser", nil) {
		for key in game.asset_names{
			texture := game.assets[key]
			if texture != nil {
				if col_index % 7 != 0 do im.SameLine()
				col_index += 1

				im_tex_id := cast(im.TextureID)uintptr(&texture[0].id)
				if im.ImageButton(to_cstring(key), im_tex_id, {50, 50}) {

					if game.editor_ctx.multi_edit_mode{
						level := level_get(game.curr_level_id)
						for i in game.editor_ctx.selected_entities{
							def := &level.entity_defs[i - 1]
							def.texture_id = key
						}
						level_reload(game.curr_level_id)
					} else{
						def.texture_id = key
					}
				}
				if im.IsItemHovered() do im.SetTooltip(to_cstring(key))
			}
		}
    }
    im.End()
}


snap_pos :: proc(pos: [2]f32) -> [2]f32 {
    pos := pos
    diff: [2]f32
    snap_val  :f32= 100
    snap_half :f32= 50

    if game.editor_ctx.enable_snap_50{
		snap_val  = 50
		snap_half = 25
    }
    diff.x = f32(abs(i32(pos.x)) % i32(snap_val))
    diff.y = f32(abs(i32(pos.y)) % i32(snap_val))

    if pos.x < 0 {
		if abs(diff.x) > snap_half {
			pos.x -= snap_val - diff.x
		} else {
			pos.x += diff.x
		}
    } else if pos.x > 0 {
		if abs(diff.x) > snap_half {
			pos.x += snap_val - diff.x
		} else {
			pos.x -= diff.x
		}
    }

    if pos.y < 0 {
		if abs(diff.y) > snap_half{
			pos.y -= snap_val- diff.y
		} else {
			pos.y += diff.y
		}
    } else if pos.y > 0 {
		if abs(diff.y) > snap_half{
			pos.y += snap_val- diff.y
		} else {
			pos.y -= diff.y
		}
    }
    pos.x = math.round(pos.x)
    pos.y = math.round(pos.y)
    return pos
}

/* imgui for selected entity */
editor_render_entity :: proc() {
    if game.editor_ctx.selected_entity != 0 {
		level  := &game.levels[game.curr_level_id]
		entity := &level.entities[game.editor_ctx.selected_entity]
		def    := level.entity_defs[game.editor_ctx.selected_entity - 1]

		im.InputFloat2("Size ", &def.size)
		im.InputFloat2("Box2d Size", &def.box2d_size)
		if im.BeginCombo("Entity type", cfmt("%s", def.type)) {
			for type in EntityType {
				if im.Selectable(cfmt("%s", type)) do def.type = type
			}
			im.EndCombo()
		}
		if im.Button("Select Texture Asset") {
			game.editor_ctx.asset_browser = !game.editor_ctx.asset_browser
		}
		im.SameLine()
		im.Text("%s", def.texture_id)
		if game.editor_ctx.asset_browser {
			editor_render_asset_browser(&def)
		}
		im.Dummy(im.Vec2{0.0, 20.0})
		im.Text("Entity Flags")
		flags_index := 0

		for flag in EntityFlagsEnum {
			if (flags_index % 2 != 0) do im.SameLine()

			flags_index += 1
			exits: bool = flag in def.flags

			if im.Checkbox(cfmt("%s", flag), &exits) {
				if !exits do def.flags -= {flag}
				else do def.flags += {flag}
			}
		}

		im.Dummy(im.Vec2{0.0, 20.0})
		if .ANIMATION in def.flags {
			im.SliderInt("Animation", &def.anim_step, 0, 20)
		}
		im.SliderFloat("Rotation ", &def.angle, 0, 359)
		im.InputFloat("Rotation", &def.angle, 10)
		im.InputInt("Static_Index", &def.static_index)
		im.Dummy(im.Vec2{0.0, 20.0})


		//BodyDef
		if im.BeginTabBar("##Box2d Def", {}) {
			if im.BeginTabItem("Body Def") {
				if im.BeginCombo("Body Type", cfmt("%s", def.body_def.type)) {
					for type in b2.BodyType {
						if im.Selectable(cfmt("%s", type)) do def.body_def.type = type
					}
					im.EndCombo()
				}

				if im.SliderFloat("Position x", &def.body_def.position.x, -1000, 1000) {
					def.body_def.position = snap_pos(def.body_def.position)
				}
				if im.SliderFloat("Position y", &def.body_def.position.y, -1000, 1000) {
					def.body_def.position = snap_pos(def.body_def.position)
				}
				im.InputFloat2("Linear velocity", &def.body_def.linearVelocity)
				im.InputFloat("Angular velocity", &def.body_def.angularVelocity, .5, 15.0)
				im.InputFloat("Linear damping", &def.body_def.linearDamping, .5, 15.0)
				im.InputFloat("Angular Damping", &def.body_def.angularDamping, .5, 15.0)
				im.InputFloat("Gravity Scale", &def.body_def.gravityScale, .5, 15.0)
				im.InputFloat("Sleep Threshold", &def.body_def.sleepThreshold, .5, 15.0)
				im.Checkbox("Enable Sleep", &def.body_def.enableSleep)
				im.Checkbox("Is Awake", &def.body_def.isAwake)
				im.Checkbox("Fixed rotation", &def.body_def.fixedRotation)
				im.Checkbox("Is Bullet", &def.body_def.isBullet)
				im.Checkbox("Enabled", &def.body_def.isEnabled)
				im.Checkbox("Automatic Mass", &def.body_def.automaticMass)
				im.EndTabItem()
			}

			if im.BeginTabItem("Shape Def") {
				im.SliderFloat("Friction", &def.shape_def.friction, 0, 1)
				im.SliderFloat("Restitution", &def.shape_def.restitution, 0, 1)
				im.SliderFloat("Density", &def.shape_def.density, 0, 50)
				im.Checkbox("Is Sensor", &def.shape_def.isSensor)
				im.Checkbox("Sensor  Events", &def.shape_def.enableSensorEvents)
				im.Checkbox("Contact Events", &def.shape_def.enableContactEvents)
				im.Checkbox("Hit Events", &def.shape_def.enableHitEvents)

				im.Text("Mask bits")

				for type in EntityType {
					exits := bool(def.shape_def.filter.maskBits & u32(type))
					if im.Checkbox(cfmt("%s ", type), &exits) {
						if !exits do def.shape_def.filter.maskBits ~= u32(type)
						else do def.shape_def.filter.maskBits |= u32(type)
					}
				}
				im.EndTabItem()
			}
			im.EndTabBar()
		}
		//EntityMap

		if def.static_index != 0 {
			indexes := &level.entity_maps[entity.static_index]
			if im.BeginCombo("Select entity", cfmt("%d", game.editor_ctx.curr_static_index)) {
				for key in level.static_indexes {
					if im.Selectable(cfmt("%d", key)) do game.editor_ctx.curr_static_index = i32(key)
				}
				im.EndCombo()
			}
			if im.Button("Add") {
				if !slice.contains(indexes[:], game.editor_ctx.curr_static_index) {
					append(indexes, game.editor_ctx.curr_static_index)
				}
			}

			for val, i in indexes {
				im.Text("%d", val)
				im.SameLine()
				if im.Button("Delete") {
					ordered_remove(indexes, i)
				}
			}
		}
		old_def := &level.entity_defs[game.editor_ctx.selected_entity - 1]
		if old_def^ != def {
			level.entity_defs[game.editor_ctx.selected_entity - 1] = def
			level_reload(game.curr_level_id)
		}
    } else {
		im.Text("No entity selected")
    }
}

/* Renders the live Entity Value of the selected entity rather than entity_def values */
editor_render_live :: proc() {
    if game.editor_ctx.selected_entity != 0 {
		level := &game.levels[game.curr_level_id]
		entity := &level.entities[game.editor_ctx.selected_entity]

		if entity != nil {
			im.Text("Entity Flags")
			flags_index := 0
			for flag in EntityFlagsEnum {
				flags_index += 1
				exits: bool = flag in entity.flags

				if (flags_index % 2 != 0) do im.SameLine()
				im.Checkbox(cfmt("%s", flag), &exits)
			}
		}
    }
}

/*
	Move
	Delete
	Texture
*/
editor_render_multi_entity :: proc(){
	if im.Button("Select Texture Asset") {
		game.editor_ctx.asset_browser = !game.editor_ctx.asset_browser
	}
	if game.editor_ctx.asset_browser{
		editor_render_asset_browser()
	}
}

editor_render_all :: proc() { /* Renders all the above functions */
    if im.Begin("Editor", nil, {}) {
		if im.BeginTabBar("##Tabs", {}) {
			if game.mode == .EDITOR {
				if im.BeginTabItem("Game State") {
					im.Text("Game Mode")
					im.EndTabItem()
				}
				if im.BeginTabItem("Level State") {
					editor_render_level()
					im.EndTabItem()
				}

				if game.editor_ctx.multi_edit_mode{
					if im.BeginTabItem("Multi Edit State"){
						editor_render_multi_entity();
						im.EndTabItem()
					}
				}else{
					if im.BeginTabItem("Entity State") {
						editor_render_entity()
						im.EndTabItem()
					}
				}
			}
			im.EndTabBar()
		}
    }
    im.End()
}

//TODO: do this without callback
overlap_result_proc :: proc "c" (shapeId: b2.ShapeId, ctx: rawptr) -> bool {
	context = runtime.default_context()
    game := cast(^GameState)ctx
    entity_index := i32(uintptr(b2.Shape_GetUserData(shapeId)))

	if is_down(.LEFT_SHIFT) {
		game.editor_ctx.multi_edit_mode = true
		append(&game.editor_ctx.selected_entities, entity_index)
	}else{
		if game.editor_ctx.multi_edit_mode{
			clear(&game.editor_ctx.selected_entities)
			game.editor_ctx.multi_edit_mode = false
		}
		game.editor_ctx.selected_entity = entity_index
	}
    return false
}

MousePointerFlag: u32 : 1 << 30

update_ctrl_keys :: proc() {

    if is_down(.LEFT_CONTROL) && is_pressed(.C) {
		if game.editor_ctx.selected_entity != 0 {
			//get game def
			//put a copy of it in editor context
			level := level_get(game.curr_level_id)
			def := level.entity_defs[game.editor_ctx.selected_entity - 1]
			game.editor_ctx.copied_def = def
		}
	} else if is_down(.LEFT_CONTROL) && is_pressed(.V) {
		if game.editor_ctx.selected_entity != 0 {
			if game.editor_ctx.copied_def != {} {
				//Get mouse positoin
				//add to the mouse position
				level := &game.levels[game.curr_level_id]
				pos := rl.GetMousePosition()
				cam := level.camera
				cam.offset += game.offset
				pos = rl.GetScreenToWorld2D(pos, cam)
				def := game.editor_ctx.copied_def
				def.body_def.position = snap_pos(pos)
				append(&level.entity_defs, def)
				level_reload(game.curr_level_id)
			}
		}
    }

    //delete

    if is_pressed(.DELETE) {
		level := &game.levels[game.curr_level_id]
		if game.editor_ctx.multi_edit_mode{
			for i in game.editor_ctx.selected_entities{
				unordered_remove(&level.entity_defs, i - 1)
			}
			clear(&game.editor_ctx.selected_entities)
			level_reload(game.curr_level_id)
			game.editor_ctx.selected_entity = 0
		}else{
			if game.editor_ctx.selected_entity != 0 {
				ordered_remove(&level.entity_defs, game.editor_ctx.selected_entity - 1)
				level_reload(game.curr_level_id)
				game.editor_ctx.selected_entity = 0
			}
		}
    }

	level := &game.levels[game.curr_level_id]
	move_diff : [2]f32 = {0, 0}

	if is_pressed(.LEFT){
		move_diff.x -= game.editor_ctx.enable_snap_50 ? 50 :  100 
	}
	if is_pressed(.RIGHT){
		move_diff.x = game.editor_ctx.enable_snap_50 ? 50 :  100 
	}
	if is_pressed(.UP){
		move_diff.y -= game.editor_ctx.enable_snap_50 ? 50 :  100 
	}
	if is_pressed(.DOWN){
		move_diff.y = game.editor_ctx.enable_snap_50 ? 50 :  100 
	}

	if move_diff != {0, 0}{
		if game.editor_ctx.multi_edit_mode{
			for i in game.editor_ctx.selected_entities{
				def := &level.entity_defs[i - 1]
				def.body_def.position += move_diff
			}
			level_reload(game.curr_level_id)
		}else{
			def := &level.entity_defs[game.editor_ctx.selected_entity - 1]
			def.body_def.position += move_diff
			level_reload(game.curr_level_id)
		}
	}

}

update_zoom_and_scroll :: proc() {
	if is_down(.LEFT_CONTROL){
		io := im.GetIO()
		level := level_get(game.curr_level_id)
		if rl.IsMouseButtonDown(.LEFT) && !io.WantCaptureMouse {
			level.camera.offset += rl.GetMouseDelta()
		}
		level.camera.zoom += rl.GetMouseWheelMove() / 100.0
	}
}

editor_update :: proc() {
    io := im.GetIO()

	update_zoom_and_scroll()
    update_ctrl_keys()

    if rl.IsMouseButtonPressed(.LEFT) && !io.WantCaptureMouse {
		aabb: b2.AABB
		pos := rl.GetMousePosition()
		cam := game.levels[game.curr_level_id].camera
		pos = rl.GetScreenToWorld2D(pos, cam)

		aabb.lowerBound = pos
		aabb.upperBound = pos + 1
		filter := b2.DefaultQueryFilter()

		world_id := game.levels[game.curr_level_id].world_id
		b2.World_OverlapAABB(world_id, aabb, filter, overlap_result_proc, &game)
    }
}