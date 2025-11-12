package multiplayer_shared

import "core:unicode/utf8/utf8string"
import "core:unicode"
import "core:math"
import "core:log"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

import enet "vendor:ENet"
import rl "vendor:raylib"

log_error :: fmt.println

Entity :: struct {
	net_id : u64,
	init : bool,
	local_id : int,
	handle: Entity_Handle,
	kind: Entity_Kind,
	position : rl.Vector2,
	current_health : f32,
	peer : ^enet.Peer,
	allocated : bool,
	max_health : f32,
	items : [10]Item,
	item_index : int,
	name : string,
	color : rl.Color,
	sprite_size : f32,
	sprite : rl.Texture2D,
	local_player : bool,
	current_move_time : f32,
	move_time : f32,
	can_move : bool,

	can_attack : bool,
	target : ^Entity,
	last_attack : f32,

	cell_x : int,
	cell_y : int,

	ai_steps : [dynamic]AI_Step,

	quests : [dynamic]Quest,

	class : Class,
	class_index : int,
	story : Story,
	story_index : int,
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

	locked : bool,

	update : proc(^Entity),
	draw: proc(^Entity),
}

Item :: struct {
	id : int,
	item_type : Item_Type,
	allocated : bool,
	quantity : int,
	name : string,
	damage : int,
	linked_id : int,
	usage : int,
	data : int,
}

Item_Type :: enum {
	weapon,
	key,
	lockpick,
}

Quest_Type :: enum {
	kill,
}

Quest :: struct {
	quest_type : Quest_Type,
	num : int,
	completion : int,
	id : int,
	object_id : int,
	description : string,
	name : string,
	xp_reward : int,
	completed : bool
}

AI_Step_Type :: enum {
	say,
	give,
	quest
}

AI_Step :: struct {
	type : AI_Step_Type,
	arg : int,
}

AI_Text :: struct {
	id : int,
	text : string,
}

Class :: struct {
	name : string,
	stats_string : string,
	vitality : int, 	//HP
	strength : int,		//MELEE DAMAGE
	intelligence : int, //MAGIC DAMAGE
	chance: int,		//CHANCE
	endurance: int,		//FIRST TO ATTACK + CRIT DAMAGE
	speed : int,		//ATTACK SPEED
	dexterity : int,	//RANGE DAMAGE
}

Story :: struct {
	name : string,
	stats_string : string,
	description : string,
	stats : Class,
	gold : int,
}

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
	enviro,
	door,
	monster,
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
	logs : [dynamic]string,
	game_step : Game_Step,
}

