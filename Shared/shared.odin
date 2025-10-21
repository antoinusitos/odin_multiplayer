package multiplayer_shared

import "core:fmt"

import enet "vendor:enet"
import rl "vendor:raylib"

log_error :: fmt.println

Entity :: struct {
	net_id : int,
	handle: Entity_Handle,
	kind: Entity_Kind,
	position : rl.Vector2,
	current_health : f32,
	peer : ^enet.Peer,
	allocated : bool,
	max_health : f32,
	items : [10]Item,
	name : string,
	color : rl.Color,
	sprite_size : f32,
	local_player : bool,
	current_move_time : f32,
	move_time : f32,
	can_move : bool,

	update : proc(^Entity),
	draw: proc(^Entity),
}

Item :: struct {
	id : int,
	allocated : bool,
	quantity : int,
	name : string,
	damage : int,
}

Cell :: struct {
	x : int,
	y : int,
	entity : ^Entity,
}

Entity_Handle :: struct {
	index: u64,
	id: u64,
}

Entity_Kind :: enum {
	nil,
	player,
	tree,
}

game_state: Game_State
Game_State :: struct {
	initialized: bool,
	entities: [MAX_ENTITIES]Entity,
	entity_id_gen: u64,
	entity_top_count: u64,
	world_name: string,
	player_handle: Entity_Handle,
	turn_length: f32,
	current_turn_length: f32,
	cells : [CELL_WIDTH * CELL_HEIGHT]Cell,
	turn_played : bool,
	can_play : bool,
	choosing_action : bool,
	choosing_actions_strings : [dynamic]string,
}

CELL_WIDTH :: 100
CELL_HEIGHT :: 100
MAX_ENTITIES :: 1024
CELL_SIZE :: 32

weapon := Item {id = 1, quantity = 1, name = "Sword_1", damage = 1}

all_items : [dynamic]Item

camera : rl.Camera2D

send_packet :: proc(peer : ^enet.Peer, data : rawptr, msg_len: uint) {
	packet : ^enet.Packet = enet.packet_create(data, msg_len + 1, {enet.PacketFlag.RELIABLE})
	enet.peer_send(peer, 0, packet)
}

fill_world :: proc() {
	for y := 0; y < CELL_HEIGHT; y += 1 {
		for x := 0; x < CELL_WIDTH; x += 1 {
			game_state.cells[y * CELL_WIDTH + x].x = x
			game_state.cells[y * CELL_WIDTH + x].y = y
		}
	}
}

fill_items :: proc() {
	append(&all_items, weapon)
}

get_item_with_id :: proc(looking_id: int) -> Item {
	for item in all_items {
		if item.id == looking_id {
			return item
		}
	}
	return Item {}
}

player_to_string :: proc(player : ^Entity) -> cstring {
	return fmt.ctprint(player.net_id, "|", player.position.x, "|", player.position.y, sep = "")
}

entity_create :: proc(kind: Entity_Kind) -> ^Entity {
	new_index : int = -1
	new_entity: ^Entity = nil
	for &entity, index in game_state.entities {
		if !entity.allocated {
			new_entity = &entity
			new_index = int(index)
			break
		}
	}
	if new_index == -1 {
		log_error("out of entities, probably just double the MAX_ENTITIES")
		return nil
	}

	game_state.entity_top_count += 1
	
	// then set it up
	new_entity.allocated = true

	game_state.entity_id_gen += 1
	new_entity.handle.id = game_state.entity_id_gen
	new_entity.handle.index = u64(new_index)

	#partial switch kind {
		case .nil: break
		case .player: setup_player(new_entity)
	}

	return new_entity
}

entity_destroy :: proc(entity: ^Entity) {
	entity^ = {} // it's really that simple
}

place_entity_on_cell :: proc(entity: ^Entity, cell : ^Cell) {
	entity.position = rl.Vector2 {f32(cell.x * CELL_SIZE), f32(cell.y * CELL_SIZE)}
}

get_entity_on_cell :: proc(x: int, y: int) -> ^Entity {
	return game_state.cells[y * CELL_WIDTH + x].entity
}

default_draw_based_on_entity_data :: proc(entity: ^Entity) {
	rl.DrawRectangleV(entity.position, {entity.sprite_size, entity.sprite_size}, entity.color)
}

setup_player :: proc(entity: ^Entity) {
	entity.max_health = 100
	entity.current_health = entity.max_health
	entity.kind = .player
	entity.position = rl.Vector2 {32, 32}
	entity.sprite_size = CELL_SIZE
	entity.color = rl.GREEN
	entity.move_time = 0.15
	entity.update = proc(entity: ^Entity) {
		if !entity.local_player {
			return
		}

		if !entity.can_move {
			entity.current_move_time -= rl.GetFrameTime()
			if entity.current_move_time <= 0 {
				entity.current_move_time = entity.move_time
				entity.can_move = true
			}
		}
		else {
			update_player := false

			movement_x : f32 = 0
			movement_y : f32 = 0
			if rl.IsKeyDown(rl.KeyboardKey.A) {
				movement_x -= CELL_SIZE
				update_player = true
			}
			else if rl.IsKeyDown(rl.KeyboardKey.D) {
				movement_x += CELL_SIZE
				update_player = true
			}
			if rl.IsKeyDown(rl.KeyboardKey.W) && movement_x == 0 {
				movement_y -= CELL_SIZE
				update_player = true
			}
			else if rl.IsKeyDown(rl.KeyboardKey.S) && movement_x == 0 {
				movement_y += CELL_SIZE
				update_player = true
			}

			if update_player {
				if entity.position.x + movement_x >= 0 {
					entity.position.x += movement_x
				}
				if entity.position.y + movement_y >= 0 {
					entity.position.y += movement_y
				}

				entity.can_move = false
				message := player_to_string(entity)
				send_packet(entity.peer, rawptr(message), len(message))

				if entity.position.x >= camera.target.x + 1280 {
					camera.target.x += 1280
				}
				else if entity.position.x < camera.target.x {
					camera.target.x -= 1280
				}

				if entity.position.y >= camera.target.y + 720 {
					camera.target.y += 720
				}
				else if entity.position.y < camera.target.y {
					camera.target.y -= 720
				}
			}
		}
	}
	entity.draw = proc(entity: ^Entity) {
		log_error("draw")
		default_draw_based_on_entity_data(entity)
	}
}

main :: proc() {
}