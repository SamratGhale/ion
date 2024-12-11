package ion

///////////////////////////////////////////////////////////////////////////////////////////////////////////
// LBP Serializer
//
// Explanation of the method:
// https://handmade.network/p/29/swedish-cubes-for-unity/blog/p/2723-how_media_molecule_does_serialization
//
// Note: numbers are automatically converted to little endian, and pointer-sized
// types are always treated as 64-bit. see `serialize_number` for more information.
//
// TODO:
// - handle endianness better: now only integers and floats are hardcoded. Enums and bit_sets aren't.

import b2 "vendor:box2d"

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"

_ :: fmt // fmt is used only for debug printing


SERIALIZER_ENABLE_GENERIC :: #config(SERIALIZER_ENABLE_GENERIC, true)

// Each update to the data layout should be a value in this enum.
// WARNING: do not change the order of these!
Serializer_Version :: enum u32le {
	initial = 0,
	added_vec2,
	added_vec3,
	added_extra_bytes,
	added_camera_offset,
	added_background_color,
	// Don't remove this!
	LATEST_PLUS_ONE,
}

SERIALIZER_VERSION_LATEST :: Serializer_Version(int(Serializer_Version.LATEST_PLUS_ONE) - 1)

Serializer :: struct {
	is_writing:  bool,
	data:        [dynamic]byte,
	read_offset: int,
	version:     Serializer_Version,
	debug:       Serializer_Debug,
}

when ODIN_DEBUG {
	Serializer_Debug :: struct {
		print_scope: bool,
		depth:       int,
	}
} else {
	Serializer_Debug :: struct {}
}

// TODO: serialize with version
serializer_init_writer :: proc(
	s: ^Serializer,
	capacity: int = 1024,
	allocator := context.allocator,
	loc := #caller_location,
) -> mem.Allocator_Error {
	s^ = {
		is_writing = true,
		version    = SERIALIZER_VERSION_LATEST,
		data       = make([dynamic]byte, 0, capacity, allocator, loc) or_return,
	}
	return nil
}

// Warning: doesn't clone the data, make sure it stays available when deserializing!
serializer_init_reader :: proc(s: ^Serializer, data: []byte) {
	s^ = {
		is_writing = false,
		data       = transmute([dynamic]u8)runtime.Raw_Dynamic_Array {
			data = (transmute(runtime.Raw_Slice)data).data,
			len = len(data),
			cap = len(data),
			allocator = runtime.nil_allocator(),
		},
	}
}

serializer_clear :: proc(s: ^Serializer) {
	s.read_offset = 0
	clear(&s.data)
}

// The reader doesn't need to be destroyed, since it doesn't own the memory
serializer_destroy_writer :: proc(s: ^Serializer, loc := #caller_location) {
	assert(s.is_writing)
	delete(s.data, loc)
}

serializer_data :: proc(s: Serializer) -> []u8 {
	return s.data[:]
}

_serializer_debug_scope_indent :: proc(depth: int) {
	for _ in 0 ..< depth do runtime.print_string("  ")
}

_serializer_debug_scope_end :: proc(s: ^Serializer, name: string) {
	when ODIN_DEBUG do if s.debug.print_scope {
		s.debug.depth -= 1
		_serializer_debug_scope_indent(s.debug.depth)
		runtime.print_string("}\n")
	}
}

@(disabled = !ODIN_DEBUG, deferred_in = _serializer_debug_scope_end)
serializer_debug_scope :: proc(s: ^Serializer, name: string) {
	when ODIN_DEBUG do if s.debug.print_scope {
		_serializer_debug_scope_indent(s.debug.depth)
		runtime.print_string(name)
		runtime.print_string(" {")
		runtime.print_string("\n")
		s.debug.depth += 1
	}
}

_serialize_bytes :: proc(s: ^Serializer, data: []byte, loc: runtime.Source_Code_Location) -> bool {
	when ODIN_DEBUG do if s.debug.print_scope {
		_serializer_debug_scope_indent(s.debug.depth)
		fmt.printf("%i bytes, ", len(data))
		if s.is_writing {
			fmt.printf("written: %i\n", len(s.data))
		} else {
			fmt.printf("read: %i/%i\n", s.read_offset, len(s.data))
		}
	}

	if len(data) == 0 {
		return true
	}

	if s.is_writing {
		if _, err := append(&s.data, ..data); err != nil {
			when ODIN_DEBUG {
				panic("Serializer failed to append data", loc)
			}
			return false
		}
	} else {
		if len(s.data) < s.read_offset + len(data) {
			when ODIN_DEBUG {
				panic("Serializer attempted to read past the end of the buffer.", loc)
			}
			return false
		}
		copy(data, s.data[s.read_offset:][:len(data)])
		s.read_offset += len(data)
	}

	return true
}

