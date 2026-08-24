# Experiment event interface

The Godot prototype now exposes an in-memory, anonymous event stream through the
`ExperimentSession` autoload. In a production Web build, the browser bridge
persists this stream to IndexedDB and uploads it only after adult consent.

## Session metadata

- `schema_version`: currently `2`.
- `session_id`: locally generated anonymous run identifier.
- `condition`: `unassigned`, `active`, or `passive`.

`active` can invite on idle, no progress, quiz errors, repeated failures, or a
repeated ineffective strategy. `passive` uses the same Bot but calls it only
after the student opens the assistant manually. `unassigned` is development-only.

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

Scaffolding events include `scaffold_eligible`, `scaffold_triggered`,
`scaffold_invitation_shown`, `scaffold_accepted`, `scaffold_rejected`,
`scaffold_dismissed`, `choice_before_scaffold`, `choice_after_scaffold`,
`support_started`, `support_ended`, and `level_time_summary`. Their payloads use
an anonymous `scaffold_id` and include `scaffold_level`, `trigger_reason`,
`scaffold_version`, checkpoint/area, and intervention index. Trigger reasons are
`idle`, `no_progress`, `repeated_failure`, `quiz_error`, `repeated_strategy`, or
`manual`.

`level_time_summary` records mutually exclusive `gameplay_time`, `quiz_time`,
and `scaffold_time` values in seconds. A visible invitation remains gameplay
time; scaffold time starts only after acceptance or manual opening.

The Web bridge writes each emitted event to IndexedDB, creates the JSONL and
summary at four-level completion, records only the Godot Canvas, retries uploads,
and waits for the server-authored manifest before showing final success.
