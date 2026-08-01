# Experiment event interface

The Godot prototype now exposes an in-memory, anonymous event stream through the
`ExperimentSession` autoload. It does not write files, upload data, record video,
or collect student identity.

## Session metadata

- `schema_version`: currently `1`.
- `session_id`: locally generated anonymous run identifier.
- `condition`: `unassigned`, `control`, `active`, or `passive`.

The project only provides the condition interface. It does not implement the
learning assistant's active/passive intervention logic.

## Event shape

Every event contains:

- `schema_version`
- `session_id`
- `condition`
- `event_name`
- `level_id`
- `elapsed_msec`
- `payload`

Current core events include `session_started`, `condition_assigned`,
`level_prepared`, `run_started`, `jump_used`, `dash_used`, `obstacle_hit`,
`player_fell`, `player_respawned`, `quiz_opened`, `quiz_answered`,
`checkpoint_completed`, `run_completed`, and `level_result_recorded`.

Call `ExperimentSession.get_snapshot()` when the future persistence or upload
module needs a serializable copy of the current session. The caller must add
consent handling, local durability, upload retry, and server-side validation.
