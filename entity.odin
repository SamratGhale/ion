package ion

import b2 "vendor:box2d"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

EntityFlagsEnum :: enum u32 {
	SELECTED,
	JUMPING,
	CHANGES_WITH_ROTATION,
	COMPLETES_LEVEL,
	SLEEP_ON_START,
	ANIMATION,
	GAP_LEFT,
	GAP_RIGHT,
	DOOR_OPENED,
	KILLS,
	NO_FLIP,
	MOVING,
	MOVING_X,
}

EntityFlags :: bit_set[EntityFlagsEnum]

//Hardcoded values for box2d
EntityType :: enum u32{
    none        =1 << 0, 
	player      =   1 << 1,
	enemy       =   1 << 2,
	ground      =   1 << 3,
	npc         =   1 << 4,
	door        =   1 << 5,
	key         =   1 << 6,
	box         =   1 << 7,
	door_opened =   1 << 8,
}



Entity :: struct {
	type:         EntityType,
	body_id:      b2.BodyId,
	shape_id:     b2.ShapeId,
	size:         b2.Vec2,
	texture_rect: rl.Rectangle,
	texture_id:   string,
	flags:        EntityFlags,
	static_index: ^Static_Index,
	anim:         Anim,
    extra       : [EXTRA_DATA_SIZE]u8,
}

/**
    Used to create entities
    box2_size This is to have finer control over the texture size and actual box2d shape size

    if box2_size is zero then copy from size
**/
CreateEntityDef :: struct {
	size:         b2.Vec2,
	box2d_size:   b2.Vec2, 
	type:         EntityType,
	flags:        EntityFlags,
	texture_id:   string,
	level_id:     string, //Dont't let the editor change level
	static_index: Static_Index,
	body_def:     b2.BodyDef,
	shape_def:    b2.ShapeDef,
	anim_step:    i32,
	angle:        f32,
    extra              : [EXTRA_DATA_SIZE]u8,
}


//Save the step
Anim :: struct {
	sub_index, index, step: i32,
}

entity_get_default_def :: proc() -> (ret: CreateEntityDef) {
	ret.body_def = b2.DefaultBodyDef()
	ret.body_def.fixedRotation = true
	ret.body_def.linearDamping = 2
	ret.body_def.angularDamping = 2

	//change these according to the entity type
	ret.shape_def = b2.DefaultShapeDef()
	ret.shape_def.restitution = 0.4
	ret.size = {50, 50}
	ret.type = .ground
	ret.flags += {.CHANGES_WITH_ROTATION}
	ret.level_id = game.curr_level_id
	return
}

entity_get_def :: proc(type: EntityType) -> (ret: CreateEntityDef) {

	ret = entity_get_default_def()
	ret.type = type

	#partial switch type 
	{
	case .ground:
		ret.texture_id = "tiles_center"
	}
	return
}

/*
    Creates new entity, box2d shape and body updates entity_maps, static_indexes
*/
entity_create_new :: proc(def: CreateEntityDef) {
	def := def
	level := level_get(def.level_id)


	if def.box2d_size == {0, 0}{
		def.box2d_size = def.size
	}

	entity: Entity = {
		size = def.size,
		type = def.type,
		texture_id = def.texture_id,
		flags = def.flags,
		anim = {step = def.anim_step},
	}
	entity.static_index = new(Static_Index)
	entity.static_index^ = def.static_index
	level.entity_maps[entity.static_index] = {}

	//body_def.position  = pos
	def.body_def.rotation = b2.MakeRot(def.angle * rl.DEG2RAD)
	def.shape_def.filter.categoryBits = u32(def.type)
	def.shape_def.filter.maskBits    |= u32(def.type)

	textures := asset_texture_get(def.texture_id)
	if textures != nil && len(textures) > 0 {
		entity.texture_rect = {0, 0, f32(textures[0].width), f32(textures[0].height)}
	}

	dynamic_box := b2.MakeRoundedBox(def.box2d_size.x * 0.5, def.box2d_size.y * 0.5, def.box2d_size.x * 0.5)
	entity.body_id = b2.CreateBody(level.world_id, def.body_def)
	entity.shape_id = b2.CreatePolygonShape(entity.body_id, def.shape_def, dynamic_box)

	entity_index := len(level.entities)
	b2.Shape_SetUserData(entity.shape_id, rawptr(uintptr(entity_index)))

	if def.static_index != 0 {
		level.static_indexes[def.static_index] = entity_index
	}

	append(&level.entities, entity)
}


