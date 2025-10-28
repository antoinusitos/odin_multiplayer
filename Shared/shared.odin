package multiplayer_shared

import "core:log"
import "core:fmt"

import enet "vendor:ENet"
import rl "vendor:raylib"

log_error :: fmt.println

Entity :: struct {
	net_id : u64,
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
	sprite : rl.Texture2D,
	local_player : bool,
	current_move_time : f32,
	move_time : f32,
	can_move : bool,
	target : ^Entity,

	class : Class,
	story : Story,
	gold : int,

	must_select_stat : bool,

	vitality : int, 	//HP
	strength : int,		//MELEE DAMAGE
	intelligence : int, //MAGIC DAMAGE
	chance: int,		//CHANCE
	endurance: int,		//FIRST TO ATTACK + CRIT DAMAGE
	speed : int,		//ATTACK SPEED
	dexterity : int,	//RANGE DAMAGE

	current_xp : int,
	target_xp : int,
	lvl : int,

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

Class :: struct {
	vitality : int, 	//HP
	strength : int,		//MELEE DAMAGE
	intelligence : int, //MAGIC DAMAGE
	chance: int,		//CHANCE
	endurance: int,		//FIRST TO ATTACK + CRIT DAMAGE
	speed : int,		//ATTACK SPEED
	dexterity : int,	//RANGE DAMAGE
}

Warrior :: Class { vitality = 5, strength = 10 }
Mage :: Class { intelligence = 10, vitality = 5 }
Ranger :: Class { dexterity = 10, speed = 5 }

Story :: struct {
	description : string,
	stats : Class,
	gold : int,
}

Greedy :: Story { description = "You inherit your family and lived a greedy life", stats = Class { chance = 20, vitality = -5 }, gold = 20 } 
Clerc :: Story { description = "You lived a prosper life in a temple", stats = Class { vitality = 10, intelligence = 10 }}
Berserk :: Story { description = "...", stats = Class { strength = 25, intelligence = -5 }}
Ninja :: Story { description = "...", stats = Class { speed = 15, endurance = 5 }}
Archer :: Story { description = "...", stats = Class { dexterity = 15, endurance = 5 }}
Paladin :: Story { description = "...", stats = Class { strength = 10, intelligence = 10 }}
Thief :: Story { description = "...", stats = Class { dexterity = 10, chance = 10 }}
Beggar :: Story { description = "...", stats = Class { dexterity = -9, strength = -9, intelligence = -9 }}
Undead :: Story { description = "...", stats = Class { dexterity = -9, strength = -9, intelligence = -9, chance = -9, vitality = -9, endurance = -9, speed = -9 }}

Cell :: struct {
	x : int,
	y : int,
	entity : ^Entity,
	sprite : rl.Texture2D,
}

Entity_Handle :: struct {
	index: u64,
	id: u64,
}

Entity_Kind :: enum {
	nil,
	player,
	tree,
	ai,
}

Game_Step :: enum {
	selection,
	game
}

game_state: Game_State
Game_State :: struct {
	initialized: bool,
	entities: [MAX_ENTITIES]Entity,
	entity_id_gen: u64,
	entity_net_id: u64,
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
	game_step : Game_Step,
}

World_Filler :: struct {
	x : int,
	y : int,
	entity_kind : Entity_Kind,
}

GAME_RES_WIDTH :: 1280//480
GAME_RES_HEIGHT :: 720//270
CELL_WIDTH :: CELLS_NUM_WIDTH * SCREENS_WIDTH
CELL_HEIGHT :: CELLS_NUM_HEIGHT * SCREENS_HEIGHT
SCREENS_WIDTH :: 5
SCREENS_HEIGHT :: 5
MAX_ENTITIES :: 1024
CELL_SIZE :: 32
CELLS_NUM_WIDTH :: 32
CELLS_NUM_HEIGHT :: 17
OFFSET_HEIGHT :: 120

weapon := Item {id = 1, quantity = 1, name = "Sword_1", damage = 20}

all_items : [dynamic]Item

camera : rl.Camera2D

background_sprite : rl.Texture2D
tree_sprite : rl.Texture2D
screen_x := 0
screen_y := 0

a_used := false
b_used := false
c_used := false
d_used := false
e_used := false
f_used := false
g_used := false

world_fillers :: []World_Filler {
	
}

dynamic_world_fillers : [dynamic]World_Filler

send_packet :: proc(peer : ^enet.Peer, data : rawptr, msg_len: uint) {
	packet : ^enet.Packet = enet.packet_create(data, msg_len + 1, {enet.PacketFlag.RELIABLE})
	enet.peer_send(peer, 0, packet)
}

fill_world :: proc() {
	background_sprite = rl.LoadTexture("Dot.png")
	tree_sprite = rl.LoadTexture("Tree.png")

	log_error(CELL_HEIGHT)

	for y := 0; y < CELL_HEIGHT; y += 1 {
		for x := 0; x < CELL_WIDTH; x += 1 {
			game_state.cells[y * CELL_WIDTH + x].x = x
			game_state.cells[y * CELL_WIDTH + x].y = y
			game_state.cells[y * CELL_WIDTH + x].sprite = background_sprite
		}
	}

	for x := 0; x < CELL_WIDTH; x += 1 {
		for y := 0; y < CELL_HEIGHT; y += 1 {
			if y == 0 || y == CELL_HEIGHT - 1 {
				append(&dynamic_world_fillers, World_Filler {x = x, y = y, entity_kind = .tree})
			}
			if x == 0 || x == CELL_WIDTH - 1 {
				append(&dynamic_world_fillers, World_Filler {x = x, y = y, entity_kind = .tree})
			}
		}
	}

	append(&dynamic_world_fillers, World_Filler {x = 2, y = 2, entity_kind = .ai})

	for filler in world_fillers {
		game_state.cells[filler.y * CELL_WIDTH + filler.x].entity = entity_create(filler.entity_kind)
	}

	for filler in dynamic_world_fillers {
		game_state.cells[filler.y * CELL_WIDTH + filler.x].entity = entity_create(filler.entity_kind)
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
	return fmt.ctprint("PLAYER:INFO:", player.net_id, "|", player.position.x, "|", player.position.y, sep = "")
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

	switch kind {
		case .nil: break
		case .player: setup_player(new_entity)
		case .tree: setup_tree(new_entity)
		case .ai: setup_ai(new_entity)
	}

	new_entity.net_id = game_state.entity_net_id
	game_state.entity_net_id += 1
	log_error("create net id ", game_state.entity_net_id, " for ", kind)

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
	entity.kind = .player
	entity.position = rl.Vector2 {1, 1}
	entity.sprite_size = CELL_SIZE
	entity.sprite = rl.LoadTexture("Player2.png")
	entity.color = rl.WHITE
	entity.move_time = 0.15
	entity.name = "player"

	entity.vitality = 10
	entity.strength = 10
	entity.intelligence = 10
	entity.chance = 10
	entity.endurance = 10
	entity.speed = 10
	entity.dexterity = 10

	entity.max_health = f32(entity.vitality) * 100
	entity.current_health = entity.max_health

	entity.current_xp = 0
	entity.target_xp = 100
	entity.lvl = 1

	apply_class(entity, Warrior)
	apply_story(entity, Greedy)

	entity.update = proc(entity: ^Entity) {
		if !entity.local_player {
			return
		}

		if rl.IsKeyUp(rl.KeyboardKey.A) && a_used {
			a_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.B) && b_used {
			b_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.C) && c_used {
			c_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.D) && d_used {
			d_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.E) && e_used {
			e_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.F) && f_used {
			f_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.G) && g_used {
			g_used = false
		}

		if entity.must_select_stat {
			return
		}

		if rl.IsKeyDown(rl.KeyboardKey.E) && !e_used {
			e_used = true
			if game_state.cells[int(entity.position.y) * CELL_WIDTH + int(entity.position.x + 1)].entity != nil {
				interact_with(entity, game_state.cells[int(entity.position.y) * CELL_WIDTH + int(entity.position.x + 1)].entity)
			}
			if game_state.cells[int(entity.position.y) * CELL_WIDTH + int(entity.position.x - 1)].entity != nil {
				interact_with(entity, game_state.cells[int(entity.position.y) * CELL_WIDTH + int(entity.position.x - 1)].entity)
			}
			if game_state.cells[int(entity.position.y + 1) * CELL_WIDTH + int(entity.position.x)].entity != nil {
				interact_with(entity, game_state.cells[int(entity.position.y + 1) * CELL_WIDTH + int(entity.position.x)].entity)
			}
			if game_state.cells[int(entity.position.y - 1) * CELL_WIDTH + int(entity.position.x)].entity != nil {
				interact_with(entity, game_state.cells[int(entity.position.y - 1) * CELL_WIDTH + int(entity.position.x)].entity)
			}
		}

		if rl.IsKeyUp(rl.KeyboardKey.A) && a_used {
			a_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.B) && b_used {
			b_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.C) && c_used {
			c_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.D) && d_used {
			d_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.F) && f_used {
			f_used = false
		}
		if rl.IsKeyUp(rl.KeyboardKey.G) && g_used {
			g_used = false
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
			if rl.IsKeyDown(rl.KeyboardKey.A) && !a_used {
				movement_x -= 1
				update_player = true
			}
			else if rl.IsKeyDown(rl.KeyboardKey.D) && !d_used {
				movement_x += 1
				update_player = true
			}
			if rl.IsKeyDown(rl.KeyboardKey.W) && movement_x == 0 {
				movement_y -= 1
				update_player = true
			}
			else if rl.IsKeyDown(rl.KeyboardKey.S) && movement_x == 0 {
				movement_y += 1
				update_player = true
			}

			if update_player {
				if entity.position.x + movement_x >= 0 {
					if game_state.cells[int(entity.position.y) * CELL_WIDTH + int(entity.position.x + movement_x)].entity == nil {
						entity.position.x += movement_x
					}
				}
				if entity.position.y + movement_y >= 0 {
					if game_state.cells[int(entity.position.y + movement_y) * CELL_WIDTH + int(entity.position.x)].entity == nil {
						entity.position.y += movement_y
					}
				}

				entity.can_move = false
				message := player_to_string(entity)
				send_packet(entity.peer, rawptr(message), len(message))

				if int(entity.position.x) >= screen_x * CELLS_NUM_WIDTH + CELLS_NUM_WIDTH {
					screen_x += 1
				}
				else if int(entity.position.x) < screen_x * CELLS_NUM_WIDTH {
					screen_x -= 1
				}

				if int(entity.position.y) >= screen_y * CELLS_NUM_HEIGHT + CELLS_NUM_HEIGHT { //entity.position.y * CELL_SIZE >= camera.target.y + 720 {
					screen_y += 1
				}
				else if int(entity.position.y) < screen_y * CELLS_NUM_HEIGHT { //entity.position.y * CELL_SIZE < camera.target.y {
					screen_y -= 1
				}
			}
		}
	}
	entity.draw = proc(entity: ^Entity) {
		default_draw_based_on_entity_data(entity)
	}
}

setup_tree :: proc(entity: ^Entity) {
	entity.max_health = 100
	entity.current_health = entity.max_health
	entity.kind = .tree
	entity.sprite_size = CELL_SIZE
	entity.sprite = tree_sprite
	entity.color = rl.WHITE
	entity.update = proc(entity: ^Entity) {
	}
	entity.draw = proc(entity: ^Entity) {
		default_draw_based_on_entity_data(entity)
	}
}

setup_ai :: proc(entity: ^Entity) {
	entity.max_health = 100
	entity.current_health = entity.max_health
	entity.kind = .ai
	entity.sprite_size = CELL_SIZE
	entity.sprite = rl.LoadTexture("Player.png")
	entity.color = rl.BLUE
	entity.name = "ai"
	entity.update = proc(entity: ^Entity) {
	}
	entity.draw = proc(entity: ^Entity) {
		default_draw_based_on_entity_data(entity)
	}
}

//LOCAL
interact_with :: proc(entity: ^Entity, with_entity: ^Entity) {
	#partial switch with_entity.kind {
		case .ai :
			message := fmt.ctprint("ATTACK:", entity.net_id, "|", with_entity.net_id, sep = "")
			send_packet(entity.peer, rawptr(message), len(message)) 
			//give_xp(entity, 10)
	}
}

give_xp :: proc(entity: ^Entity, amount: int) {
	entity.current_xp += amount
	for entity.current_xp >= entity.target_xp {
		entity.current_xp = entity.current_xp - entity.target_xp
		entity.lvl += 1
		entity.must_select_stat = true
	}
}

apply_class :: proc(entity: ^Entity, class : Class)
{
	entity.vitality += class.vitality
	entity.strength += class.strength
	entity.intelligence += class.intelligence
	entity.chance += class.chance
	entity.endurance += class.endurance
	entity.speed += class.speed
	entity.dexterity += class.dexterity
}

apply_story :: proc(entity: ^Entity, story : Story)
{
	entity.vitality += story.stats.vitality
	entity.strength += story.stats.strength
	entity.intelligence += story.stats.intelligence
	entity.chance += story.stats.chance
	entity.endurance += story.stats.endurance
	entity.speed += story.stats.speed
	entity.dexterity += story.stats.dexterity
	entity.gold += story.gold
}

begin_draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	rl.BeginMode2D(camera)

	draw_x := 0
	for y := screen_y * CELLS_NUM_HEIGHT ; y < (screen_y * CELLS_NUM_HEIGHT) + CELLS_NUM_HEIGHT; y += 1 {
		for x := screen_x * CELLS_NUM_WIDTH;  x < (screen_x * CELLS_NUM_WIDTH) + CELLS_NUM_WIDTH; x += 1 {
			cell := game_state.cells[y * CELL_WIDTH + x]
			if cell.entity != nil {
				rl.DrawTextureRec(cell.entity.sprite, {0, 0, 32, 32}, {f32(draw_x * CELL_SIZE), f32(y * CELL_SIZE + OFFSET_HEIGHT)}, cell.entity.color)
			}
			else {
				rl.DrawTextureRec(cell.sprite, {0, 0, 32, 32}, {f32(draw_x * CELL_SIZE), f32(y * CELL_SIZE + OFFSET_HEIGHT)}, rl.WHITE)
			}
			draw_x += 1
		}
		draw_x = 0
	}

	/*for cell in game_state.cells {
		if cell.entity != nil {
			rl.DrawTextureRec(cell.entity.sprite, {0, 0, 32, 32}, {f32(cell.x * CELL_SIZE), f32(cell.y * CELL_SIZE)}, cell.entity.color)
		}
		else {
			rl.DrawTextureRec(cell.sprite, {0, 0, 32, 32}, {f32(cell.x * CELL_SIZE), f32(cell.y * CELL_SIZE)}, rl.WHITE)
		}
	}*/
}

main :: proc() {
}