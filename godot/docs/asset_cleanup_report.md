# Asset cleanup report

Audit date: 2026-07-25

## Work completed

1. Inventoried all 7 ZIP archives in `incoming_assets/` and recorded their SHA-256 hashes.
2. Extracted every archive into its own operating-system temporary directory; no source ZIP was opened for writing.
3. Audited 4,786 extracted files for format distribution, license/source files, duplicate exports and runtime dependencies.
4. Parsed every retained GLTF file and resolved every external buffer and image URI.
5. Applied the format priority rule: GLB/GLTF first, with required BIN and PNG dependencies retained.
6. Organized 2,526 runtime asset files into the requested Godot directory categories.
7. Normalized every newly created directory to lowercase English snake_case.
8. Copied six original CC0 license/readme texts into `licenses/` and added a source/checksum register.
9. Validated model, image, audio, font and SVG headers/structure after copying.
10. Recomputed all 7 source ZIP hashes after the operation; every archive is byte-for-byte unchanged.

No scene, level, GDScript, gameplay system, input map or export configuration was created or modified.

## Content not imported

| Excluded content | Quantity / scope | Reason |
| --- | ---: | --- |
| FBX exports | 970 files | Duplicates of retained GLB/GLTF; includes standard and Unity-oriented variants. |
| OBJ exports | 496 files | Duplicates or split-submesh representations of retained GLTF models. |
| MTL files | 496 files | Only required by the excluded OBJ exports. |
| Interface SFX WAV | 222 tracks | Exact one-to-one content match with retained OGG tracks; too costly to keep both for Web. |
| Format-specific duplicate textures | FBX/OBJ branches | Retained only canonical textures and the local texture copies required by preferred GLTF files. |
| Preview/sample images | 18 files | Pack catalog/reference renders, not runtime textures. |
| Windows internet shortcuts | 13 `.url` files | Not runtime assets; relevant sources were written to `licenses/source_attributions.md`. |

The two mannequin FBX files were briefly copied during the mechanical folder pass, then removed from the formal assets after the duplicate-format check. They remain fully recoverable from the untouched animation ZIP.

## Items requiring manual confirmation

- **No Godot project descriptor exists yet.** The audited folder does not contain `project.godot`, scenes, scripts or Web export presets. It is currently a clean asset-staging workspace rather than an importable/runnable Godot project. This phase intentionally did not create those files.
- **Animation compatibility:** KayKit Adventurers uses Rig Medium. The separate animation pack contains Rig Medium and Rig Large libraries. Import settings, loop flags, root motion and any retarget mapping should be checked in Godot 4 before gameplay work.
- **Web payload:** the formal assets total about 42.4 MiB before Godot import/export processing; audio alone is about 18.4 MiB. A production Web build should include only the SFX and model subsets used by the finished game.
- **UI representation:** PNG Default/Double and SVG variants are all retained. The eventual UI implementation should choose one representation per control instead of loading both.
- **Input prompts:** no dedicated keyboard/gamepad prompt pack was present. `assets/input_prompts/` is intentionally empty and ready for a future licensed pack.
- **Model granularity:** the platformer pack contains 370 separate GLTF assets. Later development may group only the models used by a level or convert selected assets to GLB, but no conversion was performed during this audit.
- **Duplicate runtime files:** 40 exact-content groups remain intentionally. Most are source-relative textures or neutral UI elements. Deduplicating them safely should wait until actual Godot scenes establish which variants are used.

## Suitable prototype game directions

The current collection is sufficient for asset prototyping of:

- a third-person obstacle race with moving platforms, ramps, hazards and finish gates;
- a party-style checkpoint course with AI-literacy multiple-choice questions;
- a timed collection or delivery challenge using the adventurer characters and equipment props;
- a reaction game using buttons, levers, target props, UI signals and confirm/error audio;
- an animation evaluation sandbox for comparing idle, movement, special and simulation clips;
- a greybox-first course editor using Prototype Bits before replacing pieces with the Platformer Pack.

These are capability observations only. No formal minigame, level or gameplay logic was created.

## Final verification summary

| Check | Result |
| --- | --- |
| Original ZIP count | 7 |
| Original ZIP hashes unchanged | 7 / 7 |
| Runtime asset files | 2,526 |
| Required license/source files | 7 files: 6 preserved texts + 1 source register |
| GLTF JSON errors | 0 |
| Missing GLTF buffers/textures | 0 |
| Invalid GLB/PNG/OGG/TTF signatures | 0 |
| Invalid SVG files | 0 |
| Formal FBX/OBJ/MTL/WAV files | 0 |
| Non-snake_case asset directories | 0 |
| Gameplay/project files changed | 0 |

Status: **asset audit and organization complete; ready for a separate Godot project initialization/import phase.**
