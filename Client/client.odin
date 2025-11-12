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
choosen_class_index := -1
choosen_story : shared.Story
choosen_story_index := -1

empty_class := shared.Class {
	vitality = 10, 
	strength = 10,
	intelligence = 10,
	chance = 10,
	endurance = 10,
	speed = 10,
	dexterity = 10,
}
empty_gold := 0

Selection_Steps :: enum {
	name,
	class,
	story,
	valid
}

main :: proc() {
	rl.InitWindow(1280, 720, "client")

	rl.InitAudioDevice()

	fx_wav := rl.LoadSound("spring.wav") 

	rl.SetTargetFPS(60)

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
		rl.UpdateMusicStream(shared.menu_music);

		if rl.IsKeyPressed(.SPACE) {
			rl.PlaySound(fx_wav)      // Play WAV sound
		}

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

	rl.UnloadSound(fx_wav) 
	rl.UnloadMusicStream(shared.menu_music)
	rl.CloseAudioDevice()
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

	shared.fill_all()

	local_peer = peer
 
	fmt.printfln("INIT OK")
	enet_init = true
}

handle_receive_packet :: proc(message : string) {
	if strings.contains(message, "CREATE_LOCAL_PLAYER:") {
		rl.PlayMusicStream(shared.menu_music);
		rl.SetMusicVolume(shared.menu_music, 0.5)

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
		local_player.name = name_input
		local_player.peer = local_peer
		local_player.net_id = net_id
		local_player.init = true
		local_player.class_index = choosen_class_index
		local_player.story_index = choosen_story_index
		shared.apply_class(local_player, choosen_class)
		shared.apply_story(local_player, choosen_story)
		players[id] = local_player

		message := fmt.ctprint("CREATION_DONE:", local_player.net_id, "|", choosen_class_index, "|", choosen_story_index, "|", name_input, sep = "")
		shared.send_packet(local_player.peer, rawptr(message), len(message))

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
		found_players := strings.split(ss[1], "\\")
		ok := false
		id : u64 = 0
		class_index : int = 0
		x : f32 = 0
		y : f32 = 0
		for found_id in found_players {
			ss := strings.split(found_id, "|")
			id, ok = strconv.parse_u64(ss[0])
			if id == local_player.net_id do continue
			for &player in players {
				if player == nil || !player.allocated {
					player = shared.entity_create(.player)
					player.net_id = id
					player.name = ss[4]
					class_index, ok = strconv.parse_int(ss[1])
					shared.apply_class(player, shared.classes[class_index])
					x, ok = strconv.parse_f32(ss[2])
					y, ok = strconv.parse_f32(ss[3])
					player.position = {x, y}
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
			id : u64 = 0
			id, ok = strconv.parse_u64(found_infos[0])
			xp, ok = strconv.parse_int(found_infos[1])
			if local_player.net_id == id {
				shared.give_xp(local_player, xp)
			}
		}
		else if ss[1] == "ITEM" {
			if strings.contains(message, "GIVE:") {
				found_infos := strings.split(ss[3], "|")
				ok := false
				id : u64 = 0
				weapon_id := 0
				id, ok = strconv.parse_u64(found_infos[0])
				weapon_id, ok = strconv.parse_int(found_infos[1])
				if weapon_id != 0 {
					shared.give_item(local_player, weapon_id)
				}
			}
		}
		else if ss[1] == "CLASS" {
			found_infos := strings.split(ss[2], "|")
			ok := false
			class : int = 0
			id : u64 = 0
			id, ok = strconv.parse_u64(found_infos[0])
			class, ok = strconv.parse_int(found_infos[1])
			for &player in players {
				if player != nil && player.allocated && player.net_id == id {
					player.class_index = class
					shared.apply_class(player, shared.classes[class])
				}
			}
		}
		else if ss[1] == "NAME" {
			found_infos := strings.split(ss[2], "|")
			ok := false
			id : u64 = 0
			id, ok = strconv.parse_u64(found_infos[0])
			for &player in players {
				if player != nil && player.allocated && player.net_id == id {
					player.name = found_infos[1]
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
	else if strings.contains(message, "ATTACK_ANSWER:") {
		ss := strings.split(message, ":")
		found_infos := strings.split(ss[1], "|")
		ok := false
		damage : f32 = 0
		crit : bool
		crit_string : string
		name : string
		damage, ok = strconv.parse_f32(found_infos[0])
		crit, ok = strconv.parse_bool(found_infos[1])
		crit_string = crit ? " (crit)" : ""
		if damage == 0 {
			append(&shared.game_state.logs, fmt.tprint("You missed ", found_infos[2], sep = ""))
		}
		else {
			append(&shared.game_state.logs, fmt.tprint("You deal ", damage, crit_string, " dmg to ", found_infos[2], sep = ""))
		}
	}
	else if strings.contains(message, "KILL:") {
		ss := strings.split(message, ":")
		found_infos := strings.split(ss[1], "|")
		ok := false
		id : int = 0
		id, ok = strconv.parse_int(found_infos[0])
		append(&shared.game_state.logs, fmt.tprint("You killed ", found_infos[1], sep = ""))
		for &quest in local_player.quests {
			if !quest.completed && quest.quest_type == .kill && quest.object_id == id {
				quest.completion += 1
				if quest.completion >= quest.num {
					quest.completed = true
					shared.give_xp(local_player, quest.xp_reward)
					append(&shared.game_state.logs, fmt.tprint("Quest ", quest.name, " complete"))
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
					rl.DrawTextureRec(player.sprite, {0, 0, 32, 32}, {player_x, player_y}, local_player.color)
				}
				else {
					rl.DrawTextureRec(player.sprite, {0, 0, 32, 32}, {player_x, player_y}, player.color)
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
	if choosen_class_index != -1 {
		rl.DrawText(fmt.ctprint(choosen_class.name), 1280 / 2 + 310, 720 / 2 - 300, 20, rl.WHITE)
	}
	if choosen_story_index != -1 {
		rl.DrawText(fmt.ctprint(choosen_story.name), 1280 / 2 + 310 + 200, 720 / 2 - 300, 20, rl.WHITE)
	}
	rl.DrawText(fmt.ctprint("vitality : ", empty_class.vitality, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 30, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("strength : ", empty_class.strength, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 50, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("intelligence : ", empty_class.intelligence, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 70, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("chance : ", empty_class.chance, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 90, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("endurance : ", empty_class.endurance, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 110, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("speed : ", empty_class.speed, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 130, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("dexterity : ", empty_class.dexterity, sep = "	"), 1280 / 2 + 310, 720 / 2 - 300 + 150, 20, rl.WHITE)
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
			rl.DrawText(fmt.ctprint("A -", shared.Warrior.name, shared.Warrior.stats_string), 1280 / 2 - 290, 720 / 2 - 300 + 50, 20, (choosen_class_index == 0 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("B -", shared.Mage.name, shared.Mage.stats_string), 1280 / 2 - 290, 720 / 2 - 300 + 70, 20, (choosen_class_index == 1 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("C -", shared.Ranger.name, shared.Ranger.stats_string), 1280 / 2 - 290, 720 / 2 - 300 + 90, 20, (choosen_class_index == 2 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("D - Random"), 1280 / 2 - 290, 720 / 2 - 300 + 110, 20, rl.BLACK)
			if choosen_class_index != -1 {
				clicked := rl.GuiButton({1280 / 2 - 300, 720 / 2 - 300 + 150, 600, 50}, "OK")
				if clicked && choosen_class_index != -1 {
					selection_step = .story
				}
			}
		case .story :
			rl.DrawText(fmt.ctprint("WHAT IS YOUR STORY ?"), 1280 / 2 - 150, 720 / 2 - 300 + 10, 20, rl.BLACK)
			rl.DrawText(fmt.ctprint("A -", shared.Greedy.name), 1280 / 2 - 290, 720 / 2 - 300 + 30, 20, (choosen_story_index == 0 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("B -", shared.Clerc.name), 1280 / 2 - 290, 720 / 2 - 300 + 50, 20, (choosen_story_index == 1 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("C -", shared.Berserk.name), 1280 / 2 - 290, 720 / 2 - 300 + 70, 20, (choosen_story_index == 2 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("D -", shared.Ninja.name), 1280 / 2 - 290, 720 / 2 - 300 + 90, 20, (choosen_story_index == 3 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("E -", shared.Archer.name), 1280 / 2 - 290, 720 / 2 - 300 + 110, 20, (choosen_story_index == 4 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("F -", shared.Paladin.name), 1280 / 2 - 290, 720 / 2 - 300 + 130, 20, (choosen_story_index == 5 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("G -", shared.Thief.name), 1280 / 2 - 290, 720 / 2 - 300 + 150, 20, (choosen_story_index == 6 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("H -", shared.Beggar.name), 1280 / 2 - 290, 720 / 2 - 300 + 170, 20, (choosen_story_index == 7 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("i -", shared.Undead.name), 1280 / 2 - 290, 720 / 2 - 300 + 190, 20, (choosen_story_index == 8 ? rl.GREEN : rl.BLACK))
			rl.DrawText(fmt.ctprint("j - Random"), 1280 / 2 - 290, 720 / 2 - 300 + 230, 20, rl.BLACK)
			if choosen_story_index != -1 {
			clicked := rl.GuiButton({1280 / 2 - 300, 720 / 2 - 300 + 270, 600, 50}, "OK")
				if clicked && choosen_story_index != -1{
					init_enet()
					shared.game_state.game_step = .game
				}

				if choosen_story_index != -1 {
					rl.DrawText(fmt.ctprint(choosen_story.description), 1280 / 2 - 290, 720 / 2 - 300 + 330, 20, rl.BLACK)
					rl.DrawText(fmt.ctprint(choosen_story.stats_string), 1280 / 2 - 290, 720 / 2 - 300 + 400, 20, rl.BLACK)
				}
			}
		case .valid :
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

	/*if local_player.items[0].allocated {
		rl.DrawText(fmt.ctprint("Weapon:", local_player.items[0].name, "(dmg:", local_player.items[0].damage, ")"), 10, 50, 20, rl.WHITE)
	}*/

	current_item := local_player.items[local_player.item_index]
	if current_item.allocated {
		if current_item.item_type == .weapon {
			rl.DrawText(fmt.ctprint("Weapon:", current_item.name, "(dmg:", current_item.damage, ")"), 10, 50, 20, rl.WHITE)
		}
		else {
			rl.DrawText(fmt.ctprint(current_item.name, "(", current_item.usage, ")"), 10, 50, 20, rl.WHITE)
		}
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

	y : i32 = shared.OFFSET_HEIGHT
	for log in shared.game_state.logs {
		rl.DrawText(fmt.ctprint(log), 1280 - 250, y, 10, rl.WHITE)
		y += 10
	}
}

add_letter :: proc(letter : string) {
	name_input = string(fmt.ctprint(name_input, letter, sep = ""))
}

update :: proc() {
	if shared.game_state.game_step == .selection {
		#partial switch selection_step {
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
				choosen_class_index = 0
				empty_class.vitality = 10 + choosen_class.vitality
				empty_class.strength = 10 + choosen_class.strength
				empty_class.intelligence = 10 + choosen_class.intelligence
				empty_class.chance = 10 + choosen_class.chance
				empty_class.endurance = 10 + choosen_class.endurance
				empty_class.speed = 10 + choosen_class.speed
				empty_class.dexterity = 10 + choosen_class.dexterity
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.B) {
				choosen_class = shared.Mage
				choosen_class_index = 1
				empty_class.vitality = 10 + choosen_class.vitality
				empty_class.strength = 10 + choosen_class.strength
				empty_class.intelligence = 10 + choosen_class.intelligence
				empty_class.chance = 10 + choosen_class.chance
				empty_class.endurance = 10 + choosen_class.endurance
				empty_class.speed = 10 + choosen_class.speed
				empty_class.dexterity = 10 + choosen_class.dexterity
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.C) {
				choosen_class = shared.Ranger
				choosen_class_index = 2
				empty_class.vitality = 10 + choosen_class.vitality
				empty_class.strength = 10 + choosen_class.strength
				empty_class.intelligence = 10 + choosen_class.intelligence
				empty_class.chance = 10 + choosen_class.chance
				empty_class.endurance = 10 + choosen_class.endurance
				empty_class.speed = 10 + choosen_class.speed
				empty_class.dexterity = 10 + choosen_class.dexterity
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.D) {
				choosen_class_index = int(rl.GetRandomValue(0, len(shared.classes) - 1))
				choosen_class = shared.classes[choosen_class_index]
				empty_class.vitality = 10 + choosen_class.vitality
				empty_class.strength = 10 + choosen_class.strength
				empty_class.intelligence = 10 + choosen_class.intelligence
				empty_class.chance = 10 + choosen_class.chance
				empty_class.endurance = 10 + choosen_class.endurance
				empty_class.speed = 10 + choosen_class.speed
				empty_class.dexterity = 10 + choosen_class.dexterity
			}
			break
			case .story :
			if rl.IsKeyPressed(rl.KeyboardKey.A) {
				choosen_story = shared.Greedy
				choosen_story_index = 0
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.B) {
				choosen_story = shared.Clerc
				choosen_story_index = 1
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.C) {
				choosen_story = shared.Berserk
				choosen_story_index = 2
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.D) {
				choosen_story = shared.Ninja
				choosen_story_index = 3
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.E) {
				choosen_story = shared.Archer
				choosen_story_index = 4
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.F) {
				choosen_story = shared.Paladin
				choosen_story_index = 5
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.G) {
				choosen_story = shared.Thief
				choosen_story_index = 6
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.H) {
				choosen_story = shared.Beggar
				choosen_story_index = 7
				empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
				empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
				empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
				empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
				empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
				empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
				empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.I) {
				choosen_story = shared.Undead
				choosen_story_index = 8
				empty_class.vitality = 1
				empty_class.strength = 1
				empty_class.intelligence = 1
				empty_class.chance = 1
				empty_class.endurance = 1
				empty_class.speed = 1
				empty_class.dexterity = 1
				empty_gold = choosen_story.gold
			}
			else if rl.IsKeyPressed(rl.KeyboardKey.J) {
				choosen_story_index = int(rl.GetRandomValue(0, len(shared.stories) - 1))
				choosen_story = shared.stories[choosen_story_index]
				if choosen_story == shared.Undead {
					empty_class.vitality = 1
					empty_class.strength = 1
					empty_class.intelligence = 1
					empty_class.chance = 1
					empty_class.endurance = 1
					empty_class.speed = 1
					empty_class.dexterity = 1
				}
				else {
					empty_class.vitality = 10 + choosen_class.vitality + choosen_story.stats.vitality
					empty_class.strength = 10 + choosen_class.strength + choosen_story.stats.strength
					empty_class.intelligence = 10 + choosen_class.intelligence + choosen_story.stats.intelligence
					empty_class.chance = 10 + choosen_class.chance + choosen_story.stats.chance
					empty_class.endurance = 10 + choosen_class.endurance + choosen_story.stats.endurance
					empty_class.speed = 10 + choosen_class.speed + choosen_story.stats.speed
					empty_class.dexterity = 10 + choosen_class.dexterity + choosen_story.stats.dexterity
				}
				empty_gold = choosen_story.gold
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
		if rl.IsKeyPressed(rl.KeyboardKey.A) {
			local_player.vitality += 1
			local_player.max_health = f32(local_player.vitality) * 100
			
			selecting_stat_for_level = false
			local_player.must_select_stat = false
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.B) {
			local_player.strength += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.C) {
			local_player.intelligence += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.D) {
			local_player.chance += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.E) {
			local_player.endurance += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.F) {
			local_player.speed += 1
			selecting_stat_for_level = false
			local_player.must_select_stat = false
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