serialize_opaque :: #force_inline proc(s: ^Serializer, data: ^$T, loc := #caller_location) -> bool {
	return _serialize_bytes(s, #force_inline mem.ptr_to_bytes(data), loc)
}

// Serialize slice, fields are treated as opaque bytes.
serialize_opaque_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
	serializer_debug_scope(s, "opaque slice")
	serialize_slice_info(s, data, loc) or_return
	return _serialize_bytes(s, slice.to_bytes(data^), loc)
}

// Serialize dynamic array, but leaves fields empty.
serialize_slice_info :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
	serializer_debug_scope(s, "slice info")
	num_items := len(data)
	serialize_number(s, &num_items, loc) or_return
	if !s.is_writing {
		data^ = make([]E, num_items, loc = loc)
	}
	return true
}

// Serialize dynamic array, but leaves fields empty.
serialize_dynamic_array_info :: proc(s: ^Serializer, data: ^$T/[dynamic]$E, loc := #caller_location) -> bool {
	serializer_debug_scope(s, "dynamic array info")
	num_items := len(data)
	serialize_number(s, &num_items, loc) or_return
	if !s.is_writing {
		data^ = make([dynamic]E, num_items, num_items, loc = loc)
	}
	return true
}

// Serialize dynamic array, fields are treated as opaque bytes.
serialize_opaque_dynamic_array :: proc(s: ^Serializer, data: ^$T/[dynamic]$E, loc := #caller_location) -> bool {
	serializer_debug_scope(s, "opaque dynamic array")
	serialize_dynamic_array_info(s, data, loc) or_return
	return _serialize_bytes(s, slice.to_bytes(data[:]), loc)
}

serialize_opaque_as :: proc(s: ^Serializer, data: ^$T, $CONVERT_T: typeid, loc := #caller_location) -> bool {
	serializer_debug_scope(s, fmt.tprint(typeid_of(T), "as", typeid_of(CONVERT_T)))
	if s.is_writing {
		d := CONVERT_T(data^)
		serialize_opaque(s, &d, loc) or_return
	} else {
		d: CONVERT_T
		serialize_opaque(s, &d, loc) or_return
		data^ = T(d)
	}
	return true
}

// Automatically converts to little endian
serialize_number :: proc(
	s: ^Serializer,
	data: ^$T,
	loc := #caller_location,
) -> bool where intrinsics.type_is_float(T) ||
	intrinsics.type_is_integer(T) {
	serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))

	// Always
	when ODIN_ENDIAN != .Big {
		// Serialize pointer-sized integers as 64-bit
		switch typeid_of(T) {
		case int:
			return serialize_opaque_as(s, data, i64, loc)
		case uint:
			return serialize_opaque_as(s, data, i64, loc)
		case uintptr:
			return serialize_opaque_as(s, data, i64, loc)
		case:
			return serialize_opaque(s, data, loc)
		}

	} else {
		
	        // odinfmt: disable
        switch typeid_of(T) {
        case int: return serialize_opaque_as(s, data, i64le, loc)
        case i16: return serialize_opaque_as(s, data, i16le, loc)
        case i32: return serialize_opaque_as(s, data, i32le, loc)
        case i64: return serialize_opaque_as(s, data, i64le, loc)
        case i128: return serialize_opaque_as(s, data, i128le, loc)

        case uint: return serialize_opaque_as(s, data, u64le, loc)
        case u16: return serialize_opaque_as(s, data, u16le, loc)
        case u32: return serialize_opaque_as(s, data, u32le, loc)
        case u64: return serialize_opaque_as(s, data, u64le, loc)
        case u128: return serialize_opaque_as(s, data, u128le, loc)
        case uintptr: return serialize_opaque_as(s, data, u64le, loc)

        case f16: return serialize_opaque_as(s, data, f16le, loc)
        case f32: return serialize_opaque_as(s, data, f32le, loc)
        case f64: return serialize_opaque_as(s, data, f64le, loc)

        case:
            return serialize_opaque(s, data, loc)
        }
        // odinfmt: enable
	}
	return false
}