/*
    Give the exact animation for this frame by also applying animation
    Get the current texture array
    Check if it has animation enabled
    If enabled increment according to the length of texture
*/
entity_get_curr_texture :: proc(entity: ^Entity) -> ^rl.Texture {
	textures := asset_texture_get(entity.texture_id)
	if textures == nil do return nil
	if .ANIMATION in entity.flags && len(textures) > 1 {
		if entity.anim.sub_index >= entity.anim.step {
			entity.anim.index += 1
			entity.anim.sub_index = 0
		}
		entity.anim.sub_index += 1
		if entity.anim.index >= i32(len(textures)) {
			entity.anim.index = 0
		}
		return &textures[entity.anim.index]
	} else {
		return &textures[0]
	}
}

entities_render_all :: proc() {

	level := level_get(game.curr_level_id)
	rl.BeginMode2D(level.camera)
	if !game.editor_ctx.hide_grid
	{
		rlgl.PushMatrix();
		rlgl.Translatef(0, 50*50, 0);
		rlgl.Rotatef(90, 1, 0, 0);
		rl.DrawGrid(200, 50);
		rlgl.PopMatrix();
	}

	for &entity, i in &level.entities {
		if i == 0 do continue

		if !b2.Body_IsEnabled(entity.body_id) do continue

		pos := b2.Body_GetPosition(entity.body_id)
		r := b2.Rot_GetAngle(b2.Body_GetRotation(entity.body_id)) * rl.RAD2DEG

		if .CHANGES_WITH_ROTATION not_in entity.flags {
			r -= level.camera.rotation
		}
		texture := entity_get_curr_texture(&entity)
		if texture == nil do continue

		rec: rl.Rectangle = {
			x      = pos.x,
			y      = pos.y,
			width  = entity.size.x * 2,
			height = entity.size.y * 2,
		}
		tex_rec := entity.texture_rect

		if .SELECTED in entity.flags || i == int(game.editor_ctx.selected_entity) {
			tex_size: [2]f32 = {f32(texture.width), f32(texture.height)} 
			rl.SetShaderValue(game.shaders["outline"], game.textureSizeLoc, &tex_size[0], .VEC2)
			rl.BeginShaderMode(game.shaders["outline"])
			rl.DrawTexturePro(texture^, tex_rec, rec, entity.size, r, rl.WHITE)
			rl.EndShaderMode()
		} else do rl.DrawTexturePro(texture^, tex_rec, rec, entity.size, r, rl.WHITE)

		//Add flag on game
		/*
		if entity.type == .player {
			left_ab, right_ab := entity_player_get_bounding_box(level.camera.rotation, pos)
			left, right: rl.BoundingBox
			left.min.xy = left_ab.lowerBound
			left.max.xy = left_ab.upperBound
			right.min.xy = right_ab.lowerBound
			right.max.xy = right_ab.upperBound
			rl.DrawBoundingBox(left, rl.BLACK)
			rl.DrawBoundingBox(right, rl.BLACK)
		}
		*/
	}

	rl.EndMode2D()
	if .COMPLETED in level.flags{

		rec: rl.Rectangle = {f32(game.width / 2) - 120, f32(game.height / 2), 200, 40}
		rl.DrawText("LEVEL COMPLETED", i32(rec.x) - 150, i32(rec.y) - 100, 60, rl.BLACK)
		rl.DrawText("PRESS R TO RESTART", i32(rec.x) - 150, i32(rec.y) , 30, rl.BLACK)

		if is_pressed(.R){
			level_reload(game.curr_level_id)
		}
	}
	else if  .DEAD in level.flags{

		rec: rl.Rectangle = {f32(game.width / 2) - 120, f32(game.height / 2), 200, 40}
		rl.DrawText("DEAD", i32(rec.x) - 150, i32(rec.y) - 100, 60, rl.BLACK)
		rl.DrawText("PRESS R TO RESTART", i32(rec.x) - 150, i32(rec.y) , 30, rl.BLACK)

		if is_pressed(.R){
			level_reload(game.curr_level_id)
		}
	}
}

update_entity :: proc (entity: ^Entity, level: ^Level)


entities_update_all :: proc(){
	level := level_get(game.curr_level_id)
    b2.World_Step(level.world_id, 1.0 / 60.0, 4)

	for &entity in &level.entities{
		if game.entity_update_proc[entity.type] != nil{
			game.entity_update_proc[entity.type](&entity, level)
		}
	}
}

