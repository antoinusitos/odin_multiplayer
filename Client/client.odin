package multiplayer_client

import "core:fmt"
import "core:strings"
import "core:strconv"

import enet "vendor:enet"
import rl "vendor:raylib"

import shared "../Shared"

local_player : ^shared.Entity
players : [10]^shared.Entity
can_move := true
move_time : f32 = 0.15
current_move_time : f32 = move_time
sprite : rl.Texture2D

client : ^enet.Host
event : enet.Event

main :: proc() {
	rl.InitWindow(1280, 720, "client")

	if(enet.initialize() != 0) {
		fmt.printfln("An error occurred while initializing ENet !")
		return
	}

	sprite = rl.LoadTexture("Player.png")

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

	local_player = shared.entity_create(.player)
	local_player.local_player = true
	local_player.peer = peer

	message := shared.player_to_string(local_player)
	shared.send_packet(peer, rawptr(message), len(message))
 
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
		local_player.net_id = id
		fmt.printfln("changed id for %u", id)
	}
	else if strings.contains(message, "PLAYERS:") {
		ss := strings.split(message, ":")
		found_players := strings.split(ss[1], "|")
		ok := false
		id := 0
		index := 0
		for found_id in found_players {
			id, ok = strconv.parse_int(found_id)
			players[index] = shared.entity_create(.player)
			players[index].net_id = id
			index += 1
		}
	}
	else if strings.contains(message, "UPDATE_PLAYER:") {
		ss := strings.split(message, ":")
		if ss[1] == "POSITION" { //strings.contains(message, "POSITION:") {
			found_infos := strings.split(ss[2], "|")
			ok := false
			id := 0
			index := 0
			id, ok = strconv.parse_int(found_infos[0])
			for &player in players {
				if player.allocated && player.net_id == id {
					x : f32 = 0
					y : f32 = 0
					x, ok = strconv.parse_f32(found_infos[1])
					y, ok = strconv.parse_f32(found_infos[2])
					player.position = {x, y}
				}
			}
		}
		else if ss[1] == "HP" { //strings.contains(message, "HP:") {
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
					if player.allocated && player.net_id == id {
						player.current_health = current_hp
						player.max_health = max_hp
					}
				}
			}
		}
		else if ss[1] == "ITEM" { //strings.contains(message, "ITEM:") {
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
							if player.allocated && player.net_id == id {
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
			if player.allocated && player.net_id == id {
				player.allocated = false
			}
		}
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLUE)
	rl.BeginMode2D(shared.camera)
	for &player in players {
		if player.allocated && player.net_id != local_player.net_id {
			rl.DrawTextureRec(sprite, {0, 0, 32, 32}, {player.position.x, player.position.y}, rl.WHITE)
			rl.DrawRectangleRec({player.position.x, player.position.y - 10, 40, 5}, rl.RED)
			rl.DrawRectangleRec({player.position.x, player.position.y - 10, 40 * (player.current_health / player.max_health), 5}, rl.GREEN)
		}
	}
	rl.DrawTextureRec(sprite, {32, 32, 32, 32}, {local_player.position.x, local_player.position.y}, rl.GREEN)
	rl.DrawRectangleRec({local_player.position.x, local_player.position.y - 10, 40, 5}, rl.RED)
	rl.DrawRectangleRec({local_player.position.x, local_player.position.y - 10, 40 * (local_player.current_health / local_player.max_health), 5}, rl.GREEN)
	rl.EndMode2D()

	draw_ui()
	rl.EndDrawing()
}

draw_ui :: proc() {
	rl.DrawText("Client", 200, 120, 20, rl.GREEN)

	rl.DrawText(fmt.ctprint("POS: x:", local_player.position.x, " y:", local_player.position.y), 10, 10, 20, rl.BLACK)
	rl.DrawText(fmt.ctprint("HP:", local_player.current_health, "/", local_player.max_health), 10, 30, 20, rl.BLACK)

	if local_player.items[0].allocated {
		rl.DrawText(fmt.ctprint("Weapon:", local_player.items[0].name, "(", local_player.items[0].damage, ")"), 10, 720 - 20, 20, rl.BLACK)
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