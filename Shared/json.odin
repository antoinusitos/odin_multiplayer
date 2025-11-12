/*

This is a json helper to read maps from Tiled Software

*/

package multiplayer_shared

import "core:encoding/json"
import "core:log"
import "core:os"
import "core:strings"

Map_Layer :: struct {
	data : []int,
    height : int,
    id : int,
    name : string,
    opacity : int,
    type : string,
    visible : bool,
    width : int,
    x : int,
    y : int
}

Object_Layer :: struct {
    class : string,
    draworder : string,
    id : int,
    name : string,
    objects: []Map_Object,
    opacity : int,
    type : string,
    visible : bool,
    x : int,
    y : int,
}

Map_Object :: struct {
    height : int,
    id : int,
    name : string,
    point : bool,
    properties : []Object_Property,
    rotation : int,
    type : string,
    visible : bool,
    width : int,
    x : f32,
    y : f32
}

Object_Property :: struct {
    name : string,
    type : string,
    value : int
}

Tile_Set :: struct {
    firstgid : int,
    source : string
}

Map_Info :: struct {
	compressionlevel : int,
    infinite : bool,
    layers : []Map_Layer,
    object_layer : Object_Layer,
    monster_layer : Object_Layer,
    nextlayerid : int,
    nextobjectid : int,
    orientation : string,
    renderorder : string,
    tiledversion : string,
    tileheight : int,
    tilesets : []Tile_Set,
    tilewidth : int,
    type : string,
    version : string,
    width : int
}

map_from_file :: proc(filepath : string) -> Map_Info {
    map_info: Map_Info

    if json_data, ok := os.read_entire_file(filepath, context.temp_allocator); ok {
        if json.unmarshal(json_data, &map_info) == nil {
            // my_struct now contains
            // the data from my_struct_file.
        } else {
            log.error("Failed to unmarshal JSON")
        }
    } else {
        log.error("Failed to read my_struct_file")
    }

	return map_info
}