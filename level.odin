package ion

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"


LENGTH_UNIT_PER_METER :: 128
/*
Have a contrlled way of accessing levels,
    Alphabetically arrange levels
    Create accesser function rather than user directly using key value
*/

LevelFlags :: bit_set[enum {
    GOT_KEY,
    INITILIZED,
    COMPLETED,
    DEAD,
}]

//Static index is always the same for the entity
Static_Index :: i32


Level :: struct {
    flags:                     LevelFlags,

    //A entity needs to be of type .player and it's static index should also match the player_index of Level
    player_index:              Static_Index,

    /* Maps the static index to entity index in the array*/
    static_indexes:            map[Static_Index]int,
    entities:                  [dynamic]Entity,
    entity_defs:               [dynamic]CreateEntityDef,
    world_id:                  b2.WorldId,
    camera:                    rl.Camera2D,

    /**
	For now the main purpose of entity_maps is for key and doors
	When player gets certain key, it should open the doors
	that are in the values of Static_Index of the key
        The reason for not placing this in each entity is because 
        we are editing the level when were're editing this and it takes less space
    **/
    entity_maps:               map[^Static_Index][dynamic]Static_Index,
    entity_maps_serializeable: map[Static_Index][dynamic]Static_Index, //to serialize
    zoom:                      f32,
    player_ground_shape_id:    b2.ShapeId,

    extra              : [EXTRA_DATA_SIZE]u8,
    background_color   : rl.Color,
	background_color_f32 : [4]f32,
}

/*
Resets the level by deleting all the entities and creating new entities from entity_defs
*/
level_reload :: proc(key: string) {
    level := &game.levels[game.curr_level_id]
    level.flags -= {.COMPLETED, .DEAD}

    clear(&level.entity_maps_serializeable)
    level.entity_maps_serializeable = make(map[Static_Index][dynamic]Static_Index)

    for key, val in level.entity_maps {
        if key != nil{
            level.entity_maps_serializeable[key^] = {}

            for v in val {
                append(&level.entity_maps_serializeable[key^], v)
            }
        }
    }
    level.camera.rotation = 0
    clear(&level.entities)
    clear(&level.static_indexes)
    clear(&level.entity_maps)
    b2.DestroyWorld(level.world_id)
    append_nothing(&level.entities)

    //NOTE: put world_def in level
    //Most of the attributes of world_def is unnecessary for the game so we can avoid adding it in level and add the required attributes manually

    world_def := b2.DefaultWorldDef()
    world_def.gravity = {0, 9.8 * LENGTH_UNIT_PER_METER}

    level.world_id = b2.CreateWorld(world_def)

    for &def in &level.entity_defs {
        def.level_id = key
        entity_create_new(def)
    }
    //fill entity_map
    for key, val in level.entity_maps_serializeable {
        index := level.static_indexes[key]
        entity := &level.entities[index]
        level.entity_maps[entity.static_index] = {}
        for v in val do append(&level.entity_maps[entity.static_index], v)
    }
    level.flags += {.INITILIZED}
}

level_load :: proc(key: string) {
    game.levels[key] = {}

    level := &game.levels[key]
    path := fmt.tprintf("./levels/%s.level", key)
    level_data, _ := os.read_entire_file_from_filename(path)

    if level_data == nil || len(level_data) == 0 {
        //empty level
        append_nothing(&level.entities)

        //NOTE: put world_def in level
        world_def := b2.DefaultWorldDef()
        world_def.gravity = {0, 9.8 * LENGTH_UNIT_PER_METER}

        level.world_id = b2.CreateWorld(world_def)
    } else {
        s: Serializer
        serializer_init_reader(&s, level_data[:])
        serialize(&s, level)
        world_def := b2.DefaultWorldDef()
        world_def.gravity = {0, 9.8 * LENGTH_UNIT_PER_METER}

        level.world_id = b2.CreateWorld(world_def)
        append_nothing(&level.entities)

        for def in level.entity_defs {
            def := def
            def.level_id = key
            entity_create_new(def)
        }
        //put entity_maps_serializeable to entity_maps

        for key, val in level.entity_maps_serializeable {
            //index_wrap := new(Static_Index)

            //get entity
            index := level.static_indexes[key]
            entity := &level.entities[index]

            level.entity_maps[entity.static_index] = {}

            for v in val do append(&level.entity_maps[entity.static_index], v)
        }
    }
    level.flags -= {.COMPLETED}
}

/*
load all levels and put the names on the level names
*/
level_init_all :: proc(config: Config) {
    dir, err    := os.open(config.levels_path)
    levels, _ := os.read_dir(dir, 200)

    clear_map(&game.levels)
    game.levels = make(map[string]Level, len(levels))


    for level_data in levels {
        if level_data.is_dir do continue

        name := strings.split(level_data.name, ".")
        append(&game.level_names, name[0])
        assert(name[1] == "level")
        level_load(name[0])
    }

    slice.sort(game.level_names[:])

    builder := strings.builder_make()
    for name, i in game.level_names {
        strings.write_string(&builder, name)
        if i < len(game.level_names) - 1 do strings.write_rune(&builder, '\n')
    }
    game.level_names_single = strings.to_cstring(&builder)

    os.close(dir)
}

level_save_current :: proc() {
    level       := level_get(game.curr_level_id)
    level.flags -= {.COMPLETED}

    if level != nil {
        level_path := fmt.tprintf("./levels/%s.level", game.curr_level_id)
        clear(&level.entity_maps_serializeable)
        for key, val in level.entity_maps {
            if key != nil{
            level.entity_maps_serializeable[key^] = {}
            for v in val do append(&level.entity_maps_serializeable[key^], v)
            }
        }
        s: Serializer
        serializer_init_writer(&s)
        serialize(&s, level)
        os.write_entire_file(level_path, s.data[:])
    }
}

level_get :: proc(level_id: string) -> ^Level {
    if level_id in game.levels {
        return &game.levels[level_id]
    }
    return nil
}

