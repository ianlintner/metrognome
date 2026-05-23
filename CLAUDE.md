# CLAUDE.md

Project-specific guidance for Claude Code when working in this repo.

The full conventions live in [AGENTS.md](AGENTS.md) — read that first. The points below highlight the parts most often gotten wrong by AI assistants.

## Fast loop

After any code change in `*.cs`, the test cycle is:

```bash
pkill -f "Godot.*metrognome" 2>/dev/null; sleep 1
dotnet build && /Applications/Godot_mono.app/Contents/MacOS/Godot --path . > /dev/null 2>&1 &
```

(On Linux/Windows, swap the binary path.) The Godot window auto-relaunches; the user gives visual feedback.

## Per-asset tuning, not global magic numbers

Each `.glb` has a different native scale and pivot. Tune **per asset** in the `kinds` tuple array in `SetupMushrooms()` and in the per-animal blocks in `SetupAnimals()`. Don't apply a global scale.

`mushroom.glb` in particular has its pivot in the cap, not the base — its Y uses a quadratic lift formula:
```
y = entry.Y + 0.6 * (scale - 1) + 0.15 * (scale - 1)^2
```
Dancing mushroom uses `y = entry.Y * scale` (negative offset scales with size).

## glTF facing

`Node3D.LookAt()` makes `+Z` forward, but glTF / Blender exports use `-Z` forward. After every `LookAt`, follow with:
```csharp
node.RotateObjectLocal(Vector3.Up, Mathf.Pi);
```
Both the frogs (face camera) and the opossum (walk forward) rely on this flip.

## Animation gating

Animations are looped via `Animation.LoopModeEnum.Linear` and toggled by the play button using the `_animPlayers` list. New animated models must register through `PlayFirstAnimation()` — don't `anim.Play()` directly.

## Opossum behavior

The opossum has a wandering loop in `_Process` gated on `_metronome.IsPlaying`. Stay aware that `_Process` runs unconditionally — gate any new per-frame work behind the playing flag.

## Memory notes

The `.remember/` directory holds session notes from prior conversations. They're informational only — not authoritative. Code is the source of truth. If a memory says something the code contradicts, trust the code and update the memory.
