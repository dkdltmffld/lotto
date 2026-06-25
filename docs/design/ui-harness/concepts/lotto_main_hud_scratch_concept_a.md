# lotto_main_hud_scratch_concept_a

## Intent

`/gen-ui-concept` smoke test for the Godot project UI harness. This concept explores the main gameplay screen for `복권 키우기 : Idle RPG`: compact top HUD, visible side-scrolling combat, scratch-ticket attack panel, and bottom navigation in a 360x780 portrait mobile layout.

## Art Anchor

- Pixel-art inspired fantasy RPG UI.
- Dark carved wood frames, muted gold trim, parchment cards, green action accents.
- Scratch lottery visual language should feel like a combat tool, not a generic casino screen.
- Existing project constraints remain: portrait 9:19.5, pixel look, touch-first controls, HTML5 compatibility.

## Composition Rules

- Top safe area owns stage/currency/status chips and must remain compact.
- Middle area keeps the hero/enemy combat lane readable.
- Lower middle owns the scratch-card panel with a clear 3x3 grid.
- Bottom dock owns major navigation buttons and should not hide the scratch interaction target.
- Text in the concept is directional only; final labels must be native Godot UI text.

## UI Direction

- Treat panels/buttons as reusable skin atoms, not full-screen baked artwork.
- Candidate reusable assets: HUD chip frame, scratch panel frame, nav dock frame, nav button skin, small icon slots, reward/highlight effects.
- Candidate native UI: all labels, numbers, progress bars, cooldown/status values, quest/notification badges.
- Keep 9-slice candidates rectangular and separate decorative ornaments from stretchable skins.

## Implementation Notes

- Godot target mapping: `StyleBoxTexture`, `NinePatchRect`, `TextureButton`, `TextureRect`, and `AtlasTexture` regions.
- Likely code touch points for later build steps: `scripts/ui_skin.gd`, `scripts/sheet_rects.gd`, `scripts/nav_dock.gd`, `scripts/game.gd`, and panel scripts.
- Do not implement from this concept directly. Next step should be `/extract-design-system` to create `component-blueprints.yaml` and `asset-plan.yaml`.

## Source Image

- Project copy: `docs/design/ui-harness/concepts/lotto_main_hud_scratch_concept_a.png`
- Generated with built-in `imagegen` during Codex smoke test on 2026-06-16.
