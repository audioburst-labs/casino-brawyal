extends Node
## Autoload: loads and exposes the ContentDB.
## The pure-logic layer never references this autoload — it receives the
## ContentDB instance explicitly; only UI scripts use Db for convenience.

var content := ContentDB.new()


func _ready() -> void:
	if not content.load_all("res://data"):
		push_error("Content validation failed:\n" + "\n".join(content.errors))
