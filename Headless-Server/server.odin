package multiplayer_server

import "core:fmt"
import "core:strings"
import "core:strconv"

import enet "vendor:ENet"

import shared "../Shared"

players : [10]shared.Entity
net_id_cumulated := 0
clients_number := 0
server : ^enet.Host
event : enet.Event

d_input_used : bool

main :: proc() {
	if(enet.initialize() != 0) {
		fmt.printfln("An error occurred while initializing ENet !")
		return
	}

	address : enet.Address
	
	address.host = enet.HOST_ANY
	address.port = 7777

	server = enet.host_create(&address, 32, 1, 0, 0)

	if (server == nil) {
		fmt.printfln("An error occurred while trying to create an ENet server !")
		return
	}

	shared.fill_items();

	for {
		enet_services()
	}

	enet.host_destroy(server)
}

enet_services :: proc() {
	for enet.host_service(server, &event, 0) > 0 {
		#partial switch event.type {
			case enet.EventType.CONNECT :
				fmt.printfln("A new client connected from %x:%u.", 
					event.peer.address.host, 
					event.peer.address.port)
				p := shared.Entity {net_id = net_id_cumulated, peer = event.peer, allocated = true, max_health = 100, current_health = 100}
				players[net_id_cumulated] = p

				message := fmt.ctprint("NEW_PLAYER:", net_id_cumulated, sep = "")
				shared.send_packet(event.peer, rawptr(message), len(message))
				
				message = "PLAYERS:"
				found_one := false
				for &player in players {
					if player.allocated {
						if found_one {
							message = fmt.ctprint(message, "|", player.net_id, sep = "")
						}
						else {
							message = fmt.ctprint(message, player.net_id, sep = "")
							found_one = true
						}
					}
				}

				for &player in players {
					if player.allocated {
						shared.send_packet(player.peer, rawptr(message), len(message))
					}
				}

				message_to_send := fmt.ctprint("UPDATE_PLAYER:HP:", net_id_cumulated, "|", p.current_health, "|", p.max_health, sep = "")
				for &player in players {
					if player.allocated {
						shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
					}
				}

				message_to_send = fmt.ctprint("UPDATE_PLAYER:ITEM:GIVE:", net_id_cumulated, "|1", sep = "")
				for &player in players {
					if player.allocated {
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

				message_to_send := fmt.ctprint("UPDATE_PLAYER:POSITION:", id, "|", x, "|", y, sep = "")

				for &player in players {
					if player.allocated && player.net_id != id {
						shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
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
						fmt.printfln("found allocated player")
					}
				}
				message_to_send := fmt.ctprint("DISCONNECT:", id, sep = "")
				for &player in players {
					if player.allocated {
						shared.send_packet(player.peer, rawptr(message_to_send), len(message_to_send))
					}
				}

				clients_number -= 1
				break
		}
	}
}