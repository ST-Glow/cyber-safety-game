# Godot optimization evidence

## Reproducible commands

Run the functional smoke suite from the `godot` directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run_smoke_tests.ps1
```

Pass `-GodotExe <path>` or set `GODOT4_BIN` to use another Godot 4.7.1 console executable. The runner rejects non-zero exits, missing success sentinels, script/parse errors, resource leaks, and ObjectDB leaks. The exact Windows root-certificate-store error is the only allowed environment diagnostic.

Run the deterministic performance suite:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run_performance_benchmark.ps1 -Runs 3 -WarmupSeconds 5 -SampleSeconds 30
```

Each scenario is capped at 60 FPS, warmed for 5 seconds, and sampled for 30 seconds. Values below are the median of three runs. Headless rendering reports zero draw calls, so draw calls must be assessed in the exported Web build.

## Baseline — 2026-08-01

Godot: `4.7.1.stable.official.a13da4feb`, Compatibility renderer, headless Dummy audio.

| Scenario | Ready ms | Frame median ms | Frame P95 ms | Process median ms | Physics median ms | Static memory bytes | Objects | Resources |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Main running | 269.179 | 16.666 | 16.776 | 0.197 | 0.671 | 74,476,455 | 2,588 | 197 |
| Spinner active | 342.699 | 16.664 | 16.798 | 0.203 | 0.749 | 94,923,090 | 2,679 | 214 |
| Collection with 12 chips | 336.850 | 15.677 | 29.886 | 0.249 | 0.400 | 77,795,338 | 2,576 | 243 |
| Survival wave 3 | 378.433 | 15.678 | 30.016 | 0.245 | 0.382 | 103,377,230 | 2,824 | 237 |

Existing Web artifact sizes before the optimization work:

- `index.pck`: 9,192,488 bytes
- `index.wasm`: 37,900,721 bytes
- `index.js`: 315,645 bytes

## Decision gates

- Animation lookup, HUD diffing, and inactive-object processing may be retained when functional tests pass and process/P95 metrics do not regress by more than 3%.
- A shared immutable resource factory is adopted only if median scene-ready time or static memory improves by at least 5% in an affected scenario and P95 frame time does not regress by more than 3%.
- Dynamic emissive, pulsing, color-changing, or transparent materials remain instance-owned regardless of measurements.

## Animation and rig characterization

The runtime combines 53 animations. All eight gameplay tokens resolve to the intended KayKit libraries, and all 263 tracks in the selected clips target nodes or bones present in the Ranger Rig Medium hierarchy. `Idle_A` and `Running_A` arrive with looping disabled. That state is recorded explicitly and remains unchanged during the behavior-preserving performance phase; character movement continues to be driven by `CharacterBody3D`, without root-motion displacement.

## Post-optimization results

The first hot-path pass was also compared against `bea06b9` in a detached worktree during the same measurement window. This shorter gate used three runs with a 3-second warmup and 10-second sample so that system load was comparable before committing the change.

| Scenario | Baseline P95 ms | Hot-path P95 ms | Baseline process ms | Hot-path process ms | Process change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Main running | 16.780 | 16.757 | 0.236 | 0.206 | -12.7% |
| Spinner active | 16.818 | 16.771 | 0.231 | 0.218 | -5.6% |
| Collection with 12 chips | 16.748 | 16.749 | 0.256 | 0.247 | -3.5% |
| Survival wave 3 | 16.768 | 16.753 | 0.282 | 0.270 | -4.3% |

All P95 changes are within 0.3%, and the median process time improved in all four scenarios. The definitive 5-second/30-second suite and Web-rendering checks remain part of final verification.
