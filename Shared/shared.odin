package multiplayer_shared

import "core:fmt"

import enet "vendor:ENet"

Entity :: struct {
	net_id : int,
	pos_x : f32,
	pos_y : f32,
	current_health : f32,
	peer : ^enet.Peer,
	allocated : bool,
	max_health : f32,
	items : [10]Item,
	name : string
}

Item :: struct {
	id : int,
	allocated : bool,
	quantity : int,
	name : string,
	damage : int,
}

weapon := Item {id = 1, quantity = 1, name = "Sword_1", damage = 1}

all_items : [dynamic]Item

send_packet :: proc(peer : ^enet.Peer, data : rawptr, msg_len: uint) {
	packet : ^enet.Packet = enet.packet_create(data, msg_len + 1, {enet.PacketFlag.RELIABLE})
	enet.peer_send(peer, 0, packet)
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

player_to_string :: proc(player : Entity) -> cstring {
	return fmt.ctprint(player.net_id, "|", player.pos_x, "|", player.pos_y, sep = "")
}

main :: proc() {
}