serialize_basic :: proc(
	s: ^Serializer,
	data: ^$T,
	loc := #caller_location,
) -> bool where intrinsics.type_is_enum(T) ||
	intrinsics.type_is_boolean(T) ||
	intrinsics.type_is_bit_set(T) {
	serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))
	return serialize_opaque(s, data, loc)
}


when SERIALIZER_ENABLE_GENERIC {
	serialize_array :: proc(s: ^Serializer, data: ^$T/[$S]$E, loc := #caller_location) -> bool {
		serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
		when intrinsics.type_is_numeric(E) {
			serialize_opaque(s, data, loc) or_return
		} else {
			for &v in data {
				serialize(s, &v, loc) or_return
			}
		}
		return true
	}


	serialize_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
		serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
		serialize_slice_info(s, data, loc) or_return
		for &v in data {
			serialize(s, &v, loc) or_return
		}
		return true
	}


	serialize_string :: proc(s: ^Serializer, data: ^string, loc := #caller_location) -> bool {
		serializer_debug_scope(s, fmt.tprintf("string = \"%s\"", data^))
		return serialize_opaque_slice(s, cast(^[]u8)data, loc)
	}


	serialize_dynamic_array :: proc(s: ^Serializer, data: ^$T/[dynamic]$E, loc := #caller_location) -> bool {
		serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
		serialize_dynamic_array_info(s, data, loc) or_return
		for &v in data {
			serialize(s, &v, loc) or_return
		}
		return true
	}


	serialize_map :: proc(s: ^Serializer, data: ^$T/map[$K]$V, loc := #caller_location) -> bool {
		serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
		num_items := len(data)
		serialize_number(s, &num_items, loc) or_return

		if s.is_writing {
			for k, v in data {
				k_ := k
				v_ := v
				serialize(s, &k_, loc) or_return
				when size_of(V) > 0 {
					serialize(s, &v_, loc) or_return
				}
			}
		} else {
			data^ = make_map_cap(map[K]V, num_items)
			for _ in 0 ..< num_items {
				k: K
				v: V
				serialize(s, &k, loc) or_return
				when size_of(V) > 0 {
					serialize(s, &v, loc) or_return
				}
				data[k] = v
			}
		}

		return true
	}
}

// WARNING: this requires RTTI!
serialize_union_tag :: proc(
	s: ^Serializer,
	value: ^$T,
	loc := #caller_location,
) -> bool where intrinsics.type_is_union(T) {
	serializer_debug_scope(s, "union tag")
	tag: i64le
	if s.is_writing {
		tag = reflect.get_union_variant_raw_tag(value^)
	}
	serialize_basic(s, &tag, loc) or_return
	if !s.is_writing {
		reflect.set_union_variant_raw_tag(value^, tag)
	}
	return true
}


when SERIALIZER_ENABLE_GENERIC {
	serialize :: proc {
		serialize_number,
		serialize_basic,
		serialize_array,
		serialize_slice,
		serialize_string,
		serialize_dynamic_array,
		serialize_map,
		serialize_foo,

		// Add your custom serialization procedures here
		serialize_b2_filter,
		serialize_entity_def,
		serialize_b2_body_def,
		serialize_b2_shape_def,
		serialize_level,
	}
}


//////////////////////////////////////////////////////////////////////////////////////////////
// Example
//


Foo :: struct {
	a:          i32,
	b:          f32,
	name:       string,
	big_buffer: []u8,
}

Bar :: struct {
	foos: [dynamic]Foo,
	data: map[i32]bit_set[0 ..< 8],
}

serialize_foo :: proc(s: ^Serializer, foo: ^Foo, loc := #caller_location) -> bool {
	serializer_debug_scope(s, "foo") // optional
	serialize(s, &foo.a, loc)
	serialize(s, &foo.b, loc)
	serialize(s, &foo.name, loc)
	{
		context.allocator = context.temp_allocator
		serialize(s, &foo.big_buffer, loc)
	}
	return true
}

serialize_bar :: proc(s: ^Serializer, bar: ^Bar, loc := #caller_location) -> bool {
	serializer_debug_scope(s, "bar")
	// you can but don't have to pass the `loc` parameter into the serialize procedures
	serialize(s, &bar.foos)
	serialize(s, &bar.data)
	return true
}

