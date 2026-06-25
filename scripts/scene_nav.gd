extends RefCounted

# 씬 전환 공용 헬퍼 — login.gd / game.gd 의 _goto_scene 중복 제거(2026-06-10 리팩토링).
# "stage" 그룹(SubViewport 래퍼)이 있으면 그 안에서 전환, 없으면(단독 실행) 일반 전환.
# ⚠️ class_name 없음 — 사용처는 const SceneNav := preload("res://scripts/scene_nav.gd") 로 참조.


static func goto_scene(tree: SceneTree, path: String) -> void:
	var stage_node := tree.get_first_node_in_group("stage")
	if stage_node != null:
		stage_node.goto(path)
	else:
		tree.change_scene_to_file(path)
