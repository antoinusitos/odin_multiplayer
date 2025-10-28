package multiplayer_client

import "core:fmt"
import "core:strings"
import "core:strconv"

import enet "vendor:ENet"
import rl "vendor:raylib"

import shared "../Shared"

local_player : ^shared.Entity
players : [10]^shared.Entity

selecting_stat_for_level := false

client : ^enet.Host
event : enet.Event
local_peer : ^enet.Peer
enet_init := false

selection_step : Selection_Steps
name_input := ""
edit_mode := false
active : i32 = 0
choosen_class : shared.Class
choosen_class_index := 0
choosen_story : shared.Story
choosen_story_index := 0

Selection_Steps :: enum {
	name,
	class,
	story,
}

main :: proc() {
	rl.InitWindow(1280, 720, "client")

	if(enet.initialize() != 0) {
		fmt.printfln("An error occurred while initializing ENet !")
		return
	}

	shared.camera.zoom = 1

	client = enet.host_create(nil, 1, 1, 0, 0)

	if (client == nil) {
		fmt.printfln("An error occurred while trying to create an ENet client !")
		return
	}

	for !rl.WindowShouldClose() {
		draw()

		update()

		enet_services()
	}

	enet.peer_disconnect(local_peer, 0)

	for enet.host_service(client, &event, 3000) > 0 {
		#partial switch event.type {
			case enet.EventType.RECEIVE :
				enet.packet_destroy(event.packet)
				break
			case enet.EventType.DISCONNECT :
				fmt.printfln("Disconnection succeeded.")
				break
		}
	}

	rl.CloseWindow()
}

init_enet :: proc () {
	address : enet.Address
	peer : ^enet.Peer

	enet.address_set_host(&address, "127.0.0.1")
	address.port = 7777

	peer = enet.host_connect(client, &address, 1, 0)
	if (peer == nil) {
		fmt.printfln("No available peers for initiating an ENet connection !")
		return
	}

	if(enet.host_service(client, &event, 5000) > 0 && event.type == enet.EventType.CONNECT) {
		fmt.printfln("Connection to 127.0.0.1:7777 succeeded.")
	}
	else {
		enet.peer_reset(peer)
		fmt.printfln("Connection to 127.0.0.1:7777 failed.")
		return
	}

	shared.fill_items()
	shared.fill_world()

	local_peer = peer
 
	fmt.printfln("INIT OK")
	enet_init = true
}

