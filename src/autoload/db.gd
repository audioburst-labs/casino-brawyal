extends Node
## Autoload: thin Node wrapper around ContentDB.
## Loads and validates all JSON content at boot; exposes id lookups.
## The pure-logic layer (src/core) must never reference this autoload —
## it receives a ContentDB instance explicitly.

# TODO(M1): var content := ContentDB.new(); content.load_all()


func _ready() -> void:
	pass
