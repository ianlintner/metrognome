# Agent Instructions

These conventions apply to any AI coding agent (Claude Code, Copilot CLI, Cursor, etc.) editing this repo. Human contributors should follow them too.

## Project context

- **Engine:** Godot 4.6 (Mono / .NET 9)
- **Language:** C# only — no GDScript
- **Entry:** `Main.tscn` → `Main.cs`. Everything is built procedurally in `Main._Ready()`; there are no other scenes.
- **Assets:** `.glb` models under `assets/`. New models require a Godot editor import pass (`godot --headless --editor --import`) to generate `.import` sidecar files.

## Build / format / lint

```bash
dotnet build                       # must succeed with 0 errors, 0 warnings
dotnet format --verify-no-changes  # style check
```

Both are enforced in CI (`.github/workflows/ci.yml`). Run them before claiming a task is done.

## Coding style

- C# idiomatic, not GDScript ported to C#.
- `[Signal]` delegates for cross-class events; named `XxxEventHandler`.
- Prefer composition in `Main.cs` over deep node trees in `.tscn` files.
- Per-asset tuning lives in named tuples / dictionaries near the placement code, **not** scattered as magic numbers.
- Avoid `_Process` work that runs every frame unless it gates on `_metronome.IsPlaying` (or similar) first.
- No comments that restate the code. Comments only for non-obvious *why* — e.g., "mushroom.glb's pivot sits in the middle of the cap" explains a Y-offset formula.

## Asset placement conventions

When adding 3D models:

1. Copy the `.glb` to `assets/<category>/`.
2. Run `godot --headless --editor --import --path .` once to generate `.import` sidecars.
3. Add the path to the relevant placement list in `Main.cs` (mushrooms have a `kinds` tuple array; animals are spawned inline).
4. Provide a per-asset `ScaleMin/Max` and `YOffset` if the model's pivot or native scale differs from the others.
5. Check for camera-blocking placement: the camera is at `(0, 5, -14)` looking at `(0, 1.4, 0)` — keep nothing in `|x| < 3.5 && z < 3`.

## Animation handling

Animations are looped (`Animation.LoopModeEnum.Linear`) and paused/resumed with the play button via the `_animPlayers` list in `Main.cs`. New animated assets that should follow the metronome state must go through `PlayFirstAnimation()` so they're registered in the list.

## Don't

- Don't add GDScript files.
- Don't add new scenes — extend `Main.cs`.
- Don't commit `.godot/`, `bin/`, `obj/`, or any `.import` sidecars whose source `.glb` isn't committed.
- Don't add libraries / NuGet packages without explicit ask — keep the dependency surface minimal.
- Don't add silent fallbacks. If a `GD.Load<PackedScene>` returns null, log via `GD.PrintErr` (gnome example) or skip gracefully — but don't swallow the failure.

## When in doubt

Read `Main.cs` end to end before editing — the whole composition is there, and it's the source of truth for how subsystems wire together.
