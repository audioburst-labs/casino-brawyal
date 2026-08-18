extends Control
## Main menu. M0 stub — real layout, key art, and Continue button land in M4/M7.


func _on_play_pressed() -> void:
	# TODO(M4): Game.new_run() then goto map/first combat.
	print("Play pressed — run flow lands in M4.")


func _on_quit_pressed() -> void:
	get_tree().quit()
