extends Node
## Autoload: scene flow and current run.
## Owns the active RunState and swaps screens under Main's ScreenRoot.

# TODO(M4): var run_state: RunState

var _screen_root: Node = null


func register_screen_root(root: Node) -> void:
	_screen_root = root


func goto_screen(scene_path: String, args: Dictionary = {}) -> void:
	assert(_screen_root != null, "Main scene must register its ScreenRoot before navigation.")
	for child in _screen_root.get_children():
		child.queue_free()
	var screen: Node = load(scene_path).instantiate()
	if not args.is_empty() and screen.has_method("setup"):
		screen.setup(args)
	_screen_root.add_child(screen)
