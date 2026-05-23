# CLAUDE.md

Project-specific guidance for Claude Code when working in this repo.

The full conventions live in [AGENTS.md](AGENTS.md) — read that first. The points below highlight the parts most often gotten wrong by AI assistants.

## Fast loop

After any code change in `*.gd`, the test cycle is:

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot --path . > /dev/null 2>&1 &
```

Or use the MCP tool `mcp__godot-standard__run_project` then `mcp__godot-standard__get_debug_output`. The Godot window relaunches; the user gives visual feedback.

## Per-asset tuning, not global magic numbers

Each `.glb` has a different native scale and pivot. Tune **per asset** in the `kinds` array in `_setup_mushrooms()` and in the per-animal blocks in `_setup_animals()`. Don't apply a global scale.

`mushroom.glb` has its pivot in the cap, not the base — its Y uses a quadratic lift formula:

```gdscript
y = y_off + 0.6 * (scale - 1) + 0.15 * (scale - 1)^2
```

Dancing mushroom uses `y = y_off * scale` (negative offset scales with size).

## glTF facing

`look_at()` makes `+Z` forward, but glTF / Blender exports use `-Z` forward. After every `look_at`, follow with:

```gdscript
node.rotate_object_local(Vector3.UP, PI)
```

Both the frogs (face camera) and the opossum (walk forward) rely on this flip.

## Animation gating

Animations loop via `Animation.LOOP_LINEAR` and toggle with the play button via the `_anim_players` list. New animated models must go through `_play_first_animation()` — don't call `anim.play()` directly.

## Opossum behavior

The opossum wanders in `_process` gated on `_metronome.is_playing()`. `_process` runs unconditionally — gate any new per-frame work behind the playing flag.

## look_at before add_child

Never call `look_at()` on a node before it is in the scene tree — it will error with "Node not inside tree." Always `add_child()` first, then orient.

## Memory notes

The `.remember/` directory holds session notes from prior conversations. They're informational only — not authoritative. Code is the source of truth. If a memory says something the code contradicts, trust the code and update the memory.
