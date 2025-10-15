package multiplayer_client

import enet "vendor:enet"
import rl "vendor:raylib"
import "core:fmt"
import "core:strings"
import "core:strconv"
import shared "../Shared"

local_player : shared.Player
players : [10]shared.Player
movement_size : f32 = 32
can_move := true
move_time : f32 = 0.15
current_move_time : f32 = move_time
sprite : rl.Texture2D
camera : rl.Camera2D

client : ^enet.Host
event : enet.Event

main :: proc() {
	rl.InitWindow(1280, 720, "client")

	if(enet.initialize() != 0) {
		fmt.printfln("An error occurred while initializing ENet !")
		return
	}

	sprite = rl.LoadTexture("Player.png")

	camera.zoom = 1

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
	message := shared.player_to_string(local_player)
	shared.send_packet(peer, rawptr(message), len(message))
	local_player.peer = peer

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
			players[index] = shared.Player {net_id = id, allocated = true}
			index += 1
		}
	}
	else if strings.contains(message, "UPDATE_PLAYER:") {
		ss := strings.split(message, ":")
		if strings.contains(message, "POSITION:") {
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
					player.pos_x = x
					player.pos_y = y
				}
			}
		}
		else if strings.contains(message, "HP:") {
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
	rl.BeginMode2D(camera)
	for &player in players {
		if player.allocated && player.net_id != local_player.net_id {
			rl.DrawTextureRec(sprite, {0, 0, 32, 32}, {player.pos_x, player.pos_y}, rl.WHITE)
			rl.DrawRectangleRec({player.pos_x, player.pos_y - 10, 40, 5}, rl.RED)
			rl.DrawRectangleRec({player.pos_x, player.pos_y - 10, 40 * (player.current_health / player.max_health), 5}, rl.GREEN)
		}
	}
	rl.DrawTextureRec(sprite, {32, 32, 32, 32}, {local_player.pos_x, local_player.pos_y}, rl.GREEN)
	rl.DrawRectangleRec({local_player.pos_x, local_player.pos_y - 10, 40, 5}, rl.RED)
	rl.DrawRectangleRec({local_player.pos_x, local_player.pos_y - 10, 40 * (local_player.current_health / local_player.max_health), 5}, rl.GREEN)
	rl.EndMode2D()

	draw_ui()
	rl.EndDrawing()
}

draw_ui :: proc() {
	rl.DrawText("Client", 200, 120, 20, rl.GREEN)

	rl.DrawText(fmt.ctprint("HP:", local_player.current_health, "/", local_player.max_health), 10, 10, 20, rl.BLACK)
}

update :: proc() {
	update_player := false

	if !can_move {
		current_move_time -= rl.GetFrameTime()
		if current_move_time <= 0 {
			current_move_time = move_time
			can_move = true
		}
	}
	else {
		movement_x : f32 = 0
		movement_y : f32 = 0
		if rl.IsKeyDown(rl.KeyboardKey.A) {
			movement_x -= movement_size
			update_player = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.D) {
			movement_x += movement_size
			update_player = true
		}
		if rl.IsKeyDown(rl.KeyboardKey.W) && movement_x == 0 {
			movement_y -= movement_size
			update_player = true
		}
		else if rl.IsKeyDown(rl.KeyboardKey.S) && movement_x == 0 {
			movement_y += movement_size
			update_player = true
		}

		if update_player {
			local_player.pos_x += movement_x
			local_player.pos_y += movement_y

			can_move = false
			message := shared.player_to_string(local_player)
			shared.send_packet(local_player.peer, rawptr(message), len(message))

			if local_player.pos_x >= camera.target.x + 1280 {
				camera.target.x += 1280
			}
			else if local_player.pos_x < camera.target.x {
				camera.target.x -= 1280
			}
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