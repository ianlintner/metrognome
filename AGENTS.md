# Agent Instructions

These conventions apply to any AI coding agent (Claude Code, Copilot CLI, Cursor, etc.) editing this repo. Human contributors should follow them too.

## Project context

- **Engine:** Godot 4.6 (standard, no Mono/.NET)
- **Language:** GDScript only — no C#
- **Entry:** `Main.tscn` → `main.gd`. Everything is built procedurally in `_ready()`; there are no other scenes.
- **Assets:** `.glb` models under `assets/`. New models require a Godot editor import pass (`godot --headless --editor --import --path .`) to generate `.import` sidecar files.

## Validate / check

```bash
# Parse-check all GDScript (no errors = success)
godot --headless --quit --path .

# macOS
/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .
```

Run this before claiming a task is done. The CI job (`validate`) does the same thing.

## Coding style

- Idiomatic GDScript 4 — typed variables (`var x: float`), typed function signatures, `@export` annotations where appropriate.
- Snake_case for variables and functions; PascalCase for class names only.
- Signals declared at the top of each file with typed parameters.
- Prefer composition in `main.gd` over deep node trees in `.tscn` files.
- Per-asset tuning (scale, Y-offset) lives in named data structures near the placement code — not scattered as magic numbers.
- Gate `_process` work behind `_metronome.is_playing()` (or equivalent). Don't burn CPU every frame when paused.
- No comments that restate the code. Comments only for non-obvious *why* — e.g., "mushroom.glb pivot is in the cap" explains a Y-offset formula.

## glTF facing

`look_at()` makes `+Z` forward, but glTF / Blender exports use `−Z` forward. After every `look_at`, follow with:

```gdscript
node.rotate_object_local(Vector3.UP, PI)
```

Both frogs (face camera) and opossum (walk forward) require this flip.

## Asset placement conventions

When adding 3D models:

1. Copy the `.glb` to `assets/<category>/`.
2. Run `godot --headless --editor --import --path .` once to generate `.import` sidecars.
3. Add the path to the relevant placement block in `main.gd` (mushrooms have a `kinds` array; animals are spawned inline).
4. Provide per-asset scale and Y-offset if the model's pivot or native scale differs.
5. Keep nothing in `|x| < 3.5 && z < 3` — that corridor is the camera sightline to the gnome line. Camera is at `(0, 5, −14)` looking at `(0, 1.4, 0)`.

## Mushroom Y-offset formulas

`mushroom.glb` has its pivot in the cap (not the base):

```gdscript
y = y_off + 0.6 * (scale - 1) + 0.15 * (scale - 1)²
```

`dancing_mushroom.glb` pivot scales with size:

```gdscript
y = y_off * scale
```

All other mushrooms: `y = y_off` (flat).

## Animation handling

Animations loop via `Animation.LOOP_LINEAR` and pause/resume with the play button via the `_anim_players` list in `main.gd`. New animated assets that should follow the metronome state must go through `_play_first_animation()` so they're registered in the list.

## Don't

- Don't add C# files or reference .NET tooling.
- Don't add new `.tscn` scenes — extend `main.gd`.
- Don't commit `.godot/`, or any `.import` sidecars whose source `.glb` isn't committed.
- Don't add plugins or addons without an explicit ask.
- Don't use `call_deferred` or `await` unless the deferred execution is genuinely required — prefer synchronous logic in `_ready`.
- Don't swallow null returns silently. If `load()` returns null, call `push_error()` and return early.

## When in doubt

Read `main.gd` end to end before editing — it is the composition root and the source of truth for how subsystems wire together.