World_Filler :: struct {
	x : int,
	y : int,
	entity_kind : Entity_Kind,
	override_sprite : ^rl.Texture2D
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

/// DATA

Warrior :: Class { name = "Warrior", vitality = 5, strength = 10, stats_string = "(vitality +5, strength +10)" }
Warrior_sprite : rl.Texture2D
Mage :: Class { name = "Mage", intelligence = 10, vitality = 5, stats_string = "(intelligence +10, vitality +5)" }
Mage_sprite : rl.Texture2D
Ranger :: Class { name = "Ranger", dexterity = 10, speed = 5, stats_string = "(dexterity +10, speed +5)" }
Ranger_sprite : rl.Texture2D

classes := [3]Class {Warrior, Mage, Ranger}

Greedy :: Story { name = "Greedy", description = "You inherited your family and lived a greedy life", stats = Class { chance = 20, vitality = -5 }, gold = 20, stats_string = "chance +20\nvitality -5\ngold +20" } 
Clerc :: Story { name = "Clerc", description = "You lived a prosper life in a temple", stats = Class { vitality = 10, intelligence = 10 }, stats_string = "vitality +10\nintelligence +10"}
Berserk :: Story { name = "Berserk", description = "You are the strongest person of the world", stats = Class { strength = 25, intelligence = -5 }, stats_string = "strength +25\nintelligence -5"}
Ninja :: Story { name = "Ninja", description = "You lived in a wood, spending years of combat learning", stats = Class { speed = 15, endurance = 5 }, stats_string = "speed +15\nendurance +5"}
Archer :: Story { name = "Archer", description = "You are the best hunter of your village", stats = Class { dexterity = 15, endurance = 5 }, stats_string = "dexterity +15\nendurance +5"}
Paladin :: Story { name = "Paladin", description = "Sent by your church, you want to destroy the evil", stats = Class { strength = 10, intelligence = 10 }, stats_string = "strength +10\nintelligence +10"}
Thief :: Story { name = "Thief", description = "You lived a poor life in a big city, stealing to survive", stats = Class { dexterity = 10, chance = 10 }, stats_string = "dexterity +10\nchance +10"}
Beggar :: Story { name = "Beggar", description = "You are a peasant and you don't know what you are\ndoing", stats = Class { dexterity = -9, strength = -9, intelligence = -9 }, stats_string = "dexterity -9\nstrength -9\nintelligence -9"}
Undead :: Story { name = "Undead", description = "You came back from the dead and now you a second\nchance", stats = Class { }, stats_string = "dexterity = 1\nstrength = 1\nintelligence = 1\nchance = 1\nvitality = 1\nendurance = 1\nspeed = 1"}

stories := [9]Story {Greedy, Clerc, Berserk, Ninja, Archer, Paladin, Thief, Beggar, Undead}

weapon := Item {id = 1, item_type = .weapon, quantity = 1, name = "Sword_1", damage = 20}
key_0 := Item {id = 2, item_type = .key, quantity = 1, name = "Key_0", linked_id = 4}
Lockpick_0 := Item {id = 3, item_type = .lockpick, quantity = 1, name = "Lockpick_0", usage = 5, data = 10, damage = 1}

all_items : [dynamic]Item

text_0 := AI_Text {id = 0, text = "oh.. it's you.. Here's a key. You can open the cell next to this one."}

all_texts : [dynamic]AI_Text

quest_0 := Quest{ id = 0, quest_type = .kill, num = 3, object_id = 1, name = "quest_0", description = "Kill 3 monsters", xp_reward = 50}

all_quests : [dynamic]Quest

/// GLOBALS

camera : rl.Camera2D

background_sprite : rl.Texture2D
tree_sprite : rl.Texture2D
grid_sprite : rl.Texture2D
door_sprite : rl.Texture2D
door_opened_sprite : rl.Texture2D
window_sprite : rl.Texture2D
wall_sprite : rl.Texture2D
monster_sprite : rl.Texture2D

menu_music : rl.Music
world_music : rl.Music
key_audio : rl.Sound

screen_x := 0
screen_y := 0

dynamic_world_fillers : [dynamic]World_Filler

send_packet :: proc(peer : ^enet.Peer, data : rawptr, msg_len: uint) {
	packet : ^enet.Packet = enet.packet_create(data, msg_len + 1, {enet.PacketFlag.RELIABLE})
	enet.peer_send(peer, 0, packet)
}

fill_world :: proc() {

	log_error(split_text("azertyuiopqsdfghjklmww", 4))

	map_info : Map_Info = map_from_file("../Tiled/Map.tmj")

	background_sprite = rl.LoadTexture("../Res/Dot.png")
	tree_sprite = rl.LoadTexture("../Res/Tree.png")
	grid_sprite = rl.LoadTexture("../Res/grid.png")
	door_sprite = rl.LoadTexture("../Res/door.png")
	door_opened_sprite = rl.LoadTexture("../Res/door_opened.png")
	window_sprite = rl.LoadTexture("../Res/window.png")
	wall_sprite = rl.LoadTexture("../Res/wall.png")

	Warrior_sprite = rl.LoadTexture("../Res/Warrior.png")
	Mage_sprite = rl.LoadTexture("../Res/Mage.png")
	Ranger_sprite = rl.LoadTexture("../Res/Ranger.png")

	monster_sprite = rl.LoadTexture("../Res/Ranger.png")

	menu_music = rl.LoadMusicStream("../Res/Title.wav")
	world_music = rl.LoadMusicStream("../Res/World1.wav")

	key_audio = rl.LoadSound("../Res/spring.wav")

	for y := 0; y < CELL_HEIGHT; y += 1 {
		for x := 0; x < CELL_WIDTH; x += 1 {
			game_state.cells[y * CELL_WIDTH + x].x = x
			game_state.cells[y * CELL_WIDTH + x].y = y
			game_state.cells[y * CELL_WIDTH + x].sprite = background_sprite
		}
	}

	append(&dynamic_world_fillers, World_Filler {x = 4, y = 3, entity_kind = .ai})

	for object in map_info.monster_layer.objects {
		if strings.contains(object.name, "Monster")
		{
			id := 0
			x_found := 0
			y_found := 0
			for prop in object.properties {
				if prop.name == "x" {
					x_found = prop.value
				}
				else if prop.name == "y" {
					y_found = prop.value
				}
			}
			append(&dynamic_world_fillers, World_Filler {x = x_found, y = y_found, entity_kind = .monster})
		}
	}

	copied_array : [dynamic]int
	for copied_y := (CELL_HEIGHT - 1); copied_y >= 0; copied_y -= 1 {
		for copied_x := 0; copied_x < CELL_WIDTH; copied_x += 1 {
			id := map_info.layers[0].data[copied_y * CELL_WIDTH + copied_x]
			if id == 50 {
				append(&dynamic_world_fillers, World_Filler {x = copied_x, y = copied_y, entity_kind = .tree})
			}
			else if id == 153 {
				append(&dynamic_world_fillers, World_Filler {x = copied_x, y = copied_y, entity_kind = .enviro, override_sprite = &grid_sprite})
			}
			else if id == 200 {
				append(&dynamic_world_fillers, World_Filler {x = copied_x, y = copied_y, entity_kind = .door})
			}
			else if id == 844 {
				append(&dynamic_world_fillers, World_Filler {x = copied_x, y = copied_y, entity_kind = .enviro, override_sprite = &wall_sprite})
			}
			else if id == 846 {
				append(&dynamic_world_fillers, World_Filler {x = copied_x, y = copied_y, entity_kind = .enviro, override_sprite = &window_sprite})
			}
		}
	}

	for filler in dynamic_world_fillers {
		game_state.cells[filler.y * CELL_WIDTH + filler.x].entity = entity_create(filler.entity_kind)
		game_state.cells[filler.y * CELL_WIDTH + filler.x].entity.cell_x = filler.x
		game_state.cells[filler.y * CELL_WIDTH + filler.x].entity.cell_y = filler.y
		if filler.override_sprite != nil {
			game_state.cells[filler.y * CELL_WIDTH + filler.x].entity.sprite = filler.override_sprite^
		}
	}

	for object in map_info.object_layer.objects {
		if strings.contains(object.name, "DOOR")
		{
			id := 0
			for prop in object.properties {
				if prop.name == "LOCKED" {
					x := math.ceil_f32(f32(object.x) / 32) - 1
					y := math.ceil_f32(f32(object.y) / 32) - 1
					game_state.cells[int(y) * CELL_WIDTH + int(x)].entity.locked = bool(prop.value)
					if game_state.cells[int(y) * CELL_WIDTH + int(x)].entity.locked == false {
						game_state.cells[int(y) * CELL_WIDTH + int(x)].entity.sprite = door_opened_sprite
					}
					game_state.cells[int(y) * CELL_WIDTH + int(x)].entity.local_id = id
				}
				else if prop.name == "0_id" {
					id = prop.value
				}
			}
		}
	}
}

fill_all :: proc (){
	fill_items()
	fill_texts()
	fill_quests()
	fill_world()
}

fill_items :: proc() {
	append(&all_items, weapon)
	append(&all_items, key_0)
	append(&all_items, Lockpick_0)
}

fill_texts :: proc() {
	append(&all_texts, text_0)
}

fill_quests :: proc() {
	append(&all_quests, quest_0)
}

get_item_with_id :: proc(looking_id: int) -> Item {
	for item in all_items {
		if item.id == looking_id {
			return item
		}
	}
	return Item {}
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
		case .enviro: setup_enviro(new_entity)
		case .door: setup_door(new_entity)
		case .monster: setup_monster(new_entity)
	}

	new_entity.net_id = game_state.entity_net_id
	game_state.entity_net_id += 1
	//log_error("create net id ", game_state.entity_net_id, " for ", kind)

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
	entity.position = rl.Vector2 {8, 3}
	entity.sprite_size = CELL_SIZE
	entity.sprite = Warrior_sprite
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

	//apply_class(entity, Warrior)
	//apply_story(entity, Greedy)

	entity.update = proc(entity: ^Entity) {
		if !entity.local_player {
			return
		}

		if entity.must_select_stat {
			return
		}

		if rl.IsKeyPressed(rl.KeyboardKey.I) {
			entity.item_index += 1
			if entity.item_index >= 10 {
				entity.item_index = 0
			}
			message := fmt.ctprint("PLAYER:ITEM_INDEX:", entity.net_id, "|", entity.item_index, sep = "")
			send_packet(entity.peer, rawptr(message), len(message))
		}

		if rl.IsKeyPressed(rl.KeyboardKey.E) {
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

		if !entity.can_attack {
			entity.last_attack -= rl.GetFrameTime()
			if entity.last_attack <= 0 {
				entity.last_attack = 1 - f32(entity.speed / 100)
				entity.can_attack = true
			}
		}

		if entity.can_attack && entity.target != nil {
			if entity.current_health <= 0 {
				entity.target = nil
			}
			else
			{
				entity.can_attack = false
				message := fmt.ctprint("ATTACK:", entity.net_id, "|", entity.target.net_id, sep = "")
				send_packet(entity.peer, rawptr(message), len(message))
			}
		}

		if !entity.can_move {
			entity.current_move_time -= rl.GetFrameTime()
			if entity.current_move_time <= 0 {
				entity.current_move_time = entity.move_time
				entity.can_move = true
			}
		}
		else if entity.init {
			update_player := false

			movement_x : f32 = 0
			movement_y : f32 = 0
			if rl.IsKeyPressed(rl.KeyboardKey.A) {
				movement_x -= 1
				update_player = true
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.D) {
				movement_x += 1
				update_player = true
			}
			if rl.IsKeyPressed(rl.KeyboardKey.W) && movement_x == 0 {
				movement_y -= 1
				update_player = true
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.S) && movement_x == 0 {
				movement_y += 1
				update_player = true
			}

			if update_player {
				if movement_x != 0 && entity.position.x + movement_x >= 0 {
					found_entity := game_state.cells[int(entity.position.y) * CELL_WIDTH + int(entity.position.x + movement_x)].entity
					if found_entity == nil {
						entity.position.x += movement_x
					}
					else if found_entity.kind == .door {
						if found_entity.locked == false {
							entity.position.x += movement_x
						}
						else {
							done := false
							for item in entity.items {
								if item.linked_id == found_entity.local_id {
									//append(&game_state.logs, "used key to unlock the door")
									add_log("used key to unlock the door")
									found_entity.sprite = door_opened_sprite
									found_entity.locked = false
									done = true
									break
								}
							}
							if !done {
								if entity.items[entity.item_index].allocated {
									if entity.items[entity.item_index].item_type == .lockpick {
										entity.items[entity.item_index].usage -= 1
										add_log("you try to lockpick the door")
										//append(&game_state.logs, "you try to lockpick the door")
										rand := int(rl.GetRandomValue(0, 100))
										if rand < entity.items[entity.item_index].data + entity.chance / 2 {
											add_log("you unlocked the door")
											//append(&game_state.logs, "you unlocked the door")
											found_entity.sprite = door_opened_sprite
											found_entity.locked = false
										}
										if entity.items[entity.item_index].usage <= 0 {
											entity.items[entity.item_index].allocated = false
											add_log("lockpick broke")
											//append(&game_state.logs, "lockpick broke")
										}
										done = true
									}
								}
							}
						}
					}
				}
				if movement_y != 0 && entity.position.y + movement_y >= 0 {
					found_entity := game_state.cells[int(entity.position.y + movement_y) * CELL_WIDTH + int(entity.position.x)].entity
					if found_entity == nil {
						entity.position.y += movement_y
					}
					else if found_entity.kind == .door {
						if found_entity.locked == false {
							entity.position.y += movement_y
						}
						else {
							done := false
							rl.PlaySound(key_audio)
							for item in entity.items {
								if item.linked_id == found_entity.local_id {
									add_log("used key to unlock the door")
									//append(&game_state.logs, "used key to unlock the door")
									found_entity.sprite = door_opened_sprite
									found_entity.locked = false
									done = true
									break
								}
							}
							if !done {
								if entity.items[entity.item_index].allocated {
									if entity.items[entity.item_index].item_type == .lockpick {
										entity.items[entity.item_index].usage -= 1
										add_log("you try to lockpick the door")
										//append(&game_state.logs, "you try to lockpick the door")
										rand := int(rl.GetRandomValue(0, 100))
										if rand < entity.items[entity.item_index].data + entity.chance / 2 {
											add_log("you unlocked the door")
											//append(&game_state.logs, "you unlocked the door")
											found_entity.sprite = door_opened_sprite
											found_entity.locked = false
										}
										if entity.items[entity.item_index].usage <= 0 {
											entity.items[entity.item_index].allocated = false
											add_log("lockpick broke")
											//append(&game_state.logs, "lockpick broke")
										}
										done = true
									}
								}
							}
						}
					}
				}

				entity.can_move = false
				message := fmt.ctprint("PLAYER:UPDATE:", entity.net_id, "|", entity.position.x, "|", entity.position.y, sep = "")
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

setup_enviro :: proc(entity: ^Entity) {
	entity.max_health = 100
	entity.current_health = entity.max_health
	entity.kind = .enviro
	entity.sprite_size = CELL_SIZE
	entity.sprite = window_sprite
	entity.color = rl.WHITE
	entity.update = proc(entity: ^Entity) {
	}
	entity.draw = proc(entity: ^Entity) {
		default_draw_based_on_entity_data(entity)
	}
}

setup_door :: proc(entity: ^Entity) {
	entity.max_health = 100
	entity.current_health = entity.max_health
	entity.kind = .door
	entity.sprite_size = CELL_SIZE
	entity.sprite = door_sprite
	entity.color = rl.WHITE
	entity.locked = false
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
	entity.sprite = rl.LoadTexture("../Res/Player.png")
	entity.color = rl.BLUE
	entity.name = "ai"
	append(&entity.ai_steps, AI_Step{type = .say, arg = 0})
	append(&entity.ai_steps, AI_Step{type = .give, arg = 3})
	append(&entity.ai_steps, AI_Step{type = .give, arg = 2})
	append(&entity.ai_steps, AI_Step{type = .quest, arg = 0})
	entity.update = proc(entity: ^Entity) {
	}
	entity.draw = proc(entity: ^Entity) {
		default_draw_based_on_entity_data(entity)
	}
}

setup_monster :: proc(entity: ^Entity) {
	entity.max_health = 100
	entity.current_health = entity.max_health
	entity.kind = .monster
	entity.sprite_size = CELL_SIZE
	entity.sprite = monster_sprite
	entity.color = rl.RED
	entity.name = "monster"
	entity.local_id = 1
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
			for step in with_entity.ai_steps {
				switch step.type {
					case .say:
						for t in all_texts {
							if t.id == step.arg {
								add_log(t.text)
								//append(&game_state.logs, t.text)
								break
							}
						}
					case .give:
						give_item(entity, step.arg)
						message := fmt.ctprint("PLAYER:GET_ITEM:", entity.net_id, "|", step.arg, sep = "")
						send_packet(entity.peer, rawptr(message), len(message))
					case .quest:
						for q in all_quests {
							if q.id == step.arg {
								append(&entity.quests, q)
								add_log(fmt.tprint("Started quest", q.name))
								//append(&game_state.logs, fmt.tprint("Started quest", q.name))
								message := fmt.ctprint("PLAYER:GET_QUEST:", entity.net_id, "|", q.id, sep = "")
								send_packet(entity.peer, rawptr(message), len(message))
								break
							}
						}
				}
			}
		case .monster :
			entity.target = with_entity
	}
}

get_quest_with_id :: proc(id : int) -> Quest {
	for q in all_quests {
		if q.id == id {
			return q
		}
	}
	return Quest{}
}

give_item :: proc(entity: ^Entity, item_id: int) {
	for i in all_items {
		if i.id == item_id {
			for &temp_item in entity.items {
				if !temp_item.allocated {
					temp_item = i
					temp_item.allocated = true
					add_log(fmt.tprint("You received ", i.name))
					//append(&game_state.logs, fmt.tprint("You received ", i.name))
					break
				}
			}
			break
		}
	}
}

give_xp :: proc(entity: ^Entity, amount: int) {
	entity.current_xp += amount
	for entity.current_xp >= entity.target_xp {
		entity.current_xp = entity.current_xp - entity.target_xp
		entity.lvl += 1
		entity.must_select_stat = true
		add_log(fmt.tprint("You reached level ", entity.lvl))
		//append(&game_state.logs, fmt.tprint("You reached level ", entity.lvl))
	}
}

apply_class :: proc(entity: ^Entity, class : Class)
{
	entity.class = class
	entity.vitality += class.vitality
	entity.strength += class.strength
	entity.intelligence += class.intelligence
	entity.chance += class.chance
	entity.endurance += class.endurance
	entity.speed += class.speed
	entity.dexterity += class.dexterity
	if class == Mage {
		entity.sprite = Mage_sprite
	}
	else if class == Ranger {
		entity.sprite = Ranger_sprite
	}

}

apply_story :: proc(entity: ^Entity, story : Story)
{
	entity.story = story

	if story == Undead {
		entity.vitality = 1
		entity.strength = 1
		entity.intelligence = 1
		entity.chance = 1
		entity.endurance = 1
		entity.speed = 1
		entity.dexterity = 1
		entity.gold = 0
	}
	else
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
}

split_text :: proc(text : string, limit : int) -> [dynamic]string {
	to_return : [dynamic]string
	if len(text) < limit {
		append(&to_return, text)
		return to_return
	}

	size := 0
	total_size := 0
	temp_text := ""

	for total_size < len(text){
		temp_text = fmt.tprint(temp_text, rune(text[total_size]), sep = "")
		size += 1
		total_size += 1
		if size == limit {
			size = 0
			append(&to_return, temp_text)
			temp_text = ""
		}
	}
	if size > 0 {
		append(&to_return, temp_text)
	}
	return to_return
}

add_log :: proc(text : string) {
	strings := split_text(text, 50)
	for s in strings {
		log_error("text:", s)
		append(&game_state.logs, s)
	}
}

main :: proc() {
}