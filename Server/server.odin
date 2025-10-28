package multiplayer_server

import "core:fmt"
import "core:strings"
import "core:strconv"

import enet "vendor:ENet"
import rl "vendor:raylib"

import shared "../Shared"

players : [10]^shared.Entity
net_id_cumulated : u64 = 0
clients_number := 0
server : ^enet.Host
event : enet.Event

main :: proc() {
	rl.InitWindow(1280, 720, "server")

	if(enet.initialize() != 0) {
		fmt.printfln("An error occurred while initializing ENet !")
		return
	}

	shared.camera.zoom = 1

	address : enet.Address
	
	address.host = enet.HOST_ANY
	address.port = 7777

	server = enet.host_create(&address, 32, 1, 0, 0)

	if (server == nil) {
		fmt.printfln("An error occurred while trying to create an ENet server !")
		return
	}

	shared.fill_items()
	shared.fill_world()

	for !rl.WindowShouldClose() {
		draw()

		draw_ui()

		update()

		rl.EndDrawing()

		enet_services()
	}

	enet.host_destroy(server)

	rl.CloseWindow()
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	rl.BeginMode2D(shared.camera)

	for y := 0 ; y < shared.CELL_HEIGHT ; y += 1 {
		for x := 0;  x < shared.CELL_WIDTH; x += 1 {
			cell := &shared.game_state.cells[y * shared.CELL_WIDTH + x]
			if cell.entity != nil && cell.entity.current_health <= 0 {
				shared.entity_destroy(cell.entity)
				cell.entity = nil
			}
			if cell.entity != nil && cell.entity.current_health > 0  {
				rl.DrawTextureRec(cell.entity.sprite, {0, 0, 32, 32}, {f32(x * shared.CELL_SIZE), f32(y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)}, cell.entity.color)
				if cell.entity.current_health < cell.entity.max_health {
					rl.DrawRectangleRec({f32(x * shared.CELL_SIZE), f32(y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - 10, 40, 5}, rl.RED)
					rl.DrawRectangleRec({f32(x * shared.CELL_SIZE), f32(y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - 10, 40 * (cell.entity.current_health / cell.entity.max_health), 5}, rl.GREEN)
				}
			}
			else {
				rl.DrawTextureRec(cell.sprite, {0, 0, 32, 32}, {f32(x * shared.CELL_SIZE), f32(y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)}, rl.WHITE)
			}
		}
	}

	for &player in players {
		if player != nil && player.allocated {
			rl.DrawTextureRec(player.sprite, {0, 0, 32, 32}, {f32(player.position.x * shared.CELL_SIZE), f32(player.position.y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)}, rl.WHITE)
			rl.DrawRectangleRec({f32(player.position.x * shared.CELL_SIZE), f32(player.position.y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - 10, 40, 5}, rl.RED)
			rl.DrawRectangleRec({f32(player.position.x * shared.CELL_SIZE), f32(player.position.y * shared.CELL_SIZE + shared.OFFSET_HEIGHT) - 10, 40 * (player.current_health / player.max_health), 5}, rl.GREEN)
			rl.DrawText(fmt.ctprint(player.name), i32(player.position.x * shared.CELL_SIZE), i32(player.position.y * shared.CELL_SIZE + shared.OFFSET_HEIGHT)- 25, 10, rl.BLACK)
		}
	}

	rl.EndMode2D()
}

draw_ui :: proc() {
	//rl.DrawText("Server", 200, 120, 20, rl.GREEN)
	rl.DrawText(fmt.ctprint("Clients:", clients_number), 0, 0, 20, rl.GREEN)
	y : i32 = 0
	index := 0
	for &player in players {
		if player != nil && player.allocated {
			rl.DrawText(fmt.ctprint(player.name, " (x:", player.position.x, " y:", player.position.y, ")"), 10, 20 + y, 20, rl.GREEN)
			y += 20
			index += 1
		}
	}
	rl.DrawText(fmt.ctprint("ZQSD to move"), 200, 0, 20, rl.GREEN)
	rl.DrawText(fmt.ctprint("A/E to zoom"), 400, 0, 20, rl.GREEN)
}

update :: proc() {
	if rl.IsKeyDown(rl.KeyboardKey.Q) {
		shared.camera.zoom = 1
	}
	if rl.IsKeyDown(rl.KeyboardKey.E) {
		shared.camera.zoom = 0.5
	}

	if rl.IsKeyDown(rl.KeyboardKey.D){
		shared.camera.target.x += 1
	}
	else if rl.IsKeyDown(rl.KeyboardKey.A){
		shared.camera.target.x -= 1
	}

	if rl.IsKeyDown(rl.KeyboardKey.W){
		shared.camera.target.y -= 1
	}
	else if rl.IsKeyDown(rl.KeyboardKey.S){
		shared.camera.target.y += 1
	}
}

enet_services :: proc() {
	for enet.host_service(server, &event, 0) > 0 {
		#partial switch event.type {
			case enet.EventType.CONNECT :
				fmt.printfln("A new client connected from %x:%u.", 
					event.peer.address.host, 
					event.peer.address.port)
				p := shared.entity_create(.player)
				p.net_id = shared.game_state.entity_net_id
				p.peer = event.peer
				p.allocated = true
				p.max_health = 100
				p.current_health = 100
				item : shared.Item = shared.get_item_with_id(1)
				p.items[0] = item
				players[net_id_cumulated] = p

				message := fmt.ctprint("NEW_PLAYER:", net_id_cumulated, "|", shared.game_state.entity_net_id, sep = "")
				shared.send_packet(event.peer, rawptr(message), len(message))
				
				shared.game_state.entity_net_id += 1

				message = "PLAYERS:"
				found_one := false
				for &player in players {
					if player != nil && player.allocated{
						if found_one {
							message = fmt.ctprint(message, "|", player.net_id, sep = "")
						}
						else {
							message = fmt.ctprint(message, player.net_id, sep = "")
							found_one = true
						}
					}
				}

				shared.send_packet(event.peer, rawptr(message), len(message))

				message = fmt.ctprint("PLAYER_JOINED:", p.net_id, sep = "")

				for &player in players {
					if player != nil && player.allocated && player.net_id != p.net_id {
						shared.send_packet(player.peer, rawptr(message), len(message))
					}
				}

				message_to_send := fmt.ctprint("UPDATE_PLAYER:HP:", p.net_id, "|", p.current_health, "|", p.max_health, sep = "")
				for &player in players {
					if player != nil && player.allocated {
						shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
					}
				}

				message_to_send = fmt.ctprint("UPDATE_PLAYER:ITEM:GIVE:", p.net_id, "|1", sep = "")
				for &player in players {
					if player != nil && player.allocated {
						shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
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
				handle_receive_packet(message)
				break
			case enet.EventType.DISCONNECT :
				fmt.printfln("%x:%u disconnected.", 
					event.peer.address.host, 
					event.peer.address.port)

				id : u64 = 0
				for &player in players {
					if player != nil && player.allocated && player.peer == event.peer {
						id = player.net_id
						player.allocated = false
						fmt.printfln("found allocated player")
					}
				}
				message_to_send := fmt.ctprint("DISCONNECT:", id, sep = "")
				for &player in players {
					if player != nil && player.allocated {
						shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
					}
				}

				clients_number -= 1
				break
		}
	}
}

handle_receive_packet :: proc(message : string) {
	if strings.contains(message, "PLAYER:INFO") {
		ss1 := strings.split(message, ":")
		ss := strings.split(ss1[2], "|")
		ok := false
		id : u64 = 0
		x : f32 = 0
		y : f32 = 0
		id, ok = strconv.parse_u64(ss[0])
		x, ok = strconv.parse_f32(ss[1])
		y, ok = strconv.parse_f32(ss[2])

		for &player in players {
			if player != nil && player.allocated && player.net_id == id {
				player.position = {x, y}
			}
		}

		message_to_send := fmt.ctprint("UPDATE_PLAYER:POSITION:", id, "|", x, "|", y, sep = "")

		for &player in players {
			if player != nil && player.allocated && player.net_id != id {
				shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
			}
		}
	}
	else if strings.contains(message, "ATTACK") {
		ss1 := strings.split(message, ":")
		ss := strings.split(ss1[1], "|")
		id_from : u64 = 0
		id_to : u64 = 0
		ok := false
		id_from, ok = strconv.parse_u64(ss[0])
		id_to, ok = strconv.parse_u64(ss[1])
		attack(id_from, id_to)
	}
}

attack :: proc(from_entity : u64, to_entity : u64) {
	from : ^shared.Entity
	to : ^shared.Entity
	for &entity in shared.game_state.entities {
		if entity.net_id == from_entity {
			from = &entity
		}
		else if entity.net_id == to_entity {
			to = &entity
		}
	}

	if to.current_health <= 0 {
		return
	}

	shared.log_error(from.name, " is attacking ", to.name)
	to.current_health -= f32(from.items[0].damage)

	if (to.current_health <= 0)
	{
		message_to_send := fmt.ctprint("UPDATE_PLAYER:XP:", from.net_id, "|", "10", sep = "")
		for &player in players {
			if player != nil && player.allocated {
				shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
			}
		}
	}

	message_to_send := fmt.ctprint("UPDATE_ENTITY:HP:", to_entity, "|", to.current_health, sep = "")
	for &player in players {
			if player != nil && player.allocated {
				shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
			}
		}
}