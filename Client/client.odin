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

	for !rl.WindowShouldClose() {
		draw()

		update()

		enet_services()
	}

	enet.peer_disconnect(peer, 0)

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

handle_receive_packet :: proc(message : string) {
	if strings.contains(message, "NEW_PLAYER:") {
		ss := strings.split(message, ":")
		ok := false
		id := 0
		id, ok = strconv.parse_int(ss[1])

		local_player = shared.entity_create(.player)
		local_player.local_player = true
		local_player.allocated = true
		local_player.peer = local_peer

		players[id] = local_player

		message := shared.player_to_string(local_player)
		shared.send_packet(local_player.peer, rawptr(message), len(message))

		local_player.net_id = id
		fmt.printfln("changed id for %u", id)
	}
	else if strings.contains(message, "PLAYER_JOINED:") {
		ss := strings.split(message, ":")
		ok := false
		id := 0
		id, ok = strconv.parse_int(ss[1])
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
		id := 0
		for found_id in found_players {
			id, ok = strconv.parse_int(found_id)
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
			id := 0
			index := 0
			id, ok = strconv.parse_int(found_infos[0])
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
			id := 0
			id, ok = strconv.parse_int(found_infos[0])
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
		else if ss[1] == "ITEM" {
			if strings.contains(message, "GIVE:") {
				found_infos := strings.split(ss[3], "|")
				ok := false
				index := 0
				id := 0
				weapon_id := 0
				id, ok = strconv.parse_int(found_infos[0])
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
	else if strings.contains(message, "DISCONNECT:") {
		ss := strings.split(message, ":")
		found_infos := strings.split(ss[1], "|")
		ok := false
		id := 0
		index := 0
		id, ok = strconv.parse_int(found_infos[0])
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
	rl.BeginMode2D(shared.camera)

	draw_x := 0
	draw_y := 0
	for y := shared.screen_y * shared.CELLS_NUM_HEIGHT ; y < (shared.screen_y * shared.CELLS_NUM_HEIGHT) + shared.CELLS_NUM_HEIGHT; y += 1 {
		for x := shared.screen_x * shared.CELLS_NUM_WIDTH;  x < (shared.screen_x * shared.CELLS_NUM_WIDTH) + shared.CELLS_NUM_WIDTH; x += 1 {
			cell := shared.game_state.cells[y * shared.CELL_WIDTH + x]
			if cell.entity != nil {
				rl.DrawTextureRec(cell.entity.sprite, {0, 0, 32, 32}, {f32(draw_x * shared.CELL_SIZE), f32(draw_y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)}, cell.entity.color)
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

	rl.EndDrawing()
}

draw_ui :: proc() {
	//rl.DrawText("Client", 200, 120, 20, rl.GREEN)

	rl.DrawText(fmt.ctprint("POS: x:", local_player.position.x, " y:", local_player.position.y), 1280 - 250, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("HP:", local_player.current_health, "/", local_player.max_health), 10, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("LVL:", local_player.lvl), 10, 30, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("XP:", local_player.current_xp, "/", local_player.target_xp), 200, 30, 20, rl.WHITE)

	rl.DrawText(fmt.ctprint("VIT:", local_player.vitality), 200, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("STR:", local_player.strength), 300, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("INT:", local_player.intelligence), 400, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("CHA:", local_player.chance), 500, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("END:", local_player.endurance), 600, 10, 20, rl.WHITE)
	rl.DrawText(fmt.ctprint("SPE:", local_player.speed), 700, 10, 20, rl.WHITE)

	rl.DrawText(fmt.ctprint("SCREEN: x:", shared.screen_x, " y:", shared.screen_y), 1280 - 250, 30, 20, rl.WHITE)

	if local_player.items[0].allocated {
		rl.DrawText(fmt.ctprint("Weapon:", local_player.items[0].name, "(", local_player.items[0].damage, ")"), 10, 50, 20, rl.WHITE)
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
	}
}

update :: proc() {
	for &entity in shared.game_state.entities {
		if !entity.allocated do continue

		// call the update function
		entity.update(&entity)
		if entity.current_health <= 0 {
			shared.entity_destroy(&entity)
		}

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