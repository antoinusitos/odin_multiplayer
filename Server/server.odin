package multiplayer

import enet "vendor:enet"
import rl "vendor:raylib"
import "core:fmt"
import "core:strings"
import "core:strconv"

Player :: struct {
	net_id : int,
	pos_x : f32,
	pos_y : f32,
	peer : ^enet.Peer,
	allocated : bool
}

players : [10]Player
net_id_cumulated := 0
sprite : rl.Texture2D
clients_number := 0
camera : rl.Camera2D
server : ^enet.Host
event : enet.Event

send_packet :: proc(peer : ^enet.Peer, data : rawptr, msg_len: uint) {
	packet : ^enet.Packet = enet.packet_create(data, msg_len + 1, {enet.PacketFlag.RELIABLE})
	enet.peer_send(peer, 0, packet)
}

main :: proc() {
	rl.InitWindow(1280, 720, "server")

	if(enet.initialize() != 0) {
		fmt.printfln("An error occurred while initializing ENet !")
		return
	}

	sprite = rl.LoadTexture("Player.png")

	camera.zoom = 1

	address : enet.Address
	
	address.host = enet.HOST_ANY
	address.port = 7777

	server = enet.host_create(&address, 32, 1, 0, 0)

	if (server == nil) {
		fmt.printfln("An error occurred while trying to create an ENet server !")
		return
	}

	for !rl.WindowShouldClose() {
		draw()

		draw_ui()

		rl.EndDrawing()

		enet_services()
	}

	enet.host_destroy(server)

	rl.CloseWindow()
}

draw :: proc() {
	rl.BeginDrawing()
		
	rl.ClearBackground(rl.BLUE)

	if rl.IsKeyDown(rl.KeyboardKey.Z) {
		camera.zoom = 1
	}
	if rl.IsKeyDown(rl.KeyboardKey.S) {
		camera.zoom = 0.5
	}

	rl.BeginMode2D(camera)
	for &player in players {
		if player.allocated {
			rl.DrawTextureRec(sprite, {0, 0, 32, 32}, {player.pos_x, player.pos_y}, rl.WHITE)
		}
	}
	rl.EndMode2D()
}

draw_ui :: proc() {
	rl.DrawText("Server", 200, 120, 20, rl.GREEN)
	rl.DrawText(fmt.ctprint("Clients:", clients_number), 200, 150, 20, rl.GREEN)
}

enet_services :: proc() {
	for enet.host_service(server, &event, 0) > 0 {
		#partial switch event.type {
			case enet.EventType.CONNECT :
				fmt.printfln("A new client connected from %x:%u.", 
					event.peer.address.host, 
					event.peer.address.port)
				p := Player {net_id = net_id_cumulated, peer = event.peer, allocated = true}
				players[net_id_cumulated] = p

				message := fmt.ctprint("NEW_PLAYER:", net_id_cumulated, sep = "")
				send_packet(event.peer, rawptr(message), len(message))
				
				message = "PLAYERS:"
				for &player in players {
					if player.allocated {
						message = fmt.ctprint(message, "|", player.net_id, sep = "")
					}
				}

				for &player in players {
					if player.allocated {
						send_packet(player.peer, rawptr(message), len(message))
					}
				}

				clients_number += 1
				net_id_cumulated += 1
				break
			case enet.EventType.RECEIVE :
				/*fmt.printfln("A packer of length %u containing %s was received from address %x:%u on channel %u", 
					event.packet.dataLength, 
					event.packet.data, 
					event.peer.address.host, 
					event.peer.address.port, 
					event.channelID)*/
				message := string(event.packet.data[:event.packet.dataLength])
				ss := strings.split(message, "|")
				ok := false
				id := 0
				x : f32 = 0
				y : f32 = 0
				id, ok = strconv.parse_int(ss[0])
				x, ok = strconv.parse_f32(ss[1])
				y, ok = strconv.parse_f32(ss[2])

				for &player in players {
					if player.allocated && player.net_id == id {
						player.pos_x = x
						player.pos_y = y
					}
				}

				message_to_send := fmt.ctprint("UPDATE_PLAYER:", id, "|", x, "|", y, sep = "")

				for &player in players {
					if player.allocated && player.net_id != id {
						send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
					}
				}

				break
			case enet.EventType.DISCONNECT :
				fmt.printfln("%x:%u disconnected.", 
					event.peer.address.host, 
					event.peer.address.port)

				id := 0
				for &player in players {
					if player.allocated && player.peer == event.peer {
						id = player.net_id
						player.allocated = false
					}
				}
				message_to_send := fmt.ctprint("DISCONNECT:", id, sep = "")
				for &player in players {
					if player.allocated {
						send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
					}
				}

				clients_number -= 1
				break
		}
	}
}