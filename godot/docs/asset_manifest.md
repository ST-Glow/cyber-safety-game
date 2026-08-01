# Asset manifest

Audit date: 2026-07-25  
Target runtime: Godot 4, GDScript, future Web export

## Import policy

- Original ZIP archives are preserved unchanged in `incoming_assets/`.
- For equivalent 3D exports, the retained order is GLB, then GLTF with its `.bin` and image dependencies.
- FBX, Unity-specific FBX, OBJ and MTL duplicates were not placed in `assets/`.
- OGG was retained instead of the equivalent WAV pack to reduce Web download size.
- Preview images and Windows `.url` shortcuts were not imported as runtime assets.
- Source-provided texture copies needed by retained GLTF files were preserved even when their pixels duplicate a canonical texture.

## Pack-level manifest

| Asset name | Original archive | Author | License | Retained formats | Godot path | Recommended use | Issues / audit notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| KayKit Adventurers Character Pack 2.0 FREE | `KayKit_Adventurers_2.0_FREE.zip` | Kay Lousberg | CC0 1.0 | 6 character GLB, 31 equipment GLTF + BIN, 2 Rig Medium animation GLB, PNG textures | `res://assets/characters/kaykit_adventurers/`; `res://assets/character_animations/kaykit_adventurers/` | Rounded player/NPC prototypes, collectible props, basic movement/general animation library | No missing references. Excluded 70 FBX and 31 OBJ/MTL equivalents. Repeated class textures occur across source export folders; required local GLTF copies and canonical textures were retained. Sample renders and `contents.png` excluded. |
| KayKit Character Animations 1.1 | `KayKit_Character_Animations_1.1.zip` | Kay Lousberg | CC0 1.0 | 14 animation-library GLB, 2 mannequin GLB, 1 PNG texture | `res://assets/character_animations/kaykit_character_animations/`; `res://assets/characters/kaykit_mannequins/` | Rig Medium/Rig Large movement, combat, simulation, tools and special animation testing; retarget reference mannequins | No missing external files. Excluded 16 duplicate FBX files. Rig compatibility and animation retarget settings need confirmation in the Godot editor. |
| KayKit Platformer Pack 1.0 FREE | `KayKit_Platformer_Pack_1.0_FREE.zip` | Kay Lousberg | CC0 1.0 | 370 GLTF + 370 BIN, 6 PNG texture copies | `res://assets/environments/platformer/kaykit_platformer_pack/` | Party-platformer track pieces, arches, buttons, levers, signage, hazards and finish structures | All 740 external GLTF references resolve. Excluded 740 FBX variants, 388 OBJ and 388 MTL files. The 18 apparently OBJ-only filenames are split submeshes of combined GLTF models such as buttons, levers and finish signs, not unique assets. Preview/sample images excluded. |
| KayKit Prototype Bits 1.1 FREE | `KayKit_Prototype_Bits_1.1_FREE.zip` | Kay Lousberg | CC0 1.0 | 72 GLTF + 72 BIN, 2 PNG texture copies | `res://assets/environments/prototype/kaykit_prototype_bits/` | Greybox obstacles, ramps, barriers, targets, barrels and quick interaction prototypes | All 144 external GLTF references resolve. Excluded 144 FBX variants, 77 OBJ and 77 MTL files. Five apparently OBJ-only dummy parts are submeshes contained by `Dummy_Base.gltf`. Preview/sample images excluded. |
| Kenney UI Pack 2.0 | `kenney_ui-pack.zip` | Kenney | CC0 1.0 | 868 PNG, 434 SVG, 2 TTF; 6 OGG stored under audio | `res://assets/ui/kenney_ui_pack/`; `res://assets/audio/kenney_ui_pack/` | Menus, quiz cards, buttons, sliders, stars, toggles, HUD typography and UI clicks | All SVG files parse successfully and font/audio headers are valid. `Preview.png` and `Sample.png` excluded. PNG includes Default and Double sizes; SVG and raster variants are both retained for later UI evaluation. Neutral grey elements repeat across color folders. |
| Interface SFX Pack 1 — OGG | `inteface_sfx_pack_1_ogg.zip` | ObsydianX | CC0 1.0 | 222 OGG | `res://assets/audio/interface_sfx_pack_1/` | Confirm, back, cursor and error feedback for menus, checkpoints and quiz answers | All OGG headers are valid. The archive filename contains the original typo `inteface`; the formal folder uses corrected `interface`. No duplicate audio files inside the OGG archive. |
| Interface SFX Pack 1 — WAV | `inteface_sfx_pack_1_wav.zip` | ObsydianX | CC0 1.0 | None; archive only | Not imported | Lossless source fallback if later audio editing is required | Its 222 tracks match the OGG pack one-for-one by relative name. Excluded from runtime assets to avoid duplicate Web payload. Original ZIP and license README remain available. |

## Retained runtime file totals

| Format | Count | Purpose |
| --- | ---: | --- |
| `.gltf` | 473 | Environment and equipment models |
| `.bin` | 473 | Required GLTF geometry buffers |
| `.glb` | 24 | Characters, mannequins and animation libraries |
| `.png` | 892 | Model textures and raster UI |
| `.svg` | 434 | Scalable UI alternatives |
| `.ogg` | 228 | Interface and UI audio |
| `.ttf` | 2 | Kenney Future fonts |

Total runtime asset files: **2,526**. Raw size before Godot import/export compression: **44,479,058 bytes** (about 42.4 MiB).

## Integrity and duplication status

- GLTF JSON checked: 473 valid, 0 invalid.
- External GLTF references checked: 946 references, 0 missing.
- Binary signatures checked for GLB, PNG, OGG and TTF: 0 invalid.
- SVG XML checked: 434 valid, 0 invalid.
- Exact-content duplicate groups in the formal assets: 40 groups containing 175 files. These are mainly shared model textures copied beside GLTF files and neutral Kenney UI elements repeated in each color family. They are retained because removing or relocating them could break source-relative references or the pack's color-folder selection model.
- New directory names checked: all 80 asset subdirectories use lowercase English snake_case.
