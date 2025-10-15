package multiplayer_shared

import enet "vendor:enet"
import "core:fmt"

Player :: struct {
	net_id : int,
	pos_x : f32,
	pos_y : f32,
	current_health : f32,
	peer : ^enet.Peer,
	allocated : bool,
	max_health : f32,
}

send_packet :: proc(peer : ^enet.Peer, data : rawptr, msg_len: uint) {
	packet : ^enet.Packet = enet.packet_create(data, msg_len + 1, {enet.PacketFlag.RELIABLE})
	enet.peer_send(peer, 0, packet)
}

player_to_string :: proc(player : Player) -> cstring {
	return fmt.ctprint(player.net_id, "|", player.pos_x, "|", player.pos_y, sep = "")
}

main :: proc() {
}