handle_receive_packet :: proc(message : string) {
	if strings.contains(message, "NEW_PLAYER:") {
		ss := strings.split(message, ":")
		ok := false
		id : u64 = 0
		net_id : u64 = 0
		found_infos := strings.split(ss[1], "|")
		id, ok = strconv.parse_u64(found_infos[0])
		net_id, ok = strconv.parse_u64(found_infos[1])

		local_player = shared.entity_create(.player)
		local_player.local_player = true
		local_player.allocated = true
		local_player.peer = local_peer
		local_player.net_id = net_id
		shared.apply_class(local_player, choosen_class)
		shared.apply_story(local_player, choosen_story)

		players[id] = local_player

		message := shared.player_to_string(local_player)
		shared.send_packet(local_player.peer, rawptr(message), len(message))

		//local_player.net_id = id
		fmt.printfln("changed id for %u", id)
	}
	else if strings.contains(message, "PLAYER_JOINED:") {
		ss := strings.split(message, ":")
		ok := false
		id : u64 = 0
		id, ok = strconv.parse_u64(ss[1])
		for &player in players {
			if player == nil || !player.allocated {
				player = shared.entity_create(.player)
				player.net_id = id
				break
			}
		}
	}
	else if strings.contains(message, "PLAYERS:") {
		ss := strings.split(message, ":")
		found_players := strings.split(ss[1], "|")
		ok := false
		id : u64 = 0
		for found_id in found_players {
			id, ok = strconv.parse_u64(found_id)
			if id == local_player.net_id do continue
			for &player in players {
				if player == nil || !player.allocated {
					player = shared.entity_create(.player)
					player.net_id = id
					break
				}
			}
		}
	}
	else if strings.contains(message, "UPDATE_PLAYER:") {
		ss := strings.split(message, ":")
		if ss[1] == "POSITION" {
			found_infos := strings.split(ss[2], "|")
			ok := false
			id : u64 = 0
			index := 0
			id, ok = strconv.parse_u64(found_infos[0])
			for &player in players {
				if player != nil && player.allocated && player.net_id == id {
					x : f32 = 0
					y : f32 = 0
					x, ok = strconv.parse_f32(found_infos[1])
					y, ok = strconv.parse_f32(found_infos[2])
					player.position = {x, y}
				}
			}
		}
		else if ss[1] == "HP" {
			found_infos := strings.split(ss[2], "|")
			ok := false
			max_hp : f32 = 0
			current_hp : f32 = 0
			index := 0
			id : u64 = 0
			id, ok = strconv.parse_u64(found_infos[0])
			current_hp, ok = strconv.parse_f32(found_infos[1])
			max_hp, ok = strconv.parse_f32(found_infos[2])
			if local_player.net_id == id {
				local_player.current_health = current_hp
				local_player.max_health = max_hp
			}
			else {
				for &player in players {
					if player != nil && player.allocated && player.net_id == id {
						player.current_health = current_hp
						player.max_health = max_hp
					}
				}
			}
		}
		else if ss[1] == "XP" {
			found_infos := strings.split(ss[2], "|")
			ok := false
			xp : int = 0
			index := 0
			id : u64 = 0
			id, ok = strconv.parse_u64(found_infos[0])
			xp, ok = strconv.parse_int(found_infos[1])
			if local_player.net_id == id {
				local_player.current_xp += xp
			}
		}
		else if ss[1] == "ITEM" {
			if strings.contains(message, "GIVE:") {
				found_infos := strings.split(ss[3], "|")
				ok := false
				index := 0
				id : u64 = 0
				weapon_id := 0
				id, ok = strconv.parse_u64(found_infos[0])
				weapon_id, ok = strconv.parse_int(found_infos[1])
				item : shared.Item = shared.get_item_with_id(weapon_id)
				if item.id != 0 {
					if local_player.net_id == id {
						local_player.items[0] = item
						local_player.items[0].allocated = true
					}
					else {
						for &player in players {
							if player != nil && player.allocated && player.net_id == id {
								player.items[0] = item
								player.items[0].allocated = true
							}
						}
					}
				}
			}
		}
	}
	else if strings.contains(message, "UPDATE_ENTITY:") {
		ss := strings.split(message, ":")
		if ss[1] == "HP" {
			found_infos := strings.split(ss[2], "|")
			ok := false
			id : u64 = 0
			current_hp : f32 = 0
			id, ok = strconv.parse_u64(found_infos[0])
			current_hp, ok = strconv.parse_f32(found_infos[1])

			for &entity in shared.game_state.entities {
				if entity.net_id == id {
					entity.current_health = current_hp
					break
				}
			}
		}
	}
	else if strings.contains(message, "DISCONNECT:") {
		ss := strings.split(message, ":")
		found_infos := strings.split(ss[1], "|")
		ok := false
		id : u64 = 0
		index := 0
		id, ok = strconv.parse_u64(found_infos[0])
		for &player in players {
			if player != nil && player.allocated && player.net_id == id {
				player.allocated = false
			}
		}
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	switch shared.game_state.game_step {
		case .selection :
			draw_ui_selection()
		case .game :
			draw_game()
	}

	rl.EndDrawing()
}

draw_game :: proc() {
	if !enet_init {
		return
	}

	rl.BeginMode2D(shared.camera)

	draw_x := 0
	draw_y := 0
	for y := shared.screen_y * shared.CELLS_NUM_HEIGHT ; y < (shared.screen_y * shared.CELLS_NUM_HEIGHT) + shared.CELLS_NUM_HEIGHT; y += 1 {
		for x := shared.screen_x * shared.CELLS_NUM_WIDTH;  x < (shared.screen_x * shared.CELLS_NUM_WIDTH) + shared.CELLS_NUM_WIDTH; x += 1 {
			cell := &shared.game_state.cells[y * shared.CELL_WIDTH + x]
			if cell.entity != nil && cell.entity.current_health <= 0 {
				shared.entity_destroy(cell.entity)
				cell.entity = nil
			}
			if cell.entity != nil && cell.entity.current_health > 0 {
				rl.DrawTextureRec(cell.entity.sprite, {0, 0, 32, 32}, {f32(draw_x * shared.CELL_SIZE), f32(draw_y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)}, cell.entity.color)
				if cell.entity.current_health < cell.entity.max_health {
					rl.DrawRectangleRec({f32(draw_x * shared.CELL_SIZE), f32(draw_y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - 10, 40, 5}, rl.RED)
					rl.DrawRectangleRec({f32(draw_x * shared.CELL_SIZE), f32(draw_y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - 10, 40 * (cell.entity.current_health / cell.entity.max_health), 5}, rl.GREEN)
				}
			}
			else {
				rl.DrawTextureRec(cell.sprite, {0, 0, 32, 32}, {f32(draw_x * shared.CELL_SIZE), f32(draw_y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)}, rl.WHITE)
			}
			draw_x += 1
		}
		draw_x = 0
		draw_y += 1
	}

	for &player in players {
		if player != nil && player.allocated {
			if int(player.position.x) >= shared.screen_x * shared.CELLS_NUM_WIDTH && int(player.position.x) < shared.screen_x * shared.CELLS_NUM_WIDTH + shared.CELLS_NUM_WIDTH && 
				int(player.position.y) >= shared.screen_y * shared.CELLS_NUM_HEIGHT && int(player.position.y) < shared.screen_y * shared.CELLS_NUM_HEIGHT + shared.CELLS_NUM_HEIGHT {
				player_x := f32(player.position.x * shared.CELL_SIZE) - f32(shared.screen_x * shared.CELLS_NUM_WIDTH * shared.CELL_SIZE)
				player_y := f32(player.position.y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - f32(shared.screen_y * shared.CELLS_NUM_HEIGHT * shared.CELL_SIZE)
				if player == local_player {
					rl.DrawTextureRec(player.sprite, {0, 0, 32, 32}, {player_x, player_y}, rl.GREEN)
				}
				else {
					rl.DrawTextureRec(player.sprite, {0, 0, 32, 32}, {player_x, player_y}, rl.WHITE)
				}
				rl.DrawRectangleRec({player_x, player_y - 10, 40, 5}, rl.RED)
				rl.DrawRectangleRec({player_x, player_y - 10, 40 * (player.current_health / player.max_health), 5}, rl.GREEN)
				rl.DrawText(strings.clone_to_cstring(player.name), i32(player_x), i32(player_y)- 25, 10, rl.WHITE)
			}
		}
	}
	rl.EndMode2D()

	if local_player != nil {
		draw_ui()
	}
}

draw_ui :: proc() {
	//rl.DrawText("Client", 200, 120, 20, rl.GREEN)

	draw_ui_game()
}

draw_ui_selection :: proc() {
	rl.DrawRectangleRec({1280 / 2 - 300, 720 / 2 - 300, 600, 600}, rl.GRAY)
	switch selection_step {
		case .name :
			rl.DrawText(fmt.ctprint("WHAT IS YOUR NAME ?"), 1280 / 2 - 150, 720 / 2 - 300 + 10, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint(name_input), 1280 / 2 - 150, 720 / 2 - 300 + 50, 20, rl.BLACK)
			clicked := rl.GuiButton({1280 / 2 - 300, 720 / 2 - 300 + 150, 600, 50}, "OK")
			if clicked {
				selection_step = .class
			}
		case .class :
			rl.DrawText(fmt.ctprint("WHAT IS YOUR CLASS ?"), 1280 / 2 - 150, 720 / 2 - 300 + 10, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("A - WARRIOR"), 1280 / 2 - 290, 720 / 2 - 300 + 30, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("B - MAGE"), 1280 / 2 - 290, 720 / 2 - 300 + 50, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("C - RANGER"), 1280 / 2 - 290, 720 / 2 - 300 + 70, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("D - RANDOM"), 1280 / 2 - 290, 720 / 2 - 300 + 90, 20, rl.BLACK)
			clicked := rl.GuiButton({1280 / 2 - 300, 720 / 2 - 300 + 150, 600, 50}, "OK")
			if clicked {
				selection_step = .story
			}
		case .story :
			rl.DrawText(fmt.ctprint("WHAT IS YOUR STORY ?"), 1280 / 2 - 150, 720 / 2 - 300 + 10, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("A - Greedy"), 1280 / 2 - 290, 720 / 2 - 300 + 30, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("B - Clerc"), 1280 / 2 - 290, 720 / 2 - 300 + 50, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("C - Berserk"), 1280 / 2 - 290, 720 / 2 - 300 + 70, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("D - Ninja"), 1280 / 2 - 290, 720 / 2 - 300 + 90, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("E - Archer"), 1280 / 2 - 290, 720 / 2 - 300 + 110, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("F - Paladin"), 1280 / 2 - 290, 720 / 2 - 300 + 130, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("G - Thief"), 1280 / 2 - 290, 720 / 2 - 300 + 150, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("H - Beggar"), 1280 / 2 - 290, 720 / 2 - 300 + 170, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("i - Undead"), 1280 / 2 - 290, 720 / 2 - 300 + 190, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("j - Random"), 1280 / 2 - 290, 720 / 2 - 300 + 230, 20, rl.BLACK)
			clicked := rl.GuiButton({1280 / 2 - 300, 720 / 2 - 300 + 290, 600, 50}, "OK")
			if clicked {
				shared.game_state.game_step = .game
			}
	}
}

draw_ui_game :: proc() {
	rl.DrawText(fmt.ctprint("POS: x:", local_player.position.x, " y:", local_player.position.y), 1280 - 250, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("HP:", local_player.current_health, "/", local_player.max_health), 10, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("LVL:", local_player.lvl), 10, 30, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("XP:", local_player.current_xp, "/", local_player.target_xp), 200, 30, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("GOLD:", local_player.gold), 390, 30, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint(choosen_class.name), 390 + 190, 30, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint(choosen_story.name), 390 + 190 + 190, 30, 20, rl.WHITE)

	rl.DrawText(fmt.ctprint("VIT:", local_player.vitality), 200, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("STR:", local_player.strength), 300, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("INT:", local_player.intelligence), 400, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("CHA:", local_player.chance), 500, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("END:", local_player.endurance), 600, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("SPE:", local_player.speed), 700, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("DEX:", local_player.dexterity), 800, 10, 20, rl.WHITE)

	rl.DrawText(fmt.ctprint("SCREEN: x:", shared.screen_x, " y:", shared.screen_y), 1280 - 250, 30, 20, rl.WHITE)

	if local_player.items[0].allocated {
		rl.DrawText(fmt.ctprint("Weapon:", local_player.items[0].name, "(dmg:", local_player.items[0].damage, ")"), 10, 50, 20, rl.WHITE)
	}

	if selecting_stat_for_level {
		rl.DrawRectangleRec({1280 / 2 - 300, 720 / 2 - 300, 600, 600}, rl.GRAY)
		rl.DrawText(fmt.ctprint("SELECT STAT TO UPGRADE"), 1280 / 2 - 150, 720 / 2 - 300 + 10, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("A - VITALITY"), 1280 / 2 - 290, 720 / 2 - 300 + 30, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("B - STRENGTH"), 1280 / 2 - 290, 720 / 2 - 300 + 50, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("C - INTELLIGENCE"), 1280 / 2 - 290, 720 / 2 - 300 + 70, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("D - CHANCE"), 1280 / 2 - 290, 720 / 2 - 300 + 90, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("E - ENDURANCE"), 1280 / 2 - 290, 720 / 2 - 300 + 110, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("F - SPEED"), 1280 / 2 - 290, 720 / 2 - 300 + 130, 20, rl.BLACK)
		rl.DrawText(fmt.ctprint("G - DEXTERITY"), 1280 / 2 - 290, 720 / 2 - 300 + 150, 20, rl.BLACK)
	}
}

add_letter :: proc(letter : string) {
	name_input = string(fmt.ctprint(name_input, letter, sep = ""))
}

update :: proc() {
	if shared.game_state.game_step == .selection {
		switch selection_step {
			case .name :
			if rl.IsKeyPressed(rl.KeyboardKey.A) {
				add_letter("a")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.B) {
				add_letter("b")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.C) {
				add_letter("c")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.D) {
				add_letter("d")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.E) {
				add_letter("e")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.F) {
				add_letter("f")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.G) {
				add_letter("g")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.H) {
				add_letter("h")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.I) {
				add_letter("i")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.J) {
				add_letter("j")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.K) {
				add_letter("k")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.L) {
				add_letter("l")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.M) {
				add_letter("m")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.N) {
				add_letter("n")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.O) {
				add_letter("o")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.P) {
				add_letter("p")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.Q) {
				add_letter("q")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.R) {
				add_letter("r")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.S) {
				add_letter("s")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.T) {
				add_letter("t")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.U) {
				add_letter("u")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.V) {
				add_letter("v")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.W) {
				add_letter("w")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.X) {
				add_letter("x")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.Y) {
				add_letter("y")
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.Z) {
				add_letter("z")
			}
			break
			case .class :
			if rl.IsKeyPressed(rl.KeyboardKey.A) {
				choosen_class = shared.Warrior
				shared.log_error(choosen_class)
				selection_step = .story
				choosen_class_index = 0
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.B) {
				choosen_class = shared.Mage
				shared.log_error(choosen_class)
				selection_step = .story
				choosen_class_index = 1
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.C) {
				choosen_class = shared.Ranger
				shared.log_error(choosen_class)
				selection_step = .story
				choosen_class_index = 2
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.D) {
				choosen_class_index = int(rl.GetRandomValue(0, len(shared.classes) - 1))
				choosen_class = shared.classes[choosen_class_index]
				shared.log_error(choosen_class)
				selection_step = .story
			}
			break
			case .story :
			if rl.IsKeyPressed(rl.KeyboardKey.A) {
				choosen_story = shared.Greedy
				choosen_story_index = 0
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.B) {
				choosen_story = shared.Clerc
				choosen_story_index = 1
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.C) {
				choosen_story = shared.Berserk
				choosen_story_index = 2
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.D) {
				choosen_story = shared.Ninja
				choosen_story_index = 3
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.E) {
				choosen_story = shared.Archer
				choosen_story_index = 4
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.F) {
				choosen_story = shared.Paladin
				choosen_story_index = 5
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.G) {
				choosen_story = shared.Thief
				choosen_story_index = 6
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.H) {
				choosen_story = shared.Beggar
				choosen_story_index = 7
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.I) {
				choosen_story = shared.Undead
				choosen_story_index = 8
				shared.game_state.game_step = .game
				init_enet()
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.J) {
				choosen_story_index = int(rl.GetRandomValue(0, len(shared.stories) - 1))
				choosen_story = shared.stories[choosen_story_index]
				shared.log_error(choosen_story)
				shared.game_state.game_step = .game
				init_enet()
			}
		}

		return
	}

	for &entity in shared.game_state.entities {
		if !entity.allocated do continue

		// call the update function
		entity.update(&entity)
		/*if entity.current_health <= 0 {
			shared.entity_destroy(&entity)
		}*/

		if &entity == local_player {
			if entity.must_select_stat {
				selecting_stat_for_level = true
			}
		}
	}

	if selecting_stat_for_level {
		if rl.IsKeyDown(rl.KeyboardKey.A) && !shared.a_used {
			local_player.vitality += 1
			local_player.max_health = f32(local_player.vitality) * 100
			
			selecting_stat_for_level = false
			local_player.must_select_stat = false
			shared.a_used = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.B) && !shared.b_used {
			local_player.strength += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
			shared.b_used = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.C) && !shared.c_used {
			local_player.intelligence += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
			shared.c_used = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.D) && !shared.d_used {
			local_player.chance += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
			shared.d_used = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.E) && !shared.e_used {
			local_player.endurance += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
			shared.e_used = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.F) && !shared.f_used {
			local_player.speed += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
			shared.f_used = true
		}
	}
}

enet_services :: proc() {
	if !enet_init {
		return
	}

	for enet.host_service(client, &event, 0) > 0 {
		#partial switch event.type {
			case enet.EventType.RECEIVE :
				/*fmt.printfln("A packer of length %u containing %s was received from address %u:%u on channel %u", 
					event.packet.dataLength, 
					event.packet.data, 
					event.peer.address.host, 
					event.peer.address.port, 
					event.channelID)*/
				message := string(event.packet.data[:event.packet.dataLength])
				handle_receive_packet(message)
				break
		}
	}
}