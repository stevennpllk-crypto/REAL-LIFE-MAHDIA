extends Node
class_name MahdiaMultiplayerManager

signal connection_changed(connected: bool, message: String)
const DEFAULT_PORT := 24560
const MAX_CLIENTS := 16

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, MAX_CLIENTS)
	if result != OK:
		connection_changed.emit(false, "تعذر إنشاء الخادم: %s" % error_string(result))
		return result
	multiplayer.multiplayer_peer = peer
	connection_changed.emit(true, "الخادم المحلي يعمل على المنفذ %d" % port)
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	if address.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address.strip_edges(), port)
	if result != OK:
		connection_changed.emit(false, "تعذر الاتصال: %s" % error_string(result))
		return result
	multiplayer.multiplayer_peer = peer
	connection_changed.emit(false, "جارٍ الاتصال بالخادم...")
	return OK

func disconnect_from_game() -> void:
	multiplayer.multiplayer_peer = null
	connection_changed.emit(false, "تم قطع الاتصال")
