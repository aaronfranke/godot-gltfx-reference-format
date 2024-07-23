@tool
class_name GLTFXEditorExportSettings
extends RefCounted


## The glTFX copyright string.
@export var copyright: String = ""

## The location of the subfolder to store the leaf models in, relative to the glTFX file.
@export var model_subfolder: String = "models"

## Which glTF format to use for the leaf models, GLB Binary or GLTF Text.
@export_enum("GLB Binary (*.glb)", "GLTF Text (*.gltf)") var model_format: int = 0

## If a Godot scene is purely referencing other Godot scenes, and therefore could itself become a glTFX,
## do we want it to become a nested glTFX, or merge it to ensure a flat hierarchy?
@export_enum("Allow nested glTFX files", "Merge into main glTFX file", "Merge into leaf glTF files") var nested_scene_handling: int = 0

## The GLTFDocument to use for exporting the GLTFX file. Stores settings for exporting the leaf models.
@export var model_settings := GLTFDocument.new()