compare_bar :: proc(a, b: Bar) -> bool {
	compare_foo :: proc(a, b: Foo) -> bool {
		if a.name != b.name do return false
		if len(a.big_buffer) != len(b.big_buffer) do return false
		for v, i in a.big_buffer do if v != b.big_buffer[i] do return false
		return a.a == b.a && a.b == b.b
	}

	if len(a.foos) != len(b.foos) do return false
	for v, i in a.foos do if !compare_foo(v, b.foos[i]) do return false

	if len(a.data) != len(b.data) do return false
	for k, va in a.data {
		if vb, ok := b.data[k]; ok {
			if va != vb do return false
		}
	}

	return true
}

serialize_b2_body_def :: proc(s: ^Serializer, body_def: ^b2.BodyDef, loc := #caller_location) -> bool {
	serialize(s, &body_def.type, loc) or_return
	serialize(s, &body_def.position, loc) or_return
	serialize(s, cast(^[2]f32)&body_def.rotation, loc) or_return
	serialize(s, &body_def.linearVelocity, loc) or_return
	serialize(s, &body_def.angularVelocity, loc) or_return
	serialize(s, &body_def.linearDamping, loc) or_return
	serialize(s, &body_def.angularDamping, loc) or_return
	serialize(s, &body_def.gravityScale, loc) or_return
	serialize(s, &body_def.sleepThreshold, loc) or_return
	serialize(s, &body_def.enableSleep, loc) or_return
	serialize(s, &body_def.isBullet, loc) or_return
	serialize(s, &body_def.isAwake, loc) or_return
	serialize(s, &body_def.fixedRotation, loc) or_return
	serialize(s, &body_def.isEnabled, loc) or_return
	serialize(s, &body_def.automaticMass, loc) or_return
	return true
}

serialize_b2_filter :: proc(s: ^Serializer, filter: ^b2.Filter, loc := #caller_location) -> bool {
	serialize(s, &filter.categoryBits, loc) or_return
	serialize(s, &filter.maskBits, loc) or_return
	serialize(s, &filter.groupIndex, loc) or_return
	return true
}

serialize_b2_shape_def :: proc(s: ^Serializer, shape_def: ^b2.ShapeDef, loc := #caller_location) -> bool {

	serialize(s, &shape_def.friction, loc) or_return
	serialize(s, &shape_def.restitution, loc) or_return
	serialize(s, &shape_def.density, loc) or_return
	serialize(s, &shape_def.filter, loc) or_return
	serialize(s, &shape_def.customColor, loc) or_return
	serialize(s, &shape_def.isSensor, loc) or_return
	serialize(s, &shape_def.enableSensorEvents, loc) or_return
	serialize(s, &shape_def.enableContactEvents, loc) or_return
	serialize(s, &shape_def.enableHitEvents, loc) or_return
	serialize(s, &shape_def.enablePreSolveEvents, loc) or_return
	serialize(s, &shape_def.forceContactCreation, loc) or_return
	return true
}

serialize_entity_def :: proc(s: ^Serializer, entity: ^CreateEntityDef, loc := #caller_location) -> bool {

	serialize(s, &entity.type, loc) or_return
	serialize(s, &entity.size, loc) or_return

	serialize(s, &entity.box2d_size, loc) or_return
	serialize(s, &entity.flags, loc) or_return
	serialize(s, &entity.texture_id, loc) or_return
	serialize(s, &entity.static_index, loc) or_return
	serialize(s, &entity.body_def, loc) or_return
	serialize(s, &entity.shape_def, loc) or_return
	serialize(s, &entity.anim_step, loc) or_return
	serialize(s, &entity.angle, loc) or_return
	if s.version >= .added_extra_bytes{
		serialize(s, &entity.extra, loc) or_return
	}
	return true
}


serialize_level :: proc(s: ^Serializer, level: ^Level, loc := #caller_location) -> bool {
	serialize(s, &s.version, loc) or_return
	serialize(s, &level.flags, loc) or_return
	serialize(s, &level.player_index, loc) or_return
	serialize(s, &level.static_indexes, loc) or_return
	serialize(s, &level.entity_defs, loc) or_return

	serialize(s, &level.camera.zoom, loc) or_return
	serialize(s, &level.camera.rotation, loc) or_return

	if s.version >= .added_camera_offset{
		serialize(s, &level.camera.offset, loc) or_return
	}

	serialize(s, &level.entity_maps_serializeable, loc) or_return

	if s.version >= .added_extra_bytes{
		serialize(s, &level.extra, loc) or_return
	}
	if s.version >= .added_background_color{
		serialize(s, &level.background_color, loc) or_return
	}
	return true